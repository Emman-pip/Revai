import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/generation_cancellation.dart';
import 'package:revai/services/generation_notifications.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/model_catalog.dart';
import 'package:revai/services/quiz_generation_queue.dart';
import 'package:revai/services/quiz_generator.dart';
import 'package:revai/services/quiz_storage.dart';

const document = SourceDocument(
  name: 'notes.txt',
  extension: 'txt',
  sections: [
    SourceSection(id: 't1', label: 'line 1', text: 'Cells have membranes.'),
  ],
);
QuizSettings settings(String title) => QuizSettings(
  title: title,
  mode: ExamMode.identification,
  multipleChoiceCount: 0,
  identificationCount: 1,
  easyCount: 1,
  mediumCount: 0,
  hardCount: 0,
);
SavedQuiz quiz(String title) => SavedQuiz(
  id: title,
  title: title,
  documentName: document.name,
  createdAt: DateTime(2026),
  mode: ExamMode.identification,
  questions: const [],
);

class Request {
  final result = Completer<SavedQuiz>();
  final cleanup = Completer<void>();
}

class ControlledGenerator extends QuizGenerator {
  ControlledGenerator() : super(LocalModelService());
  final requests = <Request>[];
  bool holdCleanup = false;
  @override
  Future<SavedQuiz> generate(
    SourceDocument document,
    QuizSettings settings, {
    GenerationCancellation? cancellation,
    void Function(String)? onStage,
    void Function(String)? onOutput,
  }) async {
    final request = Request();
    requests.add(request);
    cancellation?.check();
    if (cancellation != null) {
      cancellation.stopNative = () async {
        if (!request.result.isCompleted) {
          request.result.completeError(const GenerationCancelled());
        }
      };
    }
    onStage?.call('Writing questions');
    try {
      return await request.result.future;
    } finally {
      if (holdCleanup) await request.cleanup.future;
      if (cancellation != null) cancellation.stopNative = null;
    }
  }
}

class FakeNotifications extends GenerationNotifications {
  int starts = 0;
  int stops = 0;
  int completions = 0;
  bool fail = false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> start() async {
    starts++;
    if (fail) throw StateError('unavailable');
  }

  @override
  Future<void> update(String title, String stage, int waiting) async {}
  @override
  Future<void> completed(String title, bool success) async {
    completions++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'Queue did not reach the expected state');
}

void main() {
  late Directory directory;
  late QuizStorage storage;
  late ControlledGenerator generator;
  late FakeNotifications notifications;
  late QuizGenerationQueue queue;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('revai-queue-');
    storage = QuizStorage(directory: () async => directory);
    generator = ControlledGenerator();
    notifications = FakeNotifications();
    queue = QuizGenerationQueue(
      generator: generator,
      storage: storage,
      notifications: notifications,
    );
  });
  tearDown(() async {
    queue.dispose();
    storage.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Queued jobs cancel without entering the model or saving a quiz',
    () async {
      await queue.enqueue(document, settings('one'));
      await queue.enqueue(document, settings('two'));
      await until(() => generator.requests.length == 1);
      expect(generator.model.isInUse, isTrue);
      await expectLater(
        generator.model.selectModel(localAiModels.last),
        throwsStateError,
      );
      await queue.cancel(queue.jobs[1]);
      generator.requests.first.result.complete(quiz('one'));
      await until(() => notifications.stops == 1);
      expect(generator.requests.length, 1);
      expect(queue.jobs[1].status, GenerationStatus.cancelled);
      expect((await storage.load()).map((item) => item.id), ['one']);
      expect(generator.model.canManage, isTrue);
    },
  );

  test(
    'Active cancellation waits for native cleanup before starting the next job',
    () async {
      generator.holdCleanup = true;
      await queue.enqueue(document, settings('one'));
      await queue.enqueue(document, settings('two'));
      await until(() => generator.requests.length == 1);
      await queue.cancel(queue.jobs.first);
      expect(queue.jobs.first.status, GenerationStatus.stopping);
      expect(generator.model.isInUse, isTrue);
      expect(generator.requests.length, 1);
      expect(await storage.load(), isEmpty);
      generator.requests.first.cleanup.complete();
      await until(() => generator.requests.length == 2);
      expect(queue.jobs.first.status, GenerationStatus.cancelled);
      generator.requests[1].cleanup.complete();
      generator.requests[1].result.complete(quiz('two'));
      await until(() => notifications.stops == 1);
      expect((await storage.load()).map((item) => item.id), ['two']);
      expect(notifications.completions, 1);
      expect(generator.model.canManage, isTrue);
    },
  );

  test(
    'One failed generation and notification failure do not block later jobs',
    () async {
      notifications.fail = true;
      await queue.enqueue(document, settings('one'));
      await queue.enqueue(document, settings('two'));
      await until(() => generator.requests.length == 1);
      generator.requests.first.result.completeError(
        StateError('Invalid generated quiz'),
      );
      await until(() => generator.requests.length == 2);
      generator.requests[1].result.complete(quiz('two'));
      await until(() => notifications.stops == 1);
      expect(queue.jobs.first.status, GenerationStatus.failed);
      expect(queue.jobs.last.status, GenerationStatus.completed);
      expect(queue.notificationNotice, isNotNull);
      expect((await storage.load()).single.id, 'two');
    },
  );

  test(
    'Deleting a destination folder during generation saves into Ungrouped',
    () async {
      await storage.createFolder('Biology');
      final folderId = (await storage.loadLibrary()).folders.single.id;
      await queue.enqueue(document, settings('one'), folderId: folderId);
      await until(() => generator.requests.length == 1);
      await storage.deleteFolder(folderId);
      generator.requests.first.result.complete(quiz('one'));
      await until(() => notifications.stops == 1);
      expect((await storage.load()).single.folderId, isNull);
    },
  );

  test('A failed job can be recovered as a saved manual draft', () async {
    await queue.enqueue(document, settings('manual'));
    await until(() => generator.requests.length == 1);
    generator.requests.single.result.completeError(StateError('model failed'));
    await until(() => queue.jobs.single.status == GenerationStatus.failed);

    await queue.createManualDraft(queue.jobs.single);

    expect(queue.jobs.single.status, GenerationStatus.completed);
    expect(queue.jobs.single.quiz!.questions, isEmpty);
    expect((await storage.load()).single.title, 'manual');
  });
}
