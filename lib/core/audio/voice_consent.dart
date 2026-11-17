// dart format width=100
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PLACEHOLDER WORDING — NOT FINAL LEGAL COPY. Replace this constant with the text approved by the
/// owner/legal before release. Bump [voiceConsentVersion] when the text changes materially so
/// existing users are asked again.
const String voiceConsentText =
    'Registrando un aggiornamento vocale, l\'audio viene inviato al server di TaskTap e '
    'trascritto automaticamente per aiutarti a compilare il rapporto di intervento. La '
    'registrazione viene conservata come parte della documentazione dell\'intervento. '
    'Vuoi continuare?';

/// The legal text version. The accepted record also stores the text hash, so changing the wording
/// without bumping this still forces a fresh consent.
const String voiceConsentVersion = 'v1';

/// Append-only list of accepted records. The old boolean key
/// (`voice_recording_consent_v1`) is intentionally ignored: it carries no actor or timestamp, so
/// migrating it would fabricate an audit entry. Users re-consent once after this update.
const String voiceConsentStorageKey = 'voice_recording_consents_v1';

String get voiceConsentTextHash => sha256.convert(utf8.encode(voiceConsentText)).toString();

class VoiceConsentRecord {
  const VoiceConsentRecord({
    required this.version,
    required this.textHash,
    required this.acceptedAtUtc,
    required this.actorId,
  });

  final String version;
  final String textHash;
  final DateTime acceptedAtUtc;
  final String actorId;

  Map<String, dynamic> toJson() => {
    'version': version,
    'textHash': textHash,
    'acceptedAtUtc': acceptedAtUtc.toIso8601String(),
    'actorId': actorId,
  };

  factory VoiceConsentRecord.fromJson(Map<String, dynamic> json) => VoiceConsentRecord(
    version: json['version'] as String? ?? '',
    textHash: json['textHash'] as String? ?? '',
    acceptedAtUtc:
        DateTime.tryParse(json['acceptedAtUtc'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    actorId: json['actorId'] as String? ?? '',
  );
}

Future<List<VoiceConsentRecord>> voiceConsentHistory() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(voiceConsentStorageKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) VoiceConsentRecord.fromJson(item),
    ];
  } catch (_) {
    // Malformed legacy/future data must not block recording; consent is re-asked.
    return const [];
  }
}

/// Has [actorId] accepted the current [voiceConsentText] version? Recording is refused until this
/// is true. A null actor (signed out) is always false.
Future<bool> voiceConsentAcceptedFor(String? actorId) async {
  if (actorId == null || actorId.isEmpty) return false;
  final history = await voiceConsentHistory();
  for (final record in history.reversed) {
    if (record.actorId != actorId) continue;
    return record.version == voiceConsentVersion && record.textHash == voiceConsentTextHash;
  }
  return false;
}

/// Appends one accepted record; it never replaces an earlier one. A no-op when signed out.
Future<void> acceptVoiceConsent(String? actorId) async {
  if (actorId == null || actorId.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final history = await voiceConsentHistory();
  final updated = [
    ...history,
    VoiceConsentRecord(
      version: voiceConsentVersion,
      textHash: voiceConsentTextHash,
      acceptedAtUtc: DateTime.now().toUtc(),
      actorId: actorId,
    ),
  ];
  await prefs.setString(
    voiceConsentStorageKey,
    jsonEncode([for (final record in updated) record.toJson()]),
  );
}
