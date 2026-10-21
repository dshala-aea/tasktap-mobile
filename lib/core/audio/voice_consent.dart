// dart format width=100
import 'package:shared_preferences/shared_preferences.dart';

/// PLACEHOLDER WORDING — NOT FINAL LEGAL COPY. Replace this constant with the text approved by the
/// owner/legal before release. Bump [voiceConsentKey]'s version suffix when the text changes
/// materially so existing users are asked again.
const String voiceConsentText =
    'Registrando un aggiornamento vocale, l\'audio viene inviato al server di TaskTap e '
    'trascritto automaticamente per aiutarti a compilare il rapportino. La registrazione viene '
    'conservata come parte della documentazione dell\'intervento. Vuoi continuare?';

const String voiceConsentKey = 'voice_recording_consent_v1';

/// Has the user accepted [voiceConsentText]? Recording is refused until this is true.
Future<bool> voiceConsentAccepted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(voiceConsentKey) ?? false;
}

Future<void> acceptVoiceConsent() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(voiceConsentKey, true);
}
