import 'dart:io';

import 'package:flutter/services.dart';

class GenerationNotifications {
  static const _channel = MethodChannel('com.revai/generation');

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  Future<void> start() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('start');
  }

  Future<void> update(String title, String stage, int waiting) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('update', {
      'title': title,
      'stage': stage,
      'waiting': waiting,
    });
  }

  Future<void> completed(String title, bool success) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('completed', {
      'title': title,
      'success': success,
    });
  }

  Future<void> stop() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
  }
}
