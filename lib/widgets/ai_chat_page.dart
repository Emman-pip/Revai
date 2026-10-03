import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/local_model_service.dart';
import '../theme/app_theme.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, required this.model});

  final LocalModelService model;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _messages = <_ChatMessage>[];
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  ModelChatSession? _session;
  String _draft = '';
  String? _error;
  bool _opening = true;
  bool _sending = false;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    unawaited(_openSession());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    final session = _session;
    if (session != null) unawaited(_closeSession(session));
    super.dispose();
  }

  Future<void> _openSession() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final session = await widget.model.createChatSession();
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() => _session = session);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _newChat() async {
    if (_opening || _sending) return;
    final previous = _session;
    setState(() {
      _session = null;
      _messages.clear();
      _draft = '';
      _composer.clear();
      _error = null;
      _opening = true;
    });
    if (previous != null) await _closeSession(previous);
    if (mounted) await _openSession();
  }

  Future<void> _closeSession(ModelChatSession session) async {
    try {
      await session.close();
    } catch (_) {
      // Session cleanup should not prevent navigation or a fresh chat.
    }
  }

  Future<void> _send() async {
    final text = _draft.trim();
    final session = _session;
    if (text.isEmpty || session == null || _sending || _opening) return;
    _composer.clear();
    final reply = _ChatMessage(isUser: false, text: '');
    setState(() {
      _draft = '';
      _error = null;
      _sending = true;
      _cancelRequested = false;
      _messages
        ..add(_ChatMessage(isUser: true, text: text))
        ..add(reply);
    });
    _scrollToLatest();
    try {
      await session.sendMessage(
        text,
        onToken: (token) {
          reply.text += token;
          if (mounted) {
            setState(() {});
            _scrollToLatest();
          }
        },
      );
    } catch (error) {
      if (mounted && !_cancelRequested) {
        setState(() {
          reply.text = 'Could not get a reply. ${_readableError(error)}';
          reply.isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_cancelRequested && reply.text.isEmpty) _messages.remove(reply);
          _sending = false;
          _cancelRequested = false;
        });
      }
      _scrollToLatest();
    }
  }

  Future<void> _cancelResponse() async {
    final session = _session;
    if (!_sending || _cancelRequested || session == null) return;
    setState(() => _cancelRequested = true);
    try {
      await session.cancelCurrentGeneration();
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  String _readableError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chat with AI'),
      actions: [
        TextButton.icon(
          onPressed: _opening || _sending ? null : _newChat,
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('New chat'),
        ),
        const ThemeToggle(),
      ],
    ),
    body: Column(
      children: [
        if (_opening) const LinearProgressIndicator(),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(onPressed: _openSession, child: const Text('Retry')),
            ],
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 42,
                          color: context.colors.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _opening
                              ? 'Loading the local model…'
                              : 'What would you like to know?',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your conversation stays on this device and is cleared when you leave or start a new chat.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) =>
                      _messageBubble(_messages[index]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    enabled: !_opening && _session != null && !_sending,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onChanged: (value) => setState(() => _draft = value),
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Message the local AI…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_sending)
                  IconButton.filled(
                    tooltip: _cancelRequested
                        ? 'Stopping response…'
                        : 'Cancel response',
                    onPressed: _cancelRequested ? null : _cancelResponse,
                    style: IconButton.styleFrom(
                      backgroundColor: context.colors.errorContainer,
                      foregroundColor: context.colors.onErrorContainer,
                    ),
                    icon: _cancelRequested
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.stop_rounded),
                  )
                else
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: _draft.trim().isNotEmpty && !_opening
                        ? _send
                        : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _messageBubble(_ChatMessage message) => Align(
    alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .82,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: message.isUser
            ? context.colors.primaryContainer
            : context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: message.isError
              ? context.colors.error.withValues(alpha: .5)
              : context.colors.outlineVariant,
        ),
      ),
      child: message.isUser
          ? Text(
              message.text,
              style: TextStyle(color: context.colors.onSurface, height: 1.4),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.text.isNotEmpty && !message.isError)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: ValueKey(
                        'markdown-mode-${_messages.indexOf(message)}',
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(
                        () => message.showSource = !message.showSource,
                      ),
                      icon: Icon(
                        message.showSource
                            ? Icons.visibility_outlined
                            : Icons.code_rounded,
                        size: 16,
                      ),
                      label: Text(message.showSource ? 'Preview' : 'Source'),
                    ),
                  ),
                if (message.text.isEmpty && !message.isError)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (message.isError)
                  SelectableText(
                    message.text,
                    style: TextStyle(color: context.colors.error, height: 1.4),
                  )
                else if (message.showSource)
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      color: context.colors.onSurface,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  )
                else
                  MarkdownBody(
                    data: message.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.colors.onSurface,
                            height: 1.45,
                          ),
                          code: TextStyle(
                            color: context.colors.onSurface,
                            fontFamily: 'monospace',
                            backgroundColor:
                                context.colors.surfaceContainerHighest,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: context.colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                  ),
              ],
            ),
    ),
  );
}

class _ChatMessage {
  _ChatMessage({required this.isUser, required this.text});

  final bool isUser;
  String text;
  bool isError = false;
  bool showSource = false;
}
