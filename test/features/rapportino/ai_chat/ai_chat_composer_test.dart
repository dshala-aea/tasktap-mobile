// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/ai_chat_composer.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  bool writing = true,
  bool busy = false,
  bool recording = false,
  bool micEnabled = true,
  bool micProminent = true,
  Future<double?> Function()? levelOf,
  VoidCallback? onSend,
  VoidCallback? onToggleWriting,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AiChatComposer(
        controller: controller,
        recording: recording,
        busy: busy,
        writing: writing,
        micEnabled: micEnabled,
        micProminent: micProminent,
        levelOf: levelOf,
        onMic: () {},
        onToggleWriting: onToggleWriting ?? () {},
        onSend: onSend ?? () {},
        onTextChanged: () {},
      ),
    ),
  ),
);

/// The fill of the 44 dp disc inside the microphone button.
Color? _micFill(WidgetTester tester) {
  final disc = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('ai-chat-mic')),
          matching: find.byType(Container),
        ),
      )
      .where((c) => c.constraints?.maxWidth == 44)
      .first;
  return (disc.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('the paper plane appears only when there is something to send', (tester) async {
    final ctrl = TextEditingController();
    var sent = 0;
    await _pump(tester, controller: ctrl, onSend: () => sent++);

    // Nothing typed: no plane to tap, and the row is just microphone + "Tocca per scrivere".
    expect(find.byKey(const ValueKey('ai-chat-send')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('ai-description-field')), 'Valvola sostituita');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sent, 1);
  });

  testWidgets('a turn in flight keeps the plane slot, as a spinner and inert', (tester) async {
    final ctrl = TextEditingController(text: 'Valvola sostituita');
    var sent = 0;
    await _pump(tester, controller: ctrl, busy: true, onSend: () => sent++);

    expect(find.byKey(const ValueKey('ai-sending-indicator')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sent, 0);
  });

  testWidgets('the hint opens the keyboard, and is the only writing affordance', (tester) async {
    final ctrl = TextEditingController();
    var toggled = 0;
    await _pump(tester, controller: ctrl, writing: false, onToggleWriting: () => toggled++);

    expect(find.byKey(const ValueKey('ai-chat-hint')), findsOneWidget);
    expect(find.text('Tocca per scrivere'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-description-field')), findsNothing);
    // The red "Preferisci scrivere?" band is gone: the hint beside the microphone does its job.
    expect(find.byKey(const ValueKey('ai-toggle-writing')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-chat-hint')));
    expect(toggled, 1);

    await _pump(tester, controller: ctrl, writing: true);
    expect(find.byKey(const ValueKey('ai-description-field')), findsOneWidget);
  });

  testWidgets('a running recording replaces the row with the meter, and offers no send', (
    tester,
  ) async {
    // Field report: the mic just became a square, so a recording running, a microphone hearing
    // silence and a dead button all looked the same. The meter is the difference — and the paper
    // plane, which cannot be used while a recording is open, is not drawn at all.
    final ctrl = TextEditingController(text: 'Valvola sostituita');
    await _pump(tester, controller: ctrl, recording: true, levelOf: () async => -20);

    expect(find.byKey(const ValueKey('ai-recording-indicator')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-recording-timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-chat-send')), findsNothing);
    // The old two-line instruction ("In ascolto… tocca il quadrato per fermare.") is gone: the
    // square is the platform's own stop symbol and the meter says it is running.
    expect(find.textContaining('tocca il quadrato'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('ai-recording-indicator')), findsOneWidget);

    await _pump(tester, controller: ctrl, recording: false);
    expect(find.byKey(const ValueKey('ai-recording-indicator')), findsNothing);
    expect(find.byKey(const ValueKey('ai-description-field')), findsOneWidget);
  });

  testWidgets('a platform with no amplitude still draws the meter, just still', (tester) async {
    final ctrl = TextEditingController();
    await _pump(tester, controller: ctrl, recording: true, levelOf: () async => null);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('ai-recording-timer')), findsOneWidget);
  });

  testWidgets('the microphone is the loud control only until something has been said', (
    tester,
  ) async {
    final ctrl = TextEditingController();
    await _pump(tester, controller: ctrl);
    expect(_micFill(tester), AppPalette.light.red);

    await _pump(tester, controller: ctrl, micProminent: false);
    expect(_micFill(tester), AppPalette.light.surface);
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
    expect(micTaps, 0, reason: 'dimmed means inert');
  });
}
