// dart format width=100
import '../widgets/app_toast.dart';

/// How a dictation session ended — the reason the microphone is quiet, when it is.
///
/// ADR-0017 refuses network recognition, and a refusal the technician cannot see is
/// indistinguishable from a broken app. Keeping the two apart is the whole point of this enum:
/// on Android the capability probe answers a device-level question, so a handset with no Italian
/// offline model passes the gate and then produces nothing at all — no words, no error, no sign
/// anything happened.
enum DictationOutcome {
  /// Words arrived and are in the field.
  transcribed,

  /// The technician stopped it. Never worth a message.
  stoppedByUser,

  /// The session ended with no words and no error.
  heardNothing,

  /// The recogniser reported a failure that is not about the language.
  recognitionFailed,

  /// The recogniser does not have the language it was asked for. Android reports this when the
  /// Italian offline model is missing.
  languageUnavailable;

  /// What to put on screen, or null when there is nothing worth saying.
  ({String message, ToastTone tone})? get notice => switch (this) {
    DictationOutcome.transcribed || DictationOutcome.stoppedByUser => null,
    DictationOutcome.heardNothing => (
      message:
          'Non ho sentito nulla. Se la dettatura non ha mai funzionato su questo telefono, '
          'installa il pacchetto vocale italiano nelle impostazioni di sistema.',
      tone: ToastTone.warning,
    ),
    DictationOutcome.languageUnavailable => (
      message:
          'Dettatura non disponibile offline su questo dispositivo. '
          'Installa il pacchetto vocale italiano nelle impostazioni di sistema.',
      tone: ToastTone.warning,
    ),
    DictationOutcome.recognitionFailed => (
      message: 'Riconoscimento vocale non riuscito. Riprova.',
      tone: ToastTone.error,
    ),
  };
}
