// dart format width=100
// test/core/audio/speech_output_test.dart
//
// Task 9 — optional device TTS for the AI copilot. The adapter is device-local and off by default:
// it must not speak until the technician opts in, must persist that choice under the agreed key,
// and must delegate every speak/stop to the platform engine so the screen can own the lifecycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/audio/speech_output.dart';

class _FakeEngine implements SpeechEngine {
  final List<String> spoken = [];
  int stops = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('off by default and silent until enabled', () async {
    final engine = _FakeEngine();
    final output = SpeechOutput(engine: engine);

    await output.load();

    expect(output.enabled, isFalse);
    await output.speak('Ciao');
    expect(engine.spoken, isEmpty);
  });

  test('opt-in persists under tasktap.ai.tts.enabled', () async {
    final engine = _FakeEngine();
    final output = SpeechOutput(engine: engine);

    await output.setEnabled(true);

    expect(output.enabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tasktap.ai.tts.enabled'), isTrue);

    final restored = SpeechOutput(engine: _FakeEngine());
    await restored.load();
    expect(restored.enabled, isTrue);
  });

  test('speak and stop delegate to the engine when enabled', () async {
    final engine = _FakeEngine();
    final output = SpeechOutput(engine: engine);
    await output.setEnabled(true);

    await output.speak('  Fatto.  ');
    expect(engine.spoken, ['Fatto.']);

    await output.stop();
    expect(engine.stops, 1);

    await output.speak('   ');
    expect(engine.spoken, ['Fatto.'], reason: 'blank text is not spoken');
  });

  test('disabling the preference stops playback', () async {
    final engine = _FakeEngine();
    final output = SpeechOutput(engine: engine);

    await output.setEnabled(true);
    await output.setEnabled(false);

    expect(output.enabled, isFalse);
    expect(engine.stops, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tasktap.ai.tts.enabled'), isFalse);
  });
}
