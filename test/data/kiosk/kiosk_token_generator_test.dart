import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_token_generator.dart';

void main() {
  const deviceId = 'abcdef01-1111-1111-1111-111111111111';
  final key = base64.encode(List<int>.filled(32, 7));

  test('generates the canonical v3 token and verifies with the same key', () {
    final issuedAt = DateTime.utc(2026, 11, 13, 12, 0, 30);
    final token = KioskTokenGenerator.generate(
      deviceId: deviceId,
      signingKeyBase64: key,
      issuedAt: issuedAt,
    );

    final parts = token.split(':');
    expect(parts, hasLength(4));
    expect(parts[0], 'v3');
    expect(parts[1], deviceId);
    expect(parts[2], '${issuedAt.millisecondsSinceEpoch ~/ 1000}');

    final expected = base64.encode(
      Hmac(
        sha256,
        base64.decode(key),
      ).convert(utf8.encode('kiosk3:$deviceId:${parts[2]}')).bytes,
    );
    expect(parts[3], expected);
  });

  test('different instants produce different signatures', () {
    String at(DateTime t) => KioskTokenGenerator.generate(
      deviceId: deviceId,
      signingKeyBase64: key,
      issuedAt: t,
    );
    expect(
      at(DateTime.utc(2026, 11, 13, 12)),
      isNot(at(DateTime.utc(2026, 11, 13, 12, 1))),
    );
  });
}
