import 'package:flutter/services.dart';

class DeviceReadiness {
  static const _channel = MethodChannel('com.revai/device_info');
  static const _minimumStorage = 3 * 1024 * 1024 * 1024;
  static const _minimumMemory = 8 * 1024 * 1024 * 1024;

  Future<String?> checkForModelDownload({
    int requiredFreeBytes = _minimumStorage,
  }) async {
    try {
      final values = await _channel.invokeMapMethod<String, int>(
        'getDeviceInfo',
      );
      if (values == null) {
        return 'Could not check this device. Try restarting the app.';
      }
      if ((values['sdkInt'] ?? 0) < 31) {
        return 'Revai requires Android 12 or newer.';
      }
      if ((values['totalMemory'] ?? 0) < _minimumMemory) {
        return 'The local model needs a phone with at least 8 GB RAM.';
      }
      if ((values['availableStorage'] ?? 0) < requiredFreeBytes) {
        final gigabytes = (requiredFreeBytes / 1000000000).toStringAsFixed(1);
        return 'Free at least $gigabytes GB of storage, then try again.';
      }
      return null;
    } on PlatformException {
      return 'Could not check this device. Try restarting the app.';
    }
  }
}
