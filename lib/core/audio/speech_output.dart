// dart format width=100
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preference: the technician has opted into hearing assistant replies.
///
/// Off by default. There is no server preference and no migration: each device decides for itself
/// whether the copilot may speak, exactly as the web copilot's `localStorage` flag does.
const String kSpeechOutputEnabledKey = 'tasktap.ai.tts.enabled';

/// The platform boundary [SpeechOutput] talks to.
///
/// Kept behind an interface so the adapter's preference/lifecycle rules are testable without a
/// real TTS plugin, and so a server-backed synthesiser can replace it later without changing the
/// copilot screen.
abstract interface class SpeechEngine {
  Future<void> speak(String text);
  Future<void> stop();
}

/// `flutter_tts` behind [SpeechEngine].
///
/// Nothing is configured until the first spoken reply: constructing the plugin on a device with no
/// Italian voice, or in a widget test with no platform channel, must not fail the screen. Every
/// platform refusal is swallowed; text is always on screen, so a silent reply is a degraded extra,
/// never a broken conversation.
class FlutterTtsSpeechEngine implements SpeechEngine {
  FlutterTtsSpeechEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      await _tts.setLanguage('it-IT');
      await _tts.setSpeechRate(0.5);
    } catch (_) {
      // A handset with no Italian voice still gets the platform default; the adapter stays usable.
    }
  }

  @override
  Future<void> speak(String text) async {
    await _configure();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS stop failed: $e');
    }
  }
}

/// Optional spoken assistant replies, device-local.
///
/// [speak] is a no-op while [enabled] is false: the preference is a real gate, not just a default
/// for a UI switch. The screen opts in explicitly before speaking (the speaker action is always a
/// tap, never autoplay). [stop] always reaches the engine so a new turn or a disposed screen can
/// cut off speech even if the preference was just turned off.
class SpeechOutput {
  SpeechOutput({SpeechEngine? engine, Future<SharedPreferences> Function()? prefs})
    : _engine = engine ?? FlutterTtsSpeechEngine(),
      _prefs = prefs ?? SharedPreferences.getInstance;

  final SpeechEngine _engine;
  final Future<SharedPreferences> Function() _prefs;

  bool _enabled = false;
  bool _loaded = false;

  /// Whether the technician has opted into spoken replies on this device.
  bool get enabled => _enabled;

  /// Reads the persisted preference. Failure (a test without the plugin, a locked store) leaves
  /// the safe default: off.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await _prefs();
      _enabled = prefs.getBool(kSpeechOutputEnabledKey) ?? false;
    } catch (e) {
      debugPrint('TTS preference read failed: $e');
      _enabled = false;
    }
    _loaded = true;
  }

  /// Persists the opt-in/out and stops any speech immediately when turned off.
  Future<void> setEnabled(bool value) async {
    await load();
    _enabled = value;
    try {
      final prefs = await _prefs();
      await prefs.setBool(kSpeechOutputEnabledKey, value);
    } catch (e) {
      debugPrint('TTS preference write failed: $e');
    }
    if (!value) await stop();
  }

  /// Speaks [text] only when the device preference is on. Blank text and a disabled preference are
  /// both no-ops, so callers never need to duplicate the gate.
  Future<void> speak(String text) async {
    await load();
    final trimmed = text.trim();
    if (!_enabled || trimmed.isEmpty) return;
    await _engine.speak(trimmed);
  }

  Future<void> stop() => _engine.stop();
}

/// The real device adapter, resolved lazily. Auto-disposed with the screen that read it; the
/// screen also stops speech in its own `dispose` so playback never outlives the conversation.
final speechOutputProvider = FutureProvider<SpeechOutput>((ref) async {
  final output = SpeechOutput();
  await output.load();
  ref.onDispose(() => unawaited(output.stop()));
  return output;
});
