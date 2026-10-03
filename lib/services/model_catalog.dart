import 'package:flutter_gemma/flutter_gemma.dart';

class LocalAiModel {
  const LocalAiModel({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.downloadBytes,
    required this.sizeLabel,
    required this.description,
    required this.modelType,
    required this.contextTokens,
    this.preferredBackend,
    this.maxQuizQuestions = 30,
    this.maxSourceCharacters = 26000,
  });

  final String id;
  final String name;
  final String fileName;
  final String url;
  final int downloadBytes;
  final String sizeLabel;
  final String description;
  final ModelType modelType;
  final int contextTokens;
  final PreferredBackend? preferredBackend;
  final int maxQuizQuestions;
  final int maxSourceCharacters;

  // Leave room for the download's temporary data and the rest of the app.
  int get requiredFreeBytes => downloadBytes + 512 * 1024 * 1024;
  String get quizLimits =>
      'Up to $maxQuizQuestions questions · $maxSourceCharacters source characters';
}

const localAiModels = [
  LocalAiModel(
    id: 'gemma-4-e2b',
    name: 'Gemma 4 E2B',
    fileName: 'gemma-4-E2B-it.litertlm',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    downloadBytes: 2600000000,
    sizeLabel: 'About 2.6 GB',
    description: 'The default model for document quizzes and offline chat.',
    modelType: ModelType.gemma4,
    contextTokens: 8192,
  ),
  LocalAiModel(
    id: 'gemma-4-e4b',
    name: 'Gemma 4 E4B',
    fileName: 'gemma-4-E4B-it.litertlm',
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    downloadBytes: 3660000000,
    sizeLabel: 'About 3.66 GB',
    description: 'A larger model for document quizzes and offline chat.',
    modelType: ModelType.gemma4,
    contextTokens: 8192,
  ),
  LocalAiModel(
    id: 'qwen-3-5-0-8b',
    name: 'Qwen3.5 0.8B',
    fileName: 'Qwen3.5-0.8B_int8.litertlm',
    url:
        'https://huggingface.co/litert-community/Qwen3.5-0.8B/resolve/main/Qwen3.5-0.8B_int8.litertlm',
    downloadBytes: 963184864,
    sizeLabel: 'About 963 MB',
    description: 'A small download for offline chat and short quizzes.',
    // Qwen3.5 uses ChatML, without Qwen3's /no_think user suffix.
    modelType: ModelType.qwen,
    contextTokens: 4096,
    // The text bundle's GPU compilation can exceed memory on Android phones.
    preferredBackend: PreferredBackend.cpu,
    maxQuizQuestions: 5,
    maxSourceCharacters: 6000,
  ),
];

LocalAiModel? modelById(String? id) =>
    localAiModels.where((model) => model.id == id).firstOrNull;
