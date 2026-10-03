import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/model_catalog.dart';
import 'package:revai/services/model_preferences.dart';
import 'package:revai/services/quiz_generator.dart';

import 'support/fake_model_backend.dart';

void main() {
  final gemma = localAiModels[0];
  final larger = localAiModels[1];
  final compact = localAiModels[2];
  late FakeModelBackend backend;
  late MemoryModelPreferences preferences;
  late LocalModelService service;

  setUp(() {
    backend = FakeModelBackend();
    preferences = MemoryModelPreferences();
    service = LocalModelService(backend: backend, preferences: preferences);
  });

  tearDown(() => service.dispose());

  test(
    'Migrates an installed Gemma without downloading or loading weights',
    () async {
      backend.installed.add(gemma.id);
      backend.active = gemma;
      await service.initialize();

      expect(service.selectedModel, gemma);
      expect(preferences.selectedId, gemma.id);
      expect(service.selectedInstalled, isTrue);
      expect(backend.downloads, isEmpty);
      expect(backend.loaded, isEmpty);
    },
  );

  test('Saved choice overrides the SDK identity left by a download', () async {
    backend.installed.addAll([gemma.id, compact.id]);
    backend.active = gemma;
    preferences.selectedId = compact.id;
    await service.initialize();

    expect(service.selectedModel, compact);
    expect(backend.active, compact);
    expect(await service.isInstalled(), isTrue);

    backend.installed.remove(compact.id);
    await service.initialize();
    expect(service.selectedModel, gemma);
    expect(preferences.selectedId, gemma.id);
  });

  test(
    'First download selects a model; additional and failed downloads preserve it',
    () async {
      await service.initialize();
      expect(service.selectedModel, isNull);
      final progress = <int>[];
      await service.download(model: compact, onProgress: progress.add);
      expect(progress, [45, 100]);
      expect(service.selectedModel, compact);
      expect(preferences.selectedId, compact.id);

      await service.download(model: gemma, onProgress: (_) {});
      expect(service.isDownloaded(gemma), isTrue);
      expect(service.selectedModel, compact);
      expect(backend.active, compact);

      backend.failDownloads = true;
      await expectLater(
        service.download(model: larger, onProgress: (_) {}),
        throwsStateError,
      );
      expect(service.isDownloaded(larger), isFalse);
      expect(service.selectedModel, compact);
      expect(backend.active, compact);
      expect(service.canManage, isTrue);
      expect(service.downloadingId, isNull);
      backend.failDownloads = false;
      await service.download(model: larger, onProgress: (_) {});
      expect(service.isDownloaded(larger), isTrue);
      expect(service.selectedModel, compact);
    },
  );

  test(
    'Selection closes the cached engine and routes quiz and chat to the chosen model',
    () async {
      backend.installed.addAll([gemma.id, compact.id]);
      await service.initialize();
      final firstChat = await service.createChatSession();
      expect(await firstChat.sendMessage('Hello'), 'Local reply');
      await firstChat.close();
      await service.selectModel(compact);
      expect(backend.engines.first.closes, 1);

      expect(await service.generate('Quiz prompt'), 'Local reply');
      final nextChat = await service.createChatSession();
      await nextChat.close();

      expect(backend.loaded.map((model) => model.id), [gemma.id, compact.id]);
      expect(backend.loaded.last.contextTokens, 4096);
      expect(backend.loaded.last.preferredBackend, PreferredBackend.cpu);
      expect(backend.engines.last.chats, hasLength(2));
      for (final request in backend.engines.last.chats) {
        expect(request.namedArguments[#modelType], ModelType.qwen);
        expect(request.namedArguments[#maxOutputTokens], isNull);
      }
      expect(service.canManage, isTrue);
    },
  );

  test(
    'Management is blocked throughout chat loading and the open session',
    () async {
      backend.installed.addAll([gemma.id, compact.id]);
      backend.holdLoad = Completer<void>();
      await service.initialize();
      final opening = service.createChatSession();
      expect(service.isInUse, isTrue);
      await expectLater(service.selectModel(compact), throwsStateError);
      await expectLater(service.removeModel(gemma), throwsStateError);
      await expectLater(
        service.download(model: larger, onProgress: (_) {}),
        throwsStateError,
      );
      backend.holdLoad!.complete();
      final chat = await opening;
      await expectLater(service.selectModel(compact), throwsStateError);
      await chat.close();
      await chat.close();
      expect(service.canManage, isTrue);
      await service.selectModel(compact);
    },
  );

  test(
    'An unsaved selection rolls back the SDK identity and releases management',
    () async {
      backend.installed.addAll([gemma.id, compact.id]);
      await service.initialize();
      preferences.failWrites = true;
      await expectLater(service.selectModel(compact), throwsStateError);
      expect(service.selectedModel, gemma);
      expect(backend.active, gemma);
      expect(preferences.selectedId, gemma.id);
      expect(service.canManage, isTrue);
    },
  );

  test(
    'Removing the selection prefers Gemma E2B and clears the last selection',
    () async {
      backend.installed.addAll([gemma.id, larger.id, compact.id]);
      preferences.selectedId = compact.id;
      await service.initialize();
      await service.removeModel(compact);
      expect(service.selectedModel, gemma);
      expect(service.isDownloaded(compact), isFalse);
      await service.removeModel(gemma);
      expect(service.selectedModel, larger);
      await service.removeModel(larger);
      expect(service.selectedModel, isNull);
      expect(preferences.selectedId, isNull);
      expect(backend.active, isNull);
      expect(await service.isInstalled(), isFalse);
      expect(() => service.reserveSelection(), throwsStateError);
    },
  );

  test(
    'Failed removal restores the selected model when its file is still installed',
    () async {
      backend.installed.addAll([gemma.id, larger.id]);
      await service.initialize();
      backend.failRemovals = true;
      await expectLater(service.removeModel(gemma), throwsStateError);
      expect(service.selectedModel, gemma);
      expect(service.isDownloaded(gemma), isTrue);
      expect(backend.active, gemma);
      expect(service.canManage, isTrue);
    },
  );

  test(
    'Compact quiz requests reject oversized counts and coverage before inference',
    () async {
      backend.installed.add(compact.id);
      await service.initialize();
      final generator = QuizGenerator(service);
      const document = SourceDocument(
        name: 'notes.txt',
        extension: 'txt',
        sections: [
          SourceSection(
            id: 's1',
            label: 'Notes',
            text: 'Cells have membranes.',
          ),
        ],
      );
      QuizSettings settings(int count) => QuizSettings(
        title: 'Quiz',
        mode: ExamMode.identification,
        multipleChoiceCount: 0,
        identificationCount: count,
        easyCount: count,
        mediumCount: 0,
        hardCount: 0,
      );
      generator.validateRequest(document, settings(5));
      expect(
        () => generator.validateRequest(document, settings(6)),
        throwsStateError,
      );
      final longDocument = SourceDocument(
        name: 'long.txt',
        extension: 'txt',
        sections: [SourceSection(id: 's1', label: 'Notes', text: 'x' * 6001)],
      );
      expect(
        () => generator.validateRequest(longDocument, settings(1)),
        throwsStateError,
      );
      expect(backend.loaded, isEmpty);
    },
  );

  test(
    'Model preferences survive reload and tolerate missing or damaged files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'revai-model-prefs-',
      );
      try {
        final file = File('${directory.path}/model_preferences.json');
        final preferences = ModelPreferences(file: () async => file);
        expect(await preferences.loadSelectedId(), isNull);
        await preferences.saveSelectedId(compact.id);
        expect(
          await ModelPreferences(file: () async => file).loadSelectedId(),
          compact.id,
        );
        expect(await File('${file.path}.tmp').exists(), isFalse);
        await preferences.saveSelectedId(null);
        expect(await preferences.loadSelectedId(), isNull);
        await file.writeAsString('{broken');
        expect(await preferences.loadSelectedId(), isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
