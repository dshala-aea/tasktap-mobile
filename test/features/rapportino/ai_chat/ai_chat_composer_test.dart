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
  bool micEnabled = true,
  Future<double?> Function()? levelOf,
  VoidCallback? onSend,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AiChatComposer(
        controller: controller,
        recording: recording,
        busy: busy,
        writing: writing,
        micEnabled: micEnabled,
        levelOf: levelOf,
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

  testWidgets('a running recording shows its own timer and level meter', (tester) async {
    // Field report: the mic just became a square, so a recording running, a microphone hearing
    // silence and a dead button all looked the same. The meter is the difference.
    final ctrl = TextEditingController();
    await _pump(tester, controller: ctrl, recording: true, levelOf: () async => -20);

    expect(find.byKey(const ValueKey('ai-recording-indicator')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-recording-timer')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('ai-recording-indicator')), findsOneWidget);

    // Ending the recording takes the meter with it.
    await _pump(tester, controller: ctrl, recording: false);
    expect(find.byKey(const ValueKey('ai-recording-indicator')), findsNothing);
  });

  testWidgets('a platform with no amplitude still draws the meter, just still', (tester) async {
    final ctrl = TextEditingController();
    await _pump(tester, controller: ctrl, recording: true, levelOf: () async => null);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('ai-recording-timer')), findsOneWidget);
  });

  testWidgets('a message on its way shows the spinner where the paper plane was', (tester) async {
    final ctrl = TextEditingController(text: 'Valvola sostituita');
    await _pump(tester, controller: ctrl, busy: true);

    expect(find.byKey(const ValueKey('ai-sending-indicator')), findsOneWidget);
  });

  testWidgets('a dimmed microphone takes no taps', (tester) async {
    final ctrl = TextEditingController();
    var micTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiChatComposer(
            controller: ctrl,
            recording: false,
            busy: false,
            writing: true,
            micEnabled: false,
            onMic: () => micTaps++,
            onToggleWriting: () {},
            onSend: () {},
            onTextChanged: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai-chat-mic')));
    expect(micTaps, 0);
  });
}
