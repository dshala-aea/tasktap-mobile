// Tests for ZitadelAuthRepository, focused on the cold-start / offline-first
// contract of _restore().
//
// The scenario under test: a technician's phone reboots on a job site with no
// signal. The stored refresh token is fine, but the OIDC refresh call itself
// cannot reach the network. That must NOT be treated the same as a genuine
// auth failure (revoked / expired-beyond-refresh token) — see the class doc
// on ZitadelAuthRepository._restore for the full rationale.
//
// FlutterSecureStorage and FlutterAppAuth are mocked (mocktail); storage is
// backed by a plain in-memory Map so read/write/delete round-trip like the
// real thing.

import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/auth/zitadel_auth_repository.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAppAuth extends Mock implements FlutterAppAuth {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

// ── Helpers ────────────────────────────────────────────────────────────────

const _refreshTokenKey = 'tt.oidc.refresh_token';
const _cachedIdentityKey = 'tt.oidc.cached_identity';

/// Builds an unsigned JWT with the given claims (repository only reads
/// claims; signature verification happens server-side).
String _fakeIdToken({
  String sub = 'u1',
  String email = 'tech@tasktap.io',
  String name = 'Tecnico',
}) {
  String seg(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m)));
  final header = seg({'alg': 'none'});
  final payload = seg({'sub': sub, 'email': email, 'name': name});
  return '$header.$payload.sig';
}

void main() {
  setUpAll(() {
    registerFallbackValue(TokenRequest('client', 'redirect', issuer: 'https://issuer.test'));
    registerFallbackValue(
      AuthorizationTokenRequest('client', 'redirect', issuer: 'https://issuer.test'),
    );
  });

  late MockAppAuth appAuth;
  late MockSecureStorage storage;
  late Map<String, String> store;

  setUp(() {
    store = {};
    appAuth = MockAppAuth();
    storage = MockSecureStorage();

    when(() => storage.read(key: any(named: 'key'))).thenAnswer(
      (inv) async => store[inv.namedArguments[#key] as String],
    );
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((inv) async {
      store[inv.namedArguments[#key] as String] = inv.namedArguments[#value] as String;
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((inv) async {
      store.remove(inv.namedArguments[#key] as String);
    });
  });

  /// Constructs the repository (which fires `_restore()` in the background)
  /// and waits for that microtask to settle.
  Future<ZitadelAuthRepository> restoredRepo() async {
    final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return repo;
  }

  group('cold start — no stored session', () {
    test('emits null and never calls the token endpoint', () async {
      final repo = await restoredRepo();

      expect(repo.currentUser, isNull);
      verifyNever(() => appAuth.token(any()));
    });
  });

  group('cold start — network failure while offline (the critical fix)', () {
    setUp(() {
      store[_refreshTokenKey] = 'rt-cached';
      store[_cachedIdentityKey] = jsonEncode({
        'id': 'u1',
        'email': 'tech@tasktap.io',
        'displayName': 'Tecnico',
      });
      when(() => appAuth.token(any()))
          .thenThrow(Exception('SocketException: Failed host lookup'));
    });

    test('does NOT sign the user out — keeps them signed-in offline', () async {
      final repo = await restoredRepo();

      expect(repo.currentUser, isNotNull);
      expect(repo.currentUser!.id, 'u1');
      expect(repo.currentUser!.email, 'tech@tasktap.io');
      expect(repo.currentUser!.displayName, 'Tecnico');
    });

    test('keeps the refresh token on disk (does not wipe it)', () async {
      await restoredRepo();

      expect(store[_refreshTokenKey], 'rt-cached');
    });

    test('never persists an access token on disk', () async {
      final repo = await restoredRepo();

      // accessToken lives only in memory, and is empty here since no real
      // refresh succeeded — nothing that looks like a bearer token is written.
      expect(repo.currentUser!.accessToken, isEmpty);
      expect(store.keys, isNot(contains(contains('access'))));
    });

    test('the offline session is already expired (isExpired == true)', () async {
      final repo = await restoredRepo();

      // Nothing pretends the (empty) access token is valid; callers that need
      // the API will get a 401 and trigger a real refresh.
      expect(repo.currentUser!.isExpired, isTrue);
    });
  });

  group('cold start — genuine auth failure (must sign out)', () {
    setUp(() {
      store[_refreshTokenKey] = 'rt-cached';
      store[_cachedIdentityKey] = jsonEncode({'id': 'u1', 'email': 'tech@tasktap.io'});
    });

    test('invalid_grant wipes the refresh token and signs out', () async {
      when(() => appAuth.token(any())).thenThrow(Exception('invalid_grant'));

      final repo = await restoredRepo();

      expect(repo.currentUser, isNull);
      expect(store.containsKey(_refreshTokenKey), isFalse);
      expect(store.containsKey(_cachedIdentityKey), isFalse);
    });

    test('an expired/revoked session wipes the refresh token and signs out', () async {
      when(() => appAuth.token(any())).thenThrow(Exception('token expired'));

      final repo = await restoredRepo();

      expect(repo.currentUser, isNull);
      expect(store.containsKey(_refreshTokenKey), isFalse);
    });
  });

  group('cold start — network failure with nothing cached to fall back to', () {
    test('falls through to sign-out (no identity to show as signed-in)', () async {
      store[_refreshTokenKey] = 'rt-cached';
      // No cached identity written.
      when(() => appAuth.token(any()))
          .thenThrow(Exception('SocketException: Failed host lookup'));

      final repo = await restoredRepo();

      expect(repo.currentUser, isNull);
    });
  });

  group('cold start — successful refresh', () {
    test('emits the refreshed user and refreshes the cached identity', () async {
      store[_refreshTokenKey] = 'rt-old';
      when(() => appAuth.token(any())).thenAnswer(
        (_) async => TokenResponse(
          'access-new',
          'rt-new',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
          _fakeIdToken(sub: 'u2', email: 'u2@tasktap.io', name: 'Altro Tecnico'),
          'Bearer',
          null,
          null,
        ),
      );

      final repo = await restoredRepo();

      expect(repo.currentUser?.id, 'u2');
      expect(repo.currentUser?.accessToken, 'access-new');
      expect(store[_refreshTokenKey], 'rt-new');
      expect(store[_cachedIdentityKey], contains('u2@tasktap.io'));
    });
  });

  group('signIn', () {
    test('persists the refresh token and a cached identity snapshot', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer(
        (_) async => AuthorizationTokenResponse(
          'access-1',
          'refresh-1',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
          _fakeIdToken(sub: 'u3', email: 'u3@tasktap.io'),
          'Bearer',
          null,
          null,
          null,
        ),
      );

      final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);
      final result = await repo.signIn();

      expect(result.user, isNotNull);
      expect(store[_refreshTokenKey], 'refresh-1');
      expect(store[_cachedIdentityKey], contains('u3@tasktap.io'));
    });
  });

  group('signOut', () {
    test('clears both the refresh token and the cached identity', () async {
      store[_refreshTokenKey] = 'rt';
      store[_cachedIdentityKey] = '{"id":"u1"}';

      final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);
      await repo.signOut();

      expect(store.containsKey(_refreshTokenKey), isFalse);
      expect(store.containsKey(_cachedIdentityKey), isFalse);
      expect(repo.currentUser, isNull);
    });
  });
}
