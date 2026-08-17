// dart format width=100

/// Why dictation cannot be offered, or [DictationBlocker.none] when it can.
///
/// An enum rather than a bool because each of these needs a different answer on screen and a
/// different action from the technician — "your phone cannot do this" and "you said no to the
/// microphone" are not the same message, and treating them as one `isSupported == false` produces
/// a control that is mysteriously missing.
enum DictationBlocker {
  /// Everything needed is present.
  none,

  /// The platform has no usable speech recogniser at all.
  noRecognizer,

  /// A recogniser exists but does not know Italian. Rapportini are written in Italian.
  noItalianLocale,

  /// The recogniser cannot run without sending audio to the vendor's servers.
  ///
  /// A blocker, not a downgrade. ADR-0017 makes on-device the foundation precisely so dictation
  /// works in a basement, and so no site audio — including a customer's voice in the background —
  /// leaves the handset. Falling back to network recognition would quietly convert an
  /// offline-first capability into a network-dependent one, which is the outcome the ADR names.
  noOnDeviceRecognition,

  /// The technician has not granted microphone access, or has refused it.
  microphoneDenied,
}

/// What this specific handset can actually do, established before any dictation UI is drawn.
///
/// Deliberately not a single `isSupported` flag. On-device Italian recognition depends on the
/// platform, the OS version and whether a language pack has been downloaded — so the answer
/// varies across a fleet of phones, and the parts that fail are worth telling apart.
class DictationCapability {
  const DictationCapability({
    required this.recognizerAvailable,
    required this.italianLocaleId,
    required this.onDeviceRecognitionAvailable,
    required this.microphoneGranted,
  });

  /// Nothing works. The state to assume when a check throws.
  const DictationCapability.unavailable()
    : recognizerAvailable = false,
      italianLocaleId = null,
      onDeviceRecognitionAvailable = false,
      microphoneGranted = false;

  final bool recognizerAvailable;

  /// The platform's own id for Italian (`it_IT`, `it-IT`, …), or null if it has none.
  ///
  /// Kept as the raw id rather than a bool because it is what has to be handed back to the
  /// recogniser, and the two platforms spell it differently.
  final String? italianLocaleId;

  /// Whether the platform will recognise speech without a network round trip.
  ///
  /// Answered by a direct platform call — `SpeechRecognizer.isOnDeviceRecognitionAvailable` on
  /// Android, `SFSpeechRecognizer.supportsOnDeviceRecognition` on iOS — rather than by asking the
  /// speech plugin, which does not expose it. That matters: when on-device is unavailable the
  /// plugin's Android path constructs an ordinary network recogniser and carries on, and nothing
  /// visible in Dart says that the audio just went to a server.
  final bool onDeviceRecognitionAvailable;

  final bool microphoneGranted;

  bool get italianAvailable => italianLocaleId != null;

  /// The first thing standing in the way, in the order the technician would hit it.
  DictationBlocker get blocker {
    if (!recognizerAvailable) return DictationBlocker.noRecognizer;
    if (!italianAvailable) return DictationBlocker.noItalianLocale;
    if (!onDeviceRecognitionAvailable) return DictationBlocker.noOnDeviceRecognition;
    if (!microphoneGranted) return DictationBlocker.microphoneDenied;
    return DictationBlocker.none;
  }

  bool get canDictate => blocker == DictationBlocker.none;

  /// What to tell the technician, in the app's own language.
  ///
  /// Every one of these says the feature is unavailable *here* rather than broken. Dictation is
  /// an input method; the keyboard is still there, and the rapportino is completable without it.
  String? get unavailableMessage => switch (blocker) {
    DictationBlocker.none => null,
    DictationBlocker.noRecognizer => 'Dettatura non disponibile su questo dispositivo.',
    DictationBlocker.noItalianLocale =>
      'Dettatura non disponibile: questo dispositivo non ha il riconoscimento vocale italiano.',
    DictationBlocker.noOnDeviceRecognition =>
      'Dettatura non disponibile offline su questo dispositivo. '
          'Installa il pacchetto vocale italiano nelle impostazioni di sistema.',
    DictationBlocker.microphoneDenied =>
      'Dettatura non disponibile: accesso al microfono non consentito.',
  };

  @override
  String toString() =>
      'DictationCapability(recognizer: $recognizerAvailable, italian: $italianLocaleId, '
      'onDevice: $onDeviceRecognitionAvailable, mic: $microphoneGranted)';
}
