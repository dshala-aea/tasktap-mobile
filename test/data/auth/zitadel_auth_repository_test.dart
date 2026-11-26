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

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/api/app_version_policy_api.dart';
import 'package:tasktap_mobile/data/auth/auth_config_source.dart';
import 'package:tasktap_mobile/data/auth/zitadel_auth_repository.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAppAuth extends Mock implements FlutterAppAuth {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

class MockDio extends Mock implements Dio {}

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
    registerFallbackValue(Options());
  });

  late MockAppAuth appAuth;
  late MockSecureStorage storage;
  late Map<String, String> store;

  setUp(() {
    store = {};
    // The cold-start ending records the retained-data owner through SharedPreferences before it
    // drops the credentials (see `retained_owner.dart`). Mocked here so that write settles like a
    // real device's rather than depending on a platform channel this test binding does not answer.
    SharedPreferences.setMockInitialValues({});
    appAuth = MockAppAuth();
    storage = MockSecureStorage();

    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((inv) async => store[inv.namedArguments[#key] as String]);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((inv) async {
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
      when(() => appAuth.token(any())).thenThrow(Exception('SocketException: Failed host lookup'));
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

    test('loose "expired" text is NOT proof of a dead session: the session is kept', () async {
      // Only the OAuth invalid_grant code ends a session. A TLS "certificate has expired" or an SDK
      // "failed to refresh" is retryable trouble and must not bounce a technician to the login.
      when(() => appAuth.token(any())).thenThrow(Exception('token expired'));

      final repo = await restoredRepo();

      expect(repo.currentUser, isNotNull);
      expect(store[_refreshTokenKey], 'rt-cached');
    });
  });

  group('cold start — structured AppAuth error that is not a real session failure', () {
    // Regression: _restore() used to wipe the refresh token on ANY refreshSession() failure that
    // wasn't literally NetworkError. flutter_appauth's native AppAuth SDK throws
    // FlutterAppAuthPlatformException for a whole family of internal glitches (server hiccup, JSON
    // deserialization failure, malformed token response) that have nothing to do with whether the
    // refresh token itself is still good — AppAuth's own GeneralErrors category never populates the
    // OAuth `error` field for these, only errorDescription (English text) does, and that text isn't
    // guaranteed to contain any of the old code's network/socket/connection/host keywords. The old
    // code would then fall through past NetworkError entirely, land on UnknownAuthError, and
    // _restore() would wipe the token and force an interactive re-login the user never actually
    // needed. See ZitadelAuthRepository._mapError/._restore doc comments for the full rationale.
    setUp(() {
      store[_refreshTokenKey] = 'rt-cached';
      store[_cachedIdentityKey] = jsonEncode({
        'id': 'u1',
        'email': 'tech@tasktap.io',
        'displayName': 'Tecnico',
      });
    });

    test('a structured AppAuth error with no OAuth error code does NOT sign the user out',
        () async {
      when(() => appAuth.token(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          message: 'Failed to get token: [error: null, description: Server error]',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            type: '0',
            code: '4',
            error: null,
            errorDescription: 'Server error',
          ),
        ),
      );

      final repo = await restoredRepo();

      expect(repo.currentUser, isNotNull);
      expect(repo.currentUser!.id, 'u1');
      expect(store[_refreshTokenKey], 'rt-cached');
    });

    test('an invalid_grant structured error DOES sign the user out, even with unrelated message text',
        () async {
      // Message text deliberately contains none of _mapError's string-matched keywords (no
      // "invalid_grant"/"refresh"/"expired"/"network"/etc.) — proves classification comes from the
      // structured platformErrorDetails.error field, not from sniffing e.toString().
      when(() => appAuth.token(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          message: 'Failed to get token: something unexpected happened',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            type: '2',
            code: '9',
            error: 'invalid_grant',
            errorDescription: 'The refresh token is invalid or has been revoked',
          ),
        ),
      );

      final repo = await restoredRepo();

      expect(repo.currentUser, isNull);
      expect(store.containsKey(_refreshTokenKey), isFalse);
      expect(store.containsKey(_cachedIdentityKey), isFalse);
    });

    test('a structured AppAuth error with an unrelated OAuth error code does NOT sign the user out',
        () async {
      // invalid_client/unauthorized_client etc. mean something is wrong with the app's own client
      // registration, not that this specific refresh token is dead — must not be conflated with
      // SessionExpired.
      when(() => appAuth.token(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          message: 'Failed to get token: [error: invalid_client, description: null]',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            type: '2',
            code: '1',
            error: 'invalid_client',
            errorDescription: null,
          ),
        ),
      );

      final repo = await restoredRepo();

      expect(repo.currentUser, isNotNull);
      expect(store[_refreshTokenKey], 'rt-cached');
    });
  });

  group('cold start — network failure with nothing cached to fall back to', () {
    test('falls through to sign-out (no identity to show as signed-in)', () async {
      store[_refreshTokenKey] = 'rt-cached';
      // No cached identity written.
      when(() => appAuth.token(any())).thenThrow(Exception('SocketException: Failed host lookup'));

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

  group('refreshSession — single-flight (reconnect-burst race regression)', () {
    // Regression for the reported bug: on reconnect, ~10 independent watchers each fire an API
    // call simultaneously (see home_shell.dart's onReconnect registrations). If the access token
    // expired while offline, every one of those requests 401s and each independently called
    // refreshSession() before this fix — all redeeming the SAME (soon-to-rotate) refresh token
    // concurrently. Zitadel rotates refresh tokens on use, so only one of those concurrent
    // redemptions can succeed; the rest come back as an ambiguous failure that _mapError can't
    // always classify as a clean SessionExpired, leaving the session stuck 401ing forever with no
    // sign-out and no redirect to /login. Single-flighting refreshSession() means the whole burst
    // shares ONE token exchange — no concurrent redemption of the same refresh token, no race.
    test('concurrent callers share a single token exchange, not one each', () async {
      final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);
      store[_refreshTokenKey] = 'rt-shared';

      var tokenCallCount = 0;
      when(() => appAuth.token(any())).thenAnswer((_) async {
        tokenCallCount++;
        // Delay so the concurrent calls below genuinely overlap in time, the way a real reconnect
        // burst's near-simultaneous 401s would.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return TokenResponse(
          'access-new',
          'rt-new',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
          _fakeIdToken(sub: 'u1', email: 'tech@tasktap.io', name: 'Tecnico'),
          'Bearer',
          null,
          null,
        );
      });

      final results = await Future.wait([
        repo.refreshSession(),
        repo.refreshSession(),
        repo.refreshSession(),
      ]);

      expect(tokenCallCount, 1, reason: 'only one token exchange should occur for the whole burst');
      for (final result in results) {
        expect(result.user?.id, 'u1');
        expect(result.user?.accessToken, 'access-new');
        expect(result.failure, isNull);
      }
      expect(store[_refreshTokenKey], 'rt-new');
    });

    test('a later, independent call after the first exchange completes triggers a new one', () async {
      final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);
      store[_refreshTokenKey] = 'rt-shared';

      var tokenCallCount = 0;
      when(() => appAuth.token(any())).thenAnswer((_) async {
        tokenCallCount++;
        return TokenResponse(
          'access-$tokenCallCount',
          'rt-$tokenCallCount',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
          _fakeIdToken(sub: 'u1', email: 'tech@tasktap.io', name: 'Tecnico'),
          'Bearer',
          null,
          null,
        );
      });

      await repo.refreshSession();
      await repo.refreshSession();

      expect(
        tokenCallCount,
        2,
        reason: 'the single-flight guard must clear once a refresh settles, not permanently '
            'dedupe every future refresh',
      );
    });
  });

  group('refreshSession — only invalid_grant is a dead session', () {
    // The classification the interceptor's forced path hangs off: SessionExpired ends the session
    // (keeping local data), every other failure keeps it and lets the one call fail retryably.
    late ZitadelAuthRepository repo;

    setUp(() {
      repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);
      store[_refreshTokenKey] = 'rt-kept';
      store[_cachedIdentityKey] = jsonEncode({'id': 'u1', 'email': 'tech@tasktap.io'});
    });

    test('a structured invalid_grant is SessionExpired', () async {
      when(() => appAuth.token(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          message: 'Failed to get token',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            type: '2',
            code: '9',
            error: 'invalid_grant',
            errorDescription: null,
          ),
        ),
      );

      final result = await repo.refreshSession();

      expect(result.failure, isA<SessionExpired>());
    });

    test('a network error is NetworkError and keeps the stored session', () async {
      when(() => appAuth.token(any())).thenThrow(Exception('SocketException: Failed host lookup'));

      final result = await repo.refreshSession();

      expect(result.failure, isA<NetworkError>());
      expect(store[_refreshTokenKey], 'rt-kept');
      expect(store[_cachedIdentityKey], isNotNull);
    });

    test('"certificate has expired" / "failed to refresh" are NOT SessionExpired', () async {
      when(() => appAuth.token(any())).thenThrow(Exception('certificate has expired'));
      final tls = await repo.refreshSession();
      expect(tls.failure, isNot(isA<SessionExpired>()));

      when(() => appAuth.token(any())).thenThrow(Exception('failed to refresh the token'));
      final sdk = await repo.refreshSession();
      expect(sdk.failure, isNot(isA<SessionExpired>()));

      expect(store[_refreshTokenKey], 'rt-kept');
    });

    test('a token response without an access token is retryable, not SessionExpired', () async {
      when(() => appAuth.token(any())).thenAnswer(
        (_) async => TokenResponse(null, null, null, null, null, null, null),
      );

      final result = await repo.refreshSession();

      expect(result.user, isNull);
      expect(result.failure, isA<UnknownAuthError>());
      expect(store[_refreshTokenKey], 'rt-kept');
    });

    test('a hung native refresh is a NetworkError (the session is kept)', () async {
      // Not exercised with a real 12 s wait: a TimeoutException from the call is what the bound
      // produces, and it must read as unreachable, never as a dead token.
      when(() => appAuth.token(any())).thenThrow(TimeoutException('hung'));

      final result = await repo.refreshSession();

      expect(result.failure, isA<NetworkError>());
      expect(store[_refreshTokenKey], 'rt-kept');
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

  // ── browser sign-in only ───────────────────────────────────────────────────
  group('signIn — browser flow only', () {
    AuthorizationTokenResponse okResponse() => AuthorizationTokenResponse(
      'access-1',
      'refresh-1',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
      _fakeIdToken(sub: 'u3', email: 'u3@tasktap.io'),
      'Bearer',
      null,
      null,
      null,
    );

    ZitadelAuthRepository repoWithDio(MockDio dio) => ZitadelAuthRepository(
      appAuth: appAuth,
      storage: storage,
      revocationHttpClient: dio,
      restore: false,
    );

    test('requests the AuthConfigSource issuer and client id, the scopes, a non-ephemeral session',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer((_) async => okResponse());

      await ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false).signIn();

      final req = verify(() => appAuth.authorizeAndExchangeCode(captureAny())).captured.single
          as AuthorizationTokenRequest;
      expect(req.issuer, AuthConfig.compileTime.issuer);
      expect(req.clientId, AuthConfig.compileTime.clientId);
      expect(req.redirectUrl, AuthConfig.compileTime.redirectUri);
      expect(req.scopes, ['openid', 'profile', 'email', 'offline_access']);
      expect(req.externalUserAgent, ExternalUserAgent.asWebAuthenticationSession);
    });

    test('passes the loginHint when one is given', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer((_) async => okResponse());

      await ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false)
          .signIn(loginHint: ' saved@tasktap.io ');

      final req = verify(() => appAuth.authorizeAndExchangeCode(captureAny())).captured.single
          as AuthorizationTokenRequest;
      expect(req.loginHint, 'saved@tasktap.io');
    });

    test('sends no loginHint when none or a blank one is given', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer((_) async => okResponse());
      final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

      await repo.signIn();
      await repo.signIn(loginHint: '  ');

      final reqs = verify(() => appAuth.authorizeAndExchangeCode(captureAny())).captured
          .cast<AuthorizationTokenRequest>();
      expect(reqs, hasLength(2));
      expect(reqs.every((r) => r.loginHint == null), isTrue);
    });

    test('makes no HTTP call of its own: no MobileAuth BFF request on any sign-in outcome',
        () async {
      final dio = MockDio();
      final repo = repoWithDio(dio);

      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer((_) async => okResponse());
      await repo.signIn();
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthUserCancelledException(
          code: 'authorize_and_exchange_code_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
      );
      await repo.signIn();
      when(() => appAuth.authorizeAndExchangeCode(any()))
          .thenThrow(PlatformException(code: 'x', message: 'Network error'));
      await repo.signIn();

      verifyZeroInteractions(dio);
    });

    group('a failed attempt is non-destructive', () {
      setUp(() {
        store[_refreshTokenKey] = 'rt-keep';
        store[_cachedIdentityKey] = jsonEncode({'id': 'u1', 'email': 'tech@tasktap.io'});
        store['tt.oidc.issuer'] = AuthConfig.compileTime.issuer;
      });

      void expectStorageUntouched() {
        expect(store[_refreshTokenKey], 'rt-keep');
        expect(store[_cachedIdentityKey], contains('u1'));
        expect(store['tt.oidc.issuer'], AuthConfig.compileTime.issuer);
        verifyNever(() => storage.delete(key: any(named: 'key')));
        verifyNever(() => storage.write(key: any(named: 'key'), value: any(named: 'value')));
      }

      test('cancel returns SignInCancelled and clears nothing', () async {
        when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
          FlutterAppAuthUserCancelledException(
            code: 'authorize_and_exchange_code_failed',
            message: 'User cancelled flow',
            platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
          ),
        );
        final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

        final result = await repo.signIn();

        expect(result.user, isNull);
        expect(result.failure, isA<SignInCancelled>());
        expectStorageUntouched();
      });

      test('offline returns NetworkError and clears nothing', () async {
        when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
          PlatformException(
            code: 'authorize_and_exchange_code_failed',
            message: 'Network error: unable to resolve host',
          ),
        );
        final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

        final result = await repo.signIn();

        expect(result.failure, isA<NetworkError>());
        expectStorageUntouched();
      });

      test('any other failure is a retryable UnknownAuthError, never SessionExpired', () async {
        // Text that would read as an expired session through the refresh-path classifier.
        when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
          PlatformException(code: 'x', message: 'refresh token expired invalid_grant'),
        );
        final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

        final result = await repo.signIn();

        expect(result.failure, isA<UnknownAuthError>());
        expect(result.failure, isNot(isA<SessionExpired>()));
        expectStorageUntouched();
      });

      test('an EMPTY refresh token is a failure and leaves the previous account untouched', () async {
        for (final empty in <String?>['', null]) {
          when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer(
            (_) async => AuthorizationTokenResponse(
              'access-1',
              empty,
              DateTime.now().toUtc().add(const Duration(hours: 1)),
              _fakeIdToken(sub: 'other', email: 'other@tasktap.io'),
              'Bearer',
              null,
              null,
              null,
            ),
          );
          final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

          final result = await repo.signIn();

          expect(result.user, isNull);
          expect(result.failure, isA<UnknownAuthError>());
          expect(repo.currentUser, isNull);
          expectStorageUntouched();
        }
      });

      test('a response without tokens is a failure and writes nothing', () async {
        when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer(
          (_) async => AuthorizationTokenResponse(null, null, null, null, null, null, null, null),
        );
        final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

        final result = await repo.signIn();

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        expectStorageUntouched();
      });
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

    // Regression: `POST /api/auth/logout` on the TaskTap backend is client-side only — no
    // server-side revocation exists there, so a captured refresh token would keep working after a
    // technician signed out on this device. signOut() must revoke it at Zitadel's own OAuth
    // revocation endpoint before discarding it locally.
    group('Zitadel refresh-token revocation', () {
      late MockDio revocationDio;

      setUp(() {
        revocationDio = MockDio();
      });

      Future<ZitadelAuthRepository> signedInRepo() async {
        when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer(
          (_) async => AuthorizationTokenResponse(
            'access-1',
            'refresh-to-revoke',
            DateTime.now().toUtc().add(const Duration(hours: 1)),
            _fakeIdToken(sub: 'u1', email: 'tech@tasktap.io'),
            'Bearer',
            null,
            null,
            null,
          ),
        );

        final repo = ZitadelAuthRepository(
          appAuth: appAuth,
          storage: storage,
          revocationHttpClient: revocationDio,
          restore: false,
        );
        await repo.signIn();
        return repo;
      }

      test('POSTs the refresh token to the revocation endpoint before clearing local state',
          () async {
        when(
          () => revocationDio.post<void>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenAnswer(
          (_) async =>
              Response<void>(requestOptions: RequestOptions(path: '/oauth/v2/revoke'), statusCode: 200),
        );

        final repo = await signedInRepo();
        await repo.signOut();

        final captured = verify(
          () => revocationDio.post<void>(
            captureAny(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          ),
        ).captured;

        expect(captured[0], endsWith('/oauth/v2/revoke'));
        final sentData = captured[1] as Map<String, dynamic>;
        expect(sentData['token'], 'refresh-to-revoke');
        expect(sentData['token_type_hint'], 'refresh_token');
        expect(sentData.containsKey('client_id'), isTrue);

        // Local state is still cleared as normal.
        expect(store.containsKey(_refreshTokenKey), isFalse);
        expect(store.containsKey(_cachedIdentityKey), isFalse);
        expect(repo.currentUser, isNull);
      });

      // The best-effort contract: offline, an unreachable IdP, or any other revocation failure
      // must never block or fail the user-visible sign-out.
      test('a revocation failure does not prevent local sign-out', () async {
        when(
          () => revocationDio.post<void>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(DioException(requestOptions: RequestOptions(path: '/oauth/v2/revoke')));

        final repo = await signedInRepo();

        // Must complete without throwing despite the revocation call failing.
        await repo.signOut();

        expect(store.containsKey(_refreshTokenKey), isFalse);
        expect(store.containsKey(_cachedIdentityKey), isFalse);
        expect(repo.currentUser, isNull);
      });

      test('no revocation attempt is made when there is no session to revoke', () async {
        final repo = ZitadelAuthRepository(
          appAuth: appAuth,
          storage: storage,
          revocationHttpClient: revocationDio,
          restore: false,
        );

        await repo.signOut();

        verifyNever(
          () => revocationDio.post<void>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        );
      });
    });
  });

  // ── server-provided OIDC config ────────────────────────────────────────────
  group('server-provided OIDC config', () {
    const issuerKey = 'tt.oidc.issuer';
    const oldCfg = AuthConfig(
      issuer: 'https://old.test',
      clientId: 'client-old',
      redirectUri: 'app.tasktap://callback',
    );

    AuthConfigSource sourceWith(ServerAuthConfig? server) => AuthConfigSource(
      compileTime: oldCfg,
      readPolicy: () async => AppVersionPolicy(auth: server),
    );

    const newServer = ServerAuthConfig(
      issuer: 'https://id.advantedgeautomation.com',
      clientId: 'client-new',
      redirectUri: 'app.tasktap://callback',
    );

    ZitadelAuthRepository repoWith(ServerAuthConfig? server, {Dio? dio, bool restore = false}) =>
        ZitadelAuthRepository(
          appAuth: appAuth,
          storage: storage,
          revocationHttpClient: dio,
          configSource: sourceWith(server),
          restore: restore,
        );

    MockDio reachableDio({required bool reachable}) {
      final dio = MockDio();
      when(
        () => dio.get<void>(any(), options: any(named: 'options')),
      ).thenAnswer((_) async {
        if (!reachable) {
          throw DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          );
        }
        return Response<void>(requestOptions: RequestOptions(path: '/'), statusCode: 200);
      });
      return dio;
    }

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() {
      store[_refreshTokenKey] = 'rt-1';
      store[_cachedIdentityKey] = jsonEncode({'id': 'u1', 'email': 'tech@tasktap.io'});
    });

    test('signIn uses the server issuer and client id and stores the issuer with the token',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer(
        (_) async => AuthorizationTokenResponse(
          'access-1',
          'refresh-new',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
          _fakeIdToken(),
          'Bearer',
          null,
          null,
          null,
        ),
      );

      final result = await repoWith(newServer).signIn();

      expect(result.user, isNotNull);
      final req = verify(() => appAuth.authorizeAndExchangeCode(captureAny())).captured.single
          as AuthorizationTokenRequest;
      expect(req.issuer, 'https://id.advantedgeautomation.com');
      expect(req.clientId, 'client-new');
      expect(store[issuerKey], 'https://id.advantedgeautomation.com');
      expect(store[_refreshTokenKey], 'refresh-new');
    });

    test('refresh uses the server config when the stored session was minted by that issuer',
        () async {
      store[issuerKey] = 'https://id.advantedgeautomation.com';
      when(() => appAuth.token(any())).thenAnswer(
        (_) async => TokenResponse(
          'access-2',
          'rt-2',
          DateTime.now().add(const Duration(hours: 1)),
          _fakeIdToken(),
          null,
          null,
          null,
        ),
      );

      final result = await repoWith(newServer).refreshSession();

      expect(result.user, isNotNull);
      final req = verify(() => appAuth.token(captureAny())).captured.single as TokenRequest;
      expect(req.issuer, 'https://id.advantedgeautomation.com');
      expect(req.clientId, 'client-new');
    });

    test('a session stored WITHOUT an issuer is read as the dart-define issuer (no mismatch)',
        () async {
      // No server block: config == dart-defines == the legacy session's issuer.
      when(() => appAuth.token(any())).thenAnswer(
        (_) async => TokenResponse(
          'access-2',
          'rt-2',
          DateTime.now().add(const Duration(hours: 1)),
          _fakeIdToken(),
          null,
          null,
          null,
        ),
      );

      final result = await repoWith(null).refreshSession();

      expect(result.failure, isNull);
      final req = verify(() => appAuth.token(captureAny())).captured.single as TokenRequest;
      expect(req.issuer, 'https://old.test');
      // The issuer is persisted from now on.
      expect(store[issuerKey], 'https://old.test');
    });

    test('a session stored WITHOUT an issuer is expired when the server moves the issuer',
        () async {
      final result = await repoWith(newServer, dio: reachableDio(reachable: true)).refreshSession();

      expect(result.user, isNull);
      expect(result.failure, isA<SessionExpired>());
      verifyNever(() => appAuth.token(any()));
    });

    test('changed issuer: the stored session is never presented to the new issuer', () async {
      store[issuerKey] = 'https://old.test';

      final result = await repoWith(newServer, dio: reachableDio(reachable: true)).refreshSession();

      expect(result.failure, isA<SessionExpired>());
      verifyNever(() => appAuth.token(any()));
    });

    test('changed issuer on cold start keeps the cached session and never probes or refreshes',
        () async {
      store[issuerKey] = 'https://old.test';
      final dio = reachableDio(reachable: true);

      final repo = repoWith(newServer, dio: dio, restore: true);
      await settle();

      expect(repo.currentUser, isNotNull);
      expect(repo.currentUser!.id, 'u1');
      expect(store[_refreshTokenKey], 'rt-1');
      verifyNever(() => appAuth.token(any()));
      verifyNever(() => dio.get<void>(any(), options: any(named: 'options')));

      // The next refresh (reconnect / 401) probes the new issuer and decides.
      final result = await repo.refreshSession();
      expect(result.failure, isA<SessionExpired>());
    });

    test('changed issuer: sign-out does not send the old token to a revoke endpoint', () async {
      store[issuerKey] = 'https://old.test';
      final dio = MockDio();
      final repo = repoWith(newServer, dio: dio, restore: true);
      await settle();
      await repo.signOut();

      verifyNever(
        () => dio.post<void>(any(), data: any(named: 'data'), options: any(named: 'options')),
      );
      expect(store.containsKey(_refreshTokenKey), isFalse);
    });

    test('changed issuer while OFFLINE never signs the user out and keeps the token', () async {
      store[issuerKey] = 'https://old.test';

      final repo = repoWith(newServer, dio: reachableDio(reachable: false), restore: true);
      await settle();

      expect(repo.currentUser, isNotNull);
      expect(repo.currentUser!.id, 'u1');
      expect(store[_refreshTokenKey], 'rt-1');
      verifyNever(() => appAuth.token(any()));
    });

    test('an offline refresh error is a NetworkError and keeps the session', () async {
      store[issuerKey] = 'https://id.advantedgeautomation.com';
      when(() => appAuth.token(any())).thenThrow(Exception('SocketException: Failed host lookup'));

      final result = await repoWith(newServer).refreshSession();

      expect(result.failure, isA<NetworkError>());
      expect(store[_refreshTokenKey], 'rt-1');
      expect(store[issuerKey], 'https://id.advantedgeautomation.com');
    });

    test('signOut also drops the stored issuer', () async {
      store[issuerKey] = 'https://old.test';

      await repoWith(null).signOut();

      expect(store.containsKey(issuerKey), isFalse);
    });
  });
}
