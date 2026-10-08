// dart format width=100
import 'dictation_outcome.dart';

/// Turns a stream of recogniser callbacks into the one thing the technician needs: why it ended.
///
/// Deliberately separate from `DictationService` and deliberately free of the plugin. `SpeechToText`
/// is a process-wide singleton sitting on a method channel, so the logic that decides what a silent
/// session *means* could not be tested at all if it lived in the same class as the plugin call.
class DictationSession {
  bool _sawWord = false;
  bool _userEnded = false;
  String? _errorMsg;

  void onTranscript(String words) {
    if (words.trim().isNotEmpty) _sawWord = true;
  }

  void onStoppedByUser() => _userEnded = true;

  /// [errorMsg] is speech_to_text's `SpeechRecognitionError.errorMsg` — a stable machine string
  /// like "error_no_match" or "error_language_not_supported" — and is never shown to anyone.
  void onError(String errorMsg) => _errorMsg = errorMsg;

  DictationOutcome get outcome {
    // Words first: a session that produced text owes no apology, whatever else happened in it.
    if (_sawWord) return DictationOutcome.transcribed;
    final error = _errorMsg;
    if (error != null) {
      return error.contains('language')
          ? DictationOutcome.languageUnavailable
          : DictationOutcome.recognitionFailed;
    }
    if (_userEnded) return DictationOutcome.stoppedByUser;
    return DictationOutcome.heardNothing;
  }
}
