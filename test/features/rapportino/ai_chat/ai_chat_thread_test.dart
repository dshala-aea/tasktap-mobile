// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/ai_chat_thread.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/chat_message.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<ChatMessage> messages,
  bool thinking = false,
  String? failedMessageId,
  String? sendingMessageId,
  VoidCallback? onRetry,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AiChatThread(
        messages: messages,
        thinking: thinking,
        thinkingLabel: 'Sto compilando il rapporto…',
        failedMessageId: failedMessageId,
        sendingMessageId: sendingMessageId,
        onRetryFailed: onRetry,
      ),
    ),
  ),
);

void main() {
  testWidgets('renders operator and assistant bubbles, then a thinking bubble', (tester) async {
    await _pump(
      tester,
      messages: const [
        ChatMessage(
          id: 'm1',
          role: ChatRole.operator,
          text: 'Ho sostituito la valvola',
          source: ChatSource.voice,
        ),
        ChatMessage(id: 'm2', role: ChatRole.assistant, text: 'Quanti materiali?'),
      ],
      thinking: true,
    );

    expect(find.text('Ho sostituito la valvola'), findsOneWidget);
    expect(find.text('Quanti materiali?'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-thinking')), findsOneWidget);
  });

  testWidgets('a failed operator message keeps its retry on the bubble', (tester) async {
    var retried = 0;
    await _pump(
      tester,
      messages: const [
        ChatMessage(id: 'm1', role: ChatRole.operator, text: 'Nessuno'),
      ],
      failedMessageId: 'm1',
      onRetry: () => retried++,
    );

    await tester.tap(find.byKey(const ValueKey('ai-msg-retry')));
    expect(retried, 1);
  });

  testWidgets('no retry when nothing failed', (tester) async {
    await _pump(
      tester,
      messages: const [ChatMessage(id: 'm1', role: ChatRole.operator, text: 'Nessuno')],
    );

    expect(find.byKey(const ValueKey('ai-msg-retry')), findsNothing);
  });

  testWidgets('the message on its way carries the spinner, and only that one', (tester) async {
    await _pump(
      tester,
      messages: const [
        ChatMessage(id: 'm1', role: ChatRole.operator, text: 'Ho sostituito la valvola'),
        ChatMessage(id: 'm2', role: ChatRole.operator, text: 'E ho pulito il filtro'),
      ],
      sendingMessageId: 'm2',
    );

    expect(find.byKey(const ValueKey('ai-msg-sending')), findsOneWidget);

    await _pump(
      tester,
      messages: const [
        ChatMessage(id: 'm1', role: ChatRole.operator, text: 'Ho sostituito la valvola'),
      ],
    );
    expect(find.byKey(const ValueKey('ai-msg-sending')), findsNothing);
  });
}
