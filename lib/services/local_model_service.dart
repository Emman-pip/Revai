import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'generation_cancellation.dart';

const gemmaModelFile = 'gemma-4-E2B-it.litertlm';
const gemmaModelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

class LocalModelService {
  InferenceModel? _model;

  Future<void> initialize() =>
      FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);

  Future<bool> isInstalled() => FlutterGemma.isModelInstalled(gemmaModelFile);

  Future<ModelChatSession> createChatSession() async {
    _model ??= await FlutterGemma.getActiveModel(maxTokens: 8192);
    final chat = await _model!.openChat(
      modelType: ModelType.gemma4,
      systemInstruction:
          'You are a helpful assistant. Answer clearly, accurately, and concisely.',
    );
    return LocalChatSession(chat);
  }

  Future<void> download({required void Function(int) onProgress}) async {
    await FlutterGemma.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(gemmaModelUrl, foreground: true)
        .withProgress(onProgress)
        .install();
  }

  Future<String> generate(
    String prompt, {
    GenerationCancellation? cancellation,
    void Function(String)? onToken,
  }) async {
    cancellation?.check();
    _model ??= await FlutterGemma.getActiveModel(maxTokens: 8192);
    cancellation?.check();
    final chat = await _model!.openChat(modelType: ModelType.gemma4);
    if (cancellation != null) cancellation.stopNative = chat.stopGeneration;
    try {
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
      await chat.close();
    }
  }
}

abstract interface class ModelChatSession {
  Future<String> sendMessage(String message, {void Function(String)? onToken});
  Future<void> cancelCurrentGeneration();
  Future<void> close();
}

class LocalChatSession implements ModelChatSession {
  LocalChatSession(this._chat);

  final InferenceChat _chat;
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
      if (_cancelRequested) return '';
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
    if (_generationStarted) await _chat.stopGeneration();
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
    await _chat.close();
  }
}
