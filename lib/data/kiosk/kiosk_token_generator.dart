import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Generates the kiosk v3 QR token locally, using the per-device key provisioned by the backend.
///
/// Format mirrors the server's validator exactly:
/// `v3:{deviceId}:{issuedAtUnixSeconds}:{base64(HMAC-SHA256(key, "kiosk3:{deviceId}:{issuedAt}"))}`.
/// Both the device id and the issue instant are covered by the signature, so neither can be
/// altered without the device key.
class KioskTokenGenerator {
  const KioskTokenGenerator._();

  static String generate({
    required String deviceId,
    required String signingKeyBase64,
    required DateTime issuedAt,
  }) {
    final issuedAtUnix = issuedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    final payload = 'kiosk3:$deviceId:$issuedAtUnix';
    final hmac = Hmac(sha256, base64.decode(signingKeyBase64));
    final signature = base64.encode(hmac.convert(utf8.encode(payload)).bytes);
    return 'v3:$deviceId:$issuedAtUnix:$signature';
  }
}
