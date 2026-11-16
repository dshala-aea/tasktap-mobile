// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/ai_chat_composer.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  bool writing = true,
  bool busy = false,
  bool recording = false,
  VoidCallback? onSend,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AiChatComposer(
        controller: controller,
        recording: recording,
        busy: busy,
        writing: writing,
        micEnabled: true,
        onMic: () {},
        onToggleWriting: () {},
        onSend: onSend ?? () {},
        onTextChanged: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('send fires only with text', (tester) async {
    final ctrl = TextEditingController();
    var sent = 0;
    await _pump(tester, controller: ctrl, onSend: () => sent++);

    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sent, 0, reason: 'nothing to send yet');

    await tester.enterText(find.byKey(const ValueKey('ai-description-field')), 'Valvola sostituita');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sent, 1);
  });

  testWidgets('send is inert while a turn is running or a recording is open', (tester) async {
    final ctrl = TextEditingController(text: 'Valvola sostituita');
    var sent = 0;
    await _pump(tester, controller: ctrl, busy: true, onSend: () => sent++);

    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sent, 0);

    await _pump(tester, controller: ctrl, recording: true, onSend: () => sent++);
    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sent, 0);
  });

  testWidgets('the hint invites the microphone until the keyboard is chosen', (tester) async {
    final ctrl = TextEditingController();
    await _pump(tester, controller: ctrl, writing: false);

    expect(find.byKey(const ValueKey('ai-chat-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-description-field')), findsNothing);

    await _pump(tester, controller: ctrl, writing: true);
    expect(find.byKey(const ValueKey('ai-description-field')), findsOneWidget);
  });
}
