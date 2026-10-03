import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ThemePreferences {
  ThemePreferences({Future<File> Function()? file})
    : _file = file ?? _defaultFile;

  final Future<File> Function() _file;
  Future<void> _pendingWrite = Future.value();

  static Future<File> _defaultFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/theme.json');
  }

  /// A missing preference follows the device's theme until the first toggle.
  Future<bool?> loadDarkMode() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is Map && value['darkMode'] is bool) {
        return value['darkMode'] as bool;
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> saveDarkMode(bool dark) {
    // Keep rapid toggles in order so the last selection survives a restart.
    final write = _pendingWrite.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({'darkMode': dark}),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }
}
