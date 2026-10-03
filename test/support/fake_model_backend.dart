import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/services/local_model_backend.dart';
import 'package:revai/services/model_catalog.dart';
import 'package:revai/services/model_preferences.dart';

class MemoryModelPreferences extends ModelPreferences {
  String? selectedId;
  bool failWrites = false;

  @override
  Future<String?> loadSelectedId() async => selectedId;

  @override
  Future<void> saveSelectedId(String? id) async {
    if (failWrites) throw StateError('Storage unavailable');
    selectedId = id;
  }
}

class FakeModelBackend implements LocalModelBackend {
  final installed = <String>{};
  final loaded = <LocalAiModel>[];
  final engines = <FakeInferenceModel>[];
  final downloads = <String>[];
  LocalAiModel? active;
  bool failDownloads = false;
  bool failRemovals = false;
  Completer<void>? holdDownload;
  Completer<void>? holdLoad;

  @override
  Future<void> initialize() async {}

  @override
  String? get activeFileName => active?.fileName;

  @override
  Future<bool> isInstalled(LocalAiModel model) async =>
      installed.contains(model.id);

  @override
  Future<void> activate(LocalAiModel? model) async => active = model;

  @override
  Future<void> download(
    LocalAiModel model,
    void Function(int) onProgress,
  ) async {
    downloads.add(model.id);
    // Match the SDK's installation side effect even when simulating a failure.
    active = model;
    onProgress(45);
    if (holdDownload != null) await holdDownload!.future;
    if (failDownloads) throw StateError('Connection lost');
    installed.add(model.id);
    onProgress(100);
  }

  @override
  Future<void> remove(LocalAiModel model) async {
    if (failRemovals) throw StateError('Could not remove file');
    installed.remove(model.id);
    if (active?.id == model.id) active = null;
  }

  @override
  Future<InferenceModel> load(LocalAiModel model) async {
    loaded.add(model);
    if (holdLoad != null) await holdLoad!.future;
    final engine = FakeInferenceModel();
    engines.add(engine);
    return engine;
  }
}

class FakeInferenceModel extends Fake implements InferenceModel {
  final chats = <Invocation>[];
  int closes = 0;

  @override
  Future<void> close() async => closes++;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #openChat) {
      chats.add(invocation);
      return Future<InferenceChat>.value(FakeInferenceChat());
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeInferenceChat extends Fake implements InferenceChat {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #addQueryChunk:
      case #close:
      case #stopGeneration:
        return Future<void>.value();
      case #generateChatResponseAsync:
        return Stream<ModelResponse>.value(const TextResponse('Local reply'));
      default:
        return super.noSuchMethod(invocation);
    }
  }
}
