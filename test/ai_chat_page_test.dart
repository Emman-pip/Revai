import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/theme/app_theme.dart';
import 'package:revai/widgets/ai_chat_page.dart';

class _FakeModel extends LocalModelService {
  final sessions = <_FakeChatSession>[];
  bool holdReplies = false;

  @override
  Future<ModelChatSession> createChatSession() async {
    final session = _FakeChatSession(holdReplies: holdReplies);
    sessions.add(session);
    return session;
  }
}

class _FakeChatSession implements ModelChatSession {
  _FakeChatSession({required this.holdReplies});

  final bool holdReplies;
  final messages = <String>[];
  bool closed = false;
  int cancelCalls = 0;
  Completer<String>? pendingReply;

  @override
  Future<String> sendMessage(
    String message, {
    void Function(String)? onToken,
  }) async {
    messages.add(message);
    if (holdReplies) {
      pendingReply = Completer<String>();
      onToken?.call('Partial reply');
      return pendingReply!.future;
    }
    final response =
        '# Reply ${messages.length}\n\n**formatted text**\n\n'
        '```dart\nprint("hello");\n```\n\n'
        '| Name | Value |\n| --- | --- |\n| Cells | 2 |';
    onToken?.call(response);
    return response;
  }

  @override
  Future<void> cancelCurrentGeneration() async {
    cancelCalls++;
    if (pendingReply != null && !pendingReply!.isCompleted) {
      pendingReply!.complete('Partial reply');
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _ThemeHarness extends StatefulWidget {
  const _ThemeHarness({required this.home});
  final Widget home;

  @override
  State<_ThemeHarness> createState() => _ThemeHarnessState();
}

class _ThemeHarnessState extends State<_ThemeHarness> {
  @override
  Widget build(BuildContext context) => ThemeScope(
    setDarkMode: (_) {},
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: widget.home,
    ),
  );
}

void main() {
  testWidgets('Streams replies and retains multi-turn chat until reset', (
    tester,
  ) async {
    final model = _FakeModel();
    await tester.pumpWidget(_ThemeHarness(home: AiChatPage(model: model)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('Reply 1', findRichText: true), findsOneWidget);
    expect(find.text('formatted text', findRichText: true), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any((widget) => widget.data?.startsWith('# Reply 1') ?? false),
      isTrue,
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'How are you?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(model.sessions.single.messages, ['Hello', 'How are you?']);
    expect(find.text('Reply 2', findRichText: true), findsOneWidget);

    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(model.sessions, hasLength(2));
    expect(model.sessions.first.closed, isTrue);
    expect(find.text('Hello'), findsNothing);
    expect(find.text('What would you like to know?'), findsOneWidget);
  });

  testWidgets('Leaving chat closes its native session', (tester) async {
    final model = _FakeModel();
    await tester.pumpWidget(_ThemeHarness(home: AiChatPage(model: model)));
    await tester.pumpAndSettle();
    expect(model.sessions.single.closed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(model.sessions.single.closed, isTrue);
  });

  testWidgets('Cancel stops the active response and keeps its partial text', (
    tester,
  ) async {
    final model = _FakeModel()..holdReplies = true;
    await tester.pumpWidget(_ThemeHarness(home: AiChatPage(model: model)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Explain this');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(find.byTooltip('Cancel response'), findsOneWidget);
    expect(find.text('Partial reply', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel response'));
    await tester.pumpAndSettle();

    expect(model.sessions.single.cancelCalls, 1);
    expect(find.text('Partial reply', findRichText: true), findsOneWidget);
    expect(find.textContaining('Could not get a reply.'), findsNothing);
    expect(find.byTooltip('Send message'), findsOneWidget);
  });
}
