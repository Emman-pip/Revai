import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'model_catalog.dart';

abstract interface class LocalModelBackend {
  Future<void> initialize();
  String? get activeFileName;
  Future<bool> isInstalled(LocalAiModel model);
  Future<void> activate(LocalAiModel? model);
  Future<void> download(LocalAiModel model, void Function(int) onProgress);
  Future<void> remove(LocalAiModel model);
  Future<InferenceModel> load(LocalAiModel model);
}

class GemmaModelBackend implements LocalModelBackend {
  @override
  Future<void> initialize() =>
      FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);

  @override
  String? get activeFileName =>
      FlutterGemma.activeModelSpec?.files.first.filename;

  @override
  Future<bool> isInstalled(LocalAiModel model) =>
      FlutterGemma.isModelInstalled(model.fileName);

  @override
  Future<void> activate(LocalAiModel? model) async {
    if (model == null) {
      await FlutterGemma.clearActiveInferenceIdentity();
      return;
    }
    final manager = FlutterGemmaPlugin.instance.modelManager;
    await manager.ensureInitialized();
    manager.setActiveModel(
      InferenceModelSpec(
        name: model.id,
        modelSource: ModelSource.network(model.url, foreground: true),
        modelType: model.modelType,
        fileType: ModelFileType.litertlm,
      ),
    );
  }

  @override
  Future<void> download(
    LocalAiModel model,
    void Function(int) onProgress,
  ) async {
    await FlutterGemma.installModel(
          modelType: model.modelType,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(model.url, foreground: true)
        .withProgress(onProgress)
        .install();
  }

  @override
  Future<void> remove(LocalAiModel model) =>
      FlutterGemma.uninstallModel(model.fileName);

  @override
  Future<InferenceModel> load(LocalAiModel model) =>
      FlutterGemma.getActiveModel(
        maxTokens: model.contextTokens,
        preferredBackend: model.preferredBackend,
      );
}
