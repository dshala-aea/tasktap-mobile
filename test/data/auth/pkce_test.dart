import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/auth/pkce.dart';

void main() {
  group('Pkce.generate', () {
    test('challenge is the base64url(no padding) SHA-256 of the verifier', () {
      final pair = Pkce.generate();

      final expected = base64Url
          .encode(sha256.convert(utf8.encode(pair.verifier)).bytes)
          .replaceAll('=', '');
      expect(pair.challenge, expected);
    });

    test('verifier is 43-128 chars of the unreserved character set (RFC 7636)', () {
      final pair = Pkce.generate();
      expect(pair.verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(pair.verifier), isTrue);
    });

    test('two calls produce different verifiers', () {
      final a = Pkce.generate();
      final b = Pkce.generate();
      expect(a.verifier, isNot(equals(b.verifier)));
    });
  });
}
