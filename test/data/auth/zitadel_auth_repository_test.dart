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

import 'package:dio/dio.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

  group('signInWithPassword', () {
    late MockDio httpClient;

    setUp(() {
      httpClient = MockDio();
      registerFallbackValue(Options());
    });

    /// Stubs the GET /oauth/v2/authorize redirect-capture call to return a 302 with the given
    /// authRequestId in its Location header — the shape every case in this group starts from.
    void stubAuthorizeRedirect(String authRequestId) {
      when(
        () => httpClient.get<void>(
          any(that: contains('/oauth/v2/authorize')),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/oauth/v2/authorize'),
          statusCode: 302,
          headers: Headers.fromMap({
            'location': ['https://issuer.test/ui/v1/login?authRequestId=$authRequestId'],
          }),
        ),
      );
    }

    test('happy path: authorize redirect + backend login + token exchange', () async {
      stubAuthorizeRedirect('authreq-1');
      when(
        () => httpClient.post<dynamic>(
          any(that: contains('/api/MobileAuth/login')),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
          statusCode: 200,
          data: {'code': 'abc123'},
        ),
      );
      when(() => appAuth.token(any())).thenAnswer(
        // Positional order per flutter_appauth_platform_interface's TokenResponse: accessToken,
        // refreshToken, accessTokenExpirationDateTime, idToken, tokenType, scopes,
        // tokenAdditionalParameters — 7 params, all but the first four left null here.
        (_) async => TokenResponse(
          'access-1', 'refresh-1', DateTime.now().add(const Duration(hours: 1)),
          _fakeIdToken(), null, null, null,
        ),
      );

      final repo = ZitadelAuthRepository(
        appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
      );

      final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

      expect(result.failure, isNull);
      expect(result.user?.accessToken, 'access-1');

      final tokenCall = verify(() => appAuth.token(captureAny())).captured.single as TokenRequest;
      expect(tokenCall.authorizationCode, 'abc123');
      expect(tokenCall.codeVerifier, isNotEmpty);
    });

    test('wrong credentials: backend returns invalid_credentials, no fallback', () async {
      stubAuthorizeRedirect('authreq-1');
      when(
        () => httpClient.post<dynamic>(
          any(that: contains('/api/MobileAuth/login')),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
            statusCode: 400,
            data: {'code': 'invalid_credentials'},
          ),
        ),
      );

      final repo = ZitadelAuthRepository(
        appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
      );

      final result = await repo.signInWithPassword('tech@tasktap.io', 'wrong-password');

      expect(result.user, isNull);
      expect(result.failure, isA<InvalidCredentials>());
      verifyNever(() => appAuth.token(any()));
    });

    test('additional factor required: typed as AdditionalFactorRequired', () async {
      stubAuthorizeRedirect('authreq-1');
      when(
        () => httpClient.post<dynamic>(
          any(that: contains('/api/MobileAuth/login')),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
            statusCode: 400,
            data: {'code': 'additional_factor_required'},
          ),
        ),
      );

      final repo = ZitadelAuthRepository(
        appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
      );

      final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

      expect(result.user, isNull);
      expect(result.failure, isA<AdditionalFactorRequired>());
    });

    test('network error surfaces as NetworkError', () async {
      when(
        () => httpClient.get<void>(
          any(that: contains('/oauth/v2/authorize')),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/oauth/v2/authorize'),
          type: DioExceptionType.connectionError,
        ),
      );

      final repo = ZitadelAuthRepository(
        appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
      );

      final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

      expect(result.user, isNull);
      expect(result.failure, isA<NetworkError>());
    });
  });
}
