import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE (RFC 7636) verifier/challenge pair for a single authorization request.
///
/// Generated locally rather than via `flutter_appauth` — that package's own API only knows how
/// to drive a full browser-based authorize+token round trip, and the native-login flow needs the
/// verifier before it opens anything (see `ZitadelAuthRepository.signInWithPassword`).
class Pkce {
  const Pkce._({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;

  static const _unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static ({String verifier, String challenge}) generate() {
    final random = Random.secure();
    // 96 chars — comfortably inside RFC 7636's 43-128 char verifier range.
    final verifier = List.generate(96, (_) => _unreserved[random.nextInt(_unreserved.length)]).join();
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    return (verifier: verifier, challenge: challenge);
  }
}
