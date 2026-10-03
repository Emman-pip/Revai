import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'generation_cancellation.dart';
import 'local_model_backend.dart';
import 'model_catalog.dart';
import 'model_preferences.dart';

class LocalModelService extends ChangeNotifier {
  LocalModelService({LocalModelBackend? backend, ModelPreferences? preferences})
    : _backend = backend ?? GemmaModelBackend(),
      _preferences = preferences ?? ModelPreferences();

  final LocalModelBackend _backend;
  final ModelPreferences _preferences;
  InferenceModel? _model;
  Future<InferenceModel>? _loading;
  LocalAiModel? _selectedModel = localAiModels.first;
  Set<String> _installedIds = {};
  int _reservations = 0;
  bool _managing = false;
  String? _downloadingId;
  int _downloadProgress = 0;

  LocalAiModel? get selectedModel => _selectedModel;
  bool isDownloaded(LocalAiModel model) => _installedIds.contains(model.id);
  bool get selectedInstalled =>
      _selectedModel != null && isDownloaded(_selectedModel!);
  bool get isInUse => _reservations > 0;
  bool get isManaging => _managing;
  bool get canManage => !_managing && !isInUse;
  String? get downloadingId => _downloadingId;
  int get downloadProgress => _downloadProgress;

  Future<void> initialize() async {
    _beginManagement();
    try {
      await _backend.initialize();
      await _refreshInstalledModels();
      final saved = modelById(await _preferences.loadSelectedId());
      final previous = localAiModels
          .where((model) => model.fileName == _backend.activeFileName)
          .firstOrNull;
      final next = [
        saved,
        previous,
        ...localAiModels,
      ].whereType<LocalAiModel>().where(isDownloaded).firstOrNull;
      await _changeSelection(next);
    } finally {
      _endManagement();
    }
  }

  Future<void> _refreshInstalledModels() async {
    final installed = <String>{};
    for (final model in localAiModels) {
      if (await _backend.isInstalled(model)) installed.add(model.id);
    }
    _installedIds = installed;
  }

  Future<bool> isInstalled() async {
    final selected = _selectedModel;
    return selected != null && await _backend.isInstalled(selected);
  }

  void _beginManagement() {
    if (_managing) {
      throw StateError('Wait for the current model operation to finish.');
    }
    if (isInUse) {
      throw StateError(
        'Finish or cancel quiz jobs and leave AI chat before changing models.',
      );
    }
    _managing = true;
    notifyListeners();
  }

  void _endManagement() {
    _managing = false;
    _downloadingId = null;
    notifyListeners();
  }

  /// Holds the selection through queued jobs, model loading, and session cleanup.
  /// Call the returned function once the owner has released its native session.
  VoidCallback reserveSelection() {
    if (_managing) throw StateError('Wait for model setup to finish.');
    if (_selectedModel == null) {
      throw StateError('Download and select an AI model on the home screen.');
    }
    _reservations++;
    notifyListeners();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _reservations--;
      notifyListeners();
    };
  }

  Future<void> _closeCachedModel() async {
    final previous = _model;
    _model = null;
    if (previous != null) await previous.close();
  }

  Future<void> _changeSelection(LocalAiModel? next) async {
    final previous = _selectedModel;
    await _closeCachedModel();
    try {
      await _backend.activate(next);
      await _preferences.saveSelectedId(next?.id);
    } catch (_) {
      await _backend.activate(
        previous != null && isDownloaded(previous) ? previous : null,
      );
      rethrow;
    }
    _selectedModel = next;
  }

  Future<void> selectModel(LocalAiModel model) async {
    _beginManagement();
    try {
      if (!isDownloaded(model) || !await _backend.isInstalled(model)) {
        throw StateError('Download ${model.name} before selecting it.');
      }
      await _changeSelection(model);
    } finally {
      _endManagement();
    }
  }

  Future<void> removeModel(LocalAiModel model) async {
    _beginManagement();
    final previous = _selectedModel;
    final wasSelected = previous?.id == model.id;
    try {
      if (wasSelected) {
        final fallback = localAiModels
            .where((item) => item.id != model.id && isDownloaded(item))
            .firstOrNull;
        await _changeSelection(fallback);
      }
      try {
        await _backend.remove(model);
      } catch (_) {
        if (wasSelected && await _backend.isInstalled(model)) {
          await _changeSelection(previous);
        }
        rethrow;
      }
      _installedIds.remove(model.id);
    } finally {
      try {
        await _refreshInstalledModels();
      } finally {
        _endManagement();
      }
    }
  }

  Future<InferenceModel> _loadedModel() {
    if (_model != null) return Future.value(_model!);
    // Chat and quiz generation can both request a session while the engine loads.
    return _loading ??= _loadSelectedModel().whenComplete(
      () => _loading = null,
    );
  }

  Future<InferenceModel> _loadSelectedModel() async {
    final selected = _selectedModel!;
    if (!await _backend.isInstalled(selected)) {
      throw StateError('Download ${selected.name} on the home screen first.');
    }
    await _backend.activate(selected);
    return _model = await _backend.load(selected);
  }

  Future<ModelChatSession> createChatSession() async {
    final release = reserveSelection();
    try {
      final model = await _loadedModel();
      final chat = await model.openChat(
        modelType: _selectedModel!.modelType,
        systemInstruction:
            'You are a helpful assistant. Answer clearly, accurately, and concisely.',
      );
      return LocalChatSession(chat, onClose: release);
    } catch (_) {
      release();
      rethrow;
    }
  }

  Future<void> download({
    LocalAiModel? model,
    required void Function(int) onProgress,
  }) async {
    final target = model ?? localAiModels.first;
    _beginManagement();
    _downloadingId = target.id;
    _downloadProgress = 0;
    notifyListeners();
    try {
      await _closeCachedModel();
      await _backend.download(target, (progress) {
        _downloadProgress = progress.clamp(0, 100);
        onProgress(_downloadProgress);
        notifyListeners();
      });
      _installedIds.add(target.id);
      if (_selectedModel == null || !isDownloaded(_selectedModel!)) {
        await _changeSelection(target);
      }
    } finally {
      try {
        await _refreshInstalledModels();
        // Installing a file automatically selects it in the SDK. Additional
        // downloads must preserve the user's choice, including on failure.
        await _backend.activate(selectedInstalled ? _selectedModel : null);
      } finally {
        _endManagement();
      }
    }
  }

  Future<String> generate(
    String prompt, {
    GenerationCancellation? cancellation,
    void Function(String)? onToken,
  }) async {
    cancellation?.check();
    final release = reserveSelection();
    InferenceChat? chat;
    try {
      final model = await _loadedModel();
      cancellation?.check();
      chat = await model.openChat(modelType: _selectedModel!.modelType);
      if (cancellation != null) cancellation.stopNative = chat.stopGeneration;
      cancellation?.check();
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      cancellation?.check();
      final text = StringBuffer();
      await for (final response in chat.generateChatResponseAsync()) {
        cancellation?.check();
        if (response is TextResponse) {
          text.write(response.token);
          onToken?.call(response.token);
        }
      }
      cancellation?.check();
      if (text.isEmpty) throw StateError('The local model returned no text.');
      return text.toString();
    } finally {
      if (cancellation != null) cancellation.stopNative = null;
      try {
        await chat?.close();
      } finally {
        release();
      }
    }
  }
}

abstract interface class ModelChatSession {
  Future<String> sendMessage(String message, {void Function(String)? onToken});
  Future<void> cancelCurrentGeneration();
  Future<void> close();
}

class LocalChatSession implements ModelChatSession {
  LocalChatSession(this._chat, {this.onClose});

  final InferenceChat _chat;
  final VoidCallback? onClose;
  bool _closed = false;
  bool _sending = false;
  bool _generationStarted = false;
  bool _cancelRequested = false;

  @override
  Future<String> sendMessage(
    String message, {
    void Function(String)? onToken,
  }) async {
    if (_closed) throw StateError('This chat has ended. Start a new chat.');
    if (_sending) throw StateError('Wait for the current reply to finish.');
    final prompt = message.trim();
    if (prompt.isEmpty) throw ArgumentError.value(message, 'message');
    _sending = true;
    _cancelRequested = false;
    try {
      await _chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      if (_closed || _cancelRequested) return '';
      _generationStarted = true;
      final reply = StringBuffer();
      await for (final response in _chat.generateChatResponseAsync()) {
        if (_closed) break;
        if (response is TextResponse) {
          if (!_cancelRequested) {
            reply.write(response.token);
            onToken?.call(response.token);
          }
        }
      }
      if (reply.isEmpty && !_closed && !_cancelRequested) {
        throw StateError('The local model returned no text.');
      }
      return reply.toString();
    } finally {
      _generationStarted = false;
      _sending = false;
      _cancelRequested = false;
    }
  }

  @override
  Future<void> cancelCurrentGeneration() async {
    if (!_sending || _cancelRequested) return;
    _cancelRequested = true;
    try {
      if (_generationStarted) await _chat.stopGeneration();
    } catch (_) {
      _cancelRequested = false;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_sending) {
      try {
        await _chat.stopGeneration();
      } catch (_) {}
      // Let the stream finish before releasing its native session.
      while (_sending) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    try {
      await _chat.close();
    } finally {
      onClose?.call();
    }
  }
}
