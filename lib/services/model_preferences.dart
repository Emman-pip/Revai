import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ModelPreferences {
  ModelPreferences({Future<File> Function()? file})
    : _file = file ?? _defaultFile;

  final Future<File> Function() _file;

  static Future<File> _defaultFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/model_preferences.json');
  }

  Future<String?> loadSelectedId() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is Map && value['selectedModelId'] is String) {
        return value['selectedModelId'] as String;
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> saveSelectedId(String? id) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'selectedModelId': id}),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
