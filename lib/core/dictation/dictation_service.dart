// dart format width=100
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'dictation_capability.dart';

/// Speaking instead of typing, for the fields of the existing rapportino (ADR-0017).
///
/// Voice is an input method here, not a second way to produce a report: the recogniser writes
/// into the same field a keyboard would, and everything downstream — review, signature, PDF — is
/// unchanged. Nothing in the rapportino flow may depend on this working.
abstract interface class IDictationService {
  /// What this handset can do. Called before any dictation control is drawn.
  Future<DictationCapability> capability();

  /// Starts listening, emitting partial transcripts as they arrive.
  ///
  /// On-device only. Implementations must refuse rather than reach the network.
  Future<void> start({
    required ValueChanged<String> onTranscript,
    required VoidCallback onDone,
  });

  Future<void> stop();

  bool get isListening;
}

/// Answers the one question the speech plugin will not: can this device recognise speech without
/// sending audio anywhere?
///
/// `speech_to_text` requests on-device recognition and, on Android, quietly constructs an ordinary
/// network recogniser when it is unavailable — the fallback ADR-0017 exists to prevent. Nothing in
/// its Dart API reports that this happened, so the check has to be made directly against
/// `SpeechRecognizer.isOnDeviceRecognitionAvailable` / `SFSpeechRecognizer.supportsOnDeviceRecognition`
/// before listening starts.
class OnDeviceRecognitionProbe {
  const OnDeviceRecognitionProbe([this._channel = const MethodChannel('tasktap/dictation')]);

  final MethodChannel _channel;

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isOnDeviceRecognitionAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Host side not registered — desktop, tests, or a build that predates the channel. Unknown
      // reads as unavailable, which keeps audio on the device by refusing to dictate at all.
      return false;
    }
  }
}

class DictationService implements IDictationService {
  DictationService({SpeechToText? speech, OnDeviceRecognitionProbe? probe})
    : _speech = speech ?? SpeechToText(),
      _probe = probe ?? const OnDeviceRecognitionProbe();

  final SpeechToText _speech;
  final OnDeviceRecognitionProbe _probe;

  bool _initialized = false;

  @override
  bool get isListening => _speech.isListening;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      // Errors and status are surfaced per-session by [start]; here the only question is whether
      // a recogniser exists at all.
      _initialized = await _speech.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  @override
  Future<DictationCapability> capability() async {
    if (!await _ensureInitialized()) return const DictationCapability.unavailable();

    try {
      final locales = await _speech.locales();
      // Both spellings occur across platforms, and some devices offer regional Italian only.
      final italian = locales
          .where((l) => l.localeId.toLowerCase().replaceAll('-', '_').startsWith('it'))
          .toList();

      return DictationCapability(
        recognizerAvailable: true,
        italianLocaleId: italian.isEmpty ? null : italian.first.localeId,
        onDeviceRecognitionAvailable: await _probe.isAvailable(),
        microphoneGranted: await _speech.hasPermission,
      );
    } catch (_) {
      return const DictationCapability.unavailable();
    }
  }

  @override
  Future<void> start({
    required ValueChanged<String> onTranscript,
    required VoidCallback onDone,
  }) async {
    final capability = await this.capability();
    if (!capability.canDictate) {
      // Refusing is the point. Listening anyway with onDevice requested would, on Android,
      // construct a network recogniser and stream site audio to a server — silently, and against
      // a decision that was made deliberately.
      onDone();
      return;
    }

    await _speech.listen(
      onResult: (result) => onTranscript(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        onDevice: true,
        localeId: capability.italianLocaleId,
        // Partial results are what make this feel like typing rather than like submitting a job:
        // the technician watches the words appear and stops when they have what they need.
        partialResults: true,
        cancelOnError: true,
        // Long enough to describe an intervento without being cut off mid-sentence, short enough
        // that a phone left in a pocket is not listening indefinitely.
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
      ),
    );

    _speech.statusListener = (status) {
      if (status == 'done' || status == 'notListening') onDone();
    };
  }

  @override
  Future<void> stop() => _speech.stop();
}

final dictationServiceProvider = Provider<IDictationService>((ref) => DictationService());

/// Resolved once and cached: the answer does not change while the app is running, and the UI asks
/// for it every time a field with a dictate affordance is built.
final dictationCapabilityProvider = FutureProvider<DictationCapability>(
  (ref) => ref.watch(dictationServiceProvider).capability(),
);
