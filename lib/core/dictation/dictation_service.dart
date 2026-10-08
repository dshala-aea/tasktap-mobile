// dart format width=100
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Imported directly, not through speech_to_text.dart: the plugin's main library only re-exports
// ListenMode/SpeechConfigOption/SpeechListenOptions from the platform interface and leaves
// SpeechRecognitionError — the type its own SpeechErrorListener typedef hands back — unexported.
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'dictation_capability.dart';
import 'dictation_outcome.dart';
import 'dictation_session.dart';

/// Speaking instead of typing, for the fields of the existing rapportino (ADR-0017).
///
/// Voice is an input method here, not a second way to produce a report: the recogniser writes
/// into the same field a keyboard would, and everything downstream — review, signature, PDF — is
/// unchanged. Nothing in the rapportino flow may depend on this working.
abstract interface class IDictationService {
  /// What this handset can do. Called before any dictation control is drawn.
  Future<DictationCapability> capability();

  /// Starts listening, emitting partial transcripts as they arrive and reporting *why* the session
  /// ended — words, a silent finish, or a refused language — through [onDone].
  ///
  /// On-device only. Implementations must refuse rather than reach the network.
  Future<void> start({
    required ValueChanged<String> onTranscript,
    required ValueChanged<DictationOutcome> onDone,
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

  /// The session in flight. The listeners below outlive any single one, because the plugin installs
  /// them once at initialize time on a process-wide singleton — they are the only channel a
  /// session's errors and status can arrive on, so the *current* session is held here for them to
  /// find rather than being captured in a per-call closure.
  DictationSession? _session;
  ValueChanged<DictationOutcome>? _onDone;

  @override
  bool get isListening => _speech.isListening;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(onError: _handleError, onStatus: _handleStatus);
      // Assigned directly as well as passed above: `initialize` returns early without touching
      // either field once it has succeeded, so on a second service instance — or after anything
      // else initialised the shared singleton first — the arguments above are silently ignored and
      // these are the assignments that actually take effect.
      _speech.errorListener = _handleError;
      _speech.statusListener = _handleStatus;
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  void _handleError(SpeechRecognitionError error) => _session?.onError(error.errorMsg);

  void _handleStatus(String status) {
    if (status == 'done' || status == 'notListening') _endSession();
  }

  /// Ends the session once, whatever ends it — a done status, a throw, or an explicit [stop].
  void _endSession() {
    final session = _session;
    if (session == null) return;
    final onDone = _onDone;
    // Both cleared before the callback runs: a session can deliver a final result and a done status,
    // and a second `done` arriving after the first must not fire the callback a second time.
    _session = null;
    _onDone = null;
    onDone?.call(session.outcome);
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
    required ValueChanged<DictationOutcome> onDone,
  }) async {
    final capability = await this.capability();
    if (!capability.canDictate) {
      // Refusing is the point. Listening anyway with onDevice requested would, on Android,
      // construct a network recogniser and stream site audio to a server — silently, and against
      // a decision that was made deliberately.
      onDone(DictationOutcome.stoppedByUser);
      return;
    }

    final session = DictationSession();
    _session = session;
    _onDone = onDone;

    // Assigned before listen(), never after it returns: this settable field is the plugin's only
    // status channel — listen() has no onStatus argument — so a session that ends quickly fires
    // `done` before a listener assigned afterward would ever be in place, and the control would sit
    // reading "listening" forever.
    _speech.statusListener = _handleStatus;
    _speech.errorListener = _handleError;

    try {
      await _speech.listen(
        onResult: (result) {
          session.onTranscript(result.recognizedWords);
          onTranscript(result.recognizedWords);
        },
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
    } catch (_) {
      // listen() throws rather than reporting through the status channel when the platform refuses
      // to start at all — most often `SpeechToTextNotInitializedException`. Treated as a session
      // that failed, not one that never happened.
      session.onError('error_client');
      _endSession();
    }
  }

  @override
  Future<void> stop() async {
    _session?.onStoppedByUser();
    await _speech.stop();
    // stop() asks the recogniser for a final result and a `done` status follows it — but ending the
    // session here as well keeps the control honest if that status never arrives. `_endSession`
    // clears `_onDone`, yet the closure captured in `onResult` above still writes to the controller,
    // so a final result arriving after this still lands in the field.
    _endSession();
  }
}

final dictationServiceProvider = Provider<IDictationService>((ref) => DictationService());

/// Resolved once and cached: the answer does not change while the app is running, and the UI asks
/// for it every time a field with a dictate affordance is built.
final dictationCapabilityProvider = FutureProvider<DictationCapability>(
  (ref) => ref.watch(dictationServiceProvider).capability(),
);
