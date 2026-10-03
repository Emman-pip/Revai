import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/quiz_storage.dart';
import 'package:revai/services/theme_preferences.dart';

SavedQuiz exampleQuiz(String id) => SavedQuiz(
  id: id,
  title: 'Quiz $id',
  documentName: 'notes.txt',
  createdAt: DateTime(2026),
  mode: ExamMode.identification,
  questions: const [],
);

void main() {
  late Directory directory;
  late QuizStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('revai-library-');
    storage = QuizStorage(directory: () async => directory);
  });
  tearDown(() async {
    storage.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Migrates legacy quizzes, persists folders and preserves quizzes on folder removal',
    () async {
      await File(
        '${directory.path}/saved_quizzes.json',
      ).writeAsString(encodeQuizzes([exampleQuiz('legacy')]));
      await storage.createFolder('Biology');
      var library = await storage.loadLibrary();
      final folder = library.folders.single;
      await storage.move({'legacy'}, folder.id);
      await storage.renameFolder(folder.id, 'Science');
      final reloaded = QuizStorage(directory: () async => directory);
      addTearDown(reloaded.dispose);
      library = await reloaded.loadLibrary();
      expect(library.folders.single.name, 'Science');
      expect(library.quizzes.single.folderId, folder.id);
      await storage.deleteFolder(folder.id);
      expect((await storage.load()).single.folderId, isNull);
      expect((await storage.load()).single.id, 'legacy');
    },
  );

  test('Concurrent saves and moves do not overwrite each other', () async {
    await storage.createFolder('Science');
    final folder = (await storage.loadLibrary()).folders.single.id;
    await Future.wait([
      storage.save(exampleQuiz('one')),
      storage.save(exampleQuiz('two')),
      storage.move({'one', 'two'}, folder),
    ]);
    final library = await storage.loadLibrary();
    expect(library.quizzes.length, 2);
    expect(library.quizzes.every((quiz) => quiz.folderId == folder), isTrue);
    await expectLater(storage.createFolder(' science '), throwsStateError);
    await storage.save(
      exampleQuiz('three'),
    ); // Failed writes must not block later ones.
    expect((await storage.load()).length, 3);
  });

  test(
    'Theme preference survives restart and rapid toggles retain the latest value',
    () async {
      Future<File> file() async => File('${directory.path}/theme.json');
      final preferences = ThemePreferences(file: file);
      expect(await preferences.loadDarkMode(), isNull);
      await Future.wait([
        preferences.saveDarkMode(true),
        preferences.saveDarkMode(false),
        preferences.saveDarkMode(true),
      ]);
      expect(await ThemePreferences(file: file).loadDarkMode(), isTrue);
      await (await file()).writeAsString('broken');
      expect(await preferences.loadDarkMode(), isNull);
    },
  );
}
