import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/quiz.dart';

typedef QuizLibrary = ({List<SavedQuiz> quizzes, List<QuizFolder> folders});

class QuizStorage extends ChangeNotifier {
  QuizStorage({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _pendingWrite = Future.value();

  Future<QuizLibrary> loadLibrary() async {
    await _pendingWrite;
    return _read();
  }

  Future<QuizLibrary> _read() async {
    final directory = await _directory();
    final file = File('${directory.path}/quiz_library.json');
    if (!await file.exists()) {
      final legacy = File('${directory.path}/saved_quizzes.json');
      return (
        quizzes: await legacy.exists()
            ? decodeQuizzes(await legacy.readAsString())
            : <SavedQuiz>[],
        folders: <QuizFolder>[],
      );
    }
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (
      quizzes: (json['quizzes'] as List)
          .map(
            (value) =>
                SavedQuiz.fromJson(Map<String, Object?>.from(value as Map)),
          )
          .toList(),
      folders: (json['folders'] as List)
          .map(
            (value) =>
                QuizFolder.fromJson(Map<String, Object?>.from(value as Map)),
          )
          .toList(),
    );
  }

  Future<List<SavedQuiz>> load() async => (await loadLibrary()).quizzes;

  Future<void> _mutate(void Function(QuizLibrary) edit) {
    final operation = _pendingWrite.then((_) async {
      final library = await _read();
      edit(library);
      final directory = await _directory();
      final file = File('${directory.path}/quiz_library.json');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'quizzes': library.quizzes.map((quiz) => quiz.toJson()).toList(),
          'folders': library.folders.map((folder) => folder.toJson()).toList(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
      notifyListeners();
    });
    // Failed writes are reported to their caller without blocking future writes.
    _pendingWrite = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> save(SavedQuiz quiz) => _mutate((library) {
    library.quizzes.removeWhere((item) => item.id == quiz.id);
    final folderExists = library.folders.any(
      (folder) => folder.id == quiz.folderId,
    );
    library.quizzes.insert(0, folderExists ? quiz : quiz.withFolder(null));
  });

  Future<void> delete(String id) => _mutate(
    (library) => library.quizzes.removeWhere((quiz) => quiz.id == id),
  );

  Future<void> move(Set<String> ids, String? folderId) => _mutate((library) {
    if (folderId != null &&
        !library.folders.any((folder) => folder.id == folderId)) {
      throw StateError('This folder no longer exists.');
    }
    for (var i = 0; i < library.quizzes.length; i++) {
      if (ids.contains(library.quizzes[i].id)) {
        library.quizzes[i] = library.quizzes[i].withFolder(folderId);
      }
    }
  });

  Future<void> createFolder(String name) => _mutate((library) {
    final trimmed = _validateName(name, library.folders);
    library.folders.add(
      QuizFolder(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: trimmed,
      ),
    );
  });

  Future<void> renameFolder(String id, String name) => _mutate((library) {
    final index = library.folders.indexWhere((folder) => folder.id == id);
    if (index < 0) throw StateError('This folder no longer exists.');
    final trimmed = _validateName(
      name,
      library.folders.where((folder) => folder.id != id),
    );
    library.folders[index] = QuizFolder(id: id, name: trimmed);
  });

  Future<void> deleteFolder(String id) => _mutate((library) {
    library.folders.removeWhere((folder) => folder.id == id);
    for (var i = 0; i < library.quizzes.length; i++) {
      if (library.quizzes[i].folderId == id) {
        library.quizzes[i] = library.quizzes[i].withFolder(null);
      }
    }
  });

  String _validateName(String value, Iterable<QuizFolder> folders) {
    final name = value.trim();
    if (name.isEmpty || name.length > 60) {
      throw StateError('Use a folder name between 1 and 60 characters.');
    }
    if (folders.any(
      (folder) => folder.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw StateError('A folder with that name already exists.');
    }
    return name;
  }
}
