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
    ///
    /// Uses `authRequest` as the query parameter name, matching the deployed Zitadel instance's
    /// actual Login V2 configuration (ZITADEL_OIDC_DEFAULTLOGINURLV2 in the backend repo's
    /// docker-compose.coolify.yml) — NOT `authRequestId`, which some Zitadel docs/versions use
    /// but which this deployment does not send.
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
            'location': ['https://issuer.test/ui/v1/login?authRequest=$authRequestId'],
          }),
        ),
      );
    }

    /// Stubs the same redirect but with the fallback `authRequestId` query parameter name, for
    /// the test confirming that name is still accepted.
    void stubAuthorizeRedirectWithFallbackParamName(String authRequestId) {
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

    // Regression: some Zitadel configurations/versions send `authRequestId` instead of the
    // `authRequest` name this deployment actually uses (see stubAuthorizeRedirect's doc comment)
    // — the fallback name must still work.
    test('happy path via the authRequestId fallback query parameter name', () async {
      stubAuthorizeRedirectWithFallbackParamName('authreq-fallback');
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

      final loginPostCall = verify(
        () => httpClient.post<dynamic>(
          any(that: contains('/api/MobileAuth/login')),
          data: captureAny(named: 'data'),
          options: any(named: 'options'),
        ),
      ).captured.single as Map<String, dynamic>;
      expect(loginPostCall['authRequestId'], 'authreq-fallback');
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

    // Regression: _captureAuthRequestId throws typed AuthFailure values (e.g. UnknownAuthError),
    // not Dart Exceptions. The catch block around its call site used to funnel everything through
    // _mapError(e), which does `e.toString().toLowerCase()` — since UnknownAuthError has no
    // custom toString(), that produced a useless "Instance of 'UnknownAuthError'" message instead
    // of the actual, specific failure. It must be passed through untouched instead.
    test(
      'when the authorize redirect has no Location header, the typed failure survives intact '
      '(not "Instance of ...")',
      () async {
        when(
          () => httpClient.get<void>(
            any(that: contains('/oauth/v2/authorize')),
            options: any(named: 'options'),
          ),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(path: '/oauth/v2/authorize'),
            statusCode: 302,
            // No 'location' header at all — simulates a redirect response Dio accepted but that
            // carries nothing to capture (e.g. a timed-out/misconfigured authorize endpoint).
            headers: Headers(),
          ),
        );

        final repo = ZitadelAuthRepository(
          appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
        );

        final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        final failure = result.failure as UnknownAuthError;
        expect(failure.message, isNot(contains('Instance of')));
        expect(failure.message, 'No redirect from authorize endpoint');
        verifyNever(() => httpClient.post<dynamic>(any(), data: any(named: 'data'), options: any(named: 'options')));
      },
    );

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

    // Regression: a 200 OK with a malformed body (missing `code`, or `code` of the wrong type)
    // must never let a raw cast/TypeError exception escape signInWithPassword — every other
    // failure path in this class converts to a typed AuthFailure, and this one must too.
    test('malformed 200 response (missing code): returns UnknownAuthError, does not throw', () async {
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
          data: <String, dynamic>{},
        ),
      );

      final repo = ZitadelAuthRepository(
        appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
      );

      final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

      expect(result.user, isNull);
      expect(result.failure, isA<UnknownAuthError>());
      verifyNever(() => appAuth.token(any()));
    });

    test('malformed 200 response (code not a String): returns UnknownAuthError, does not throw', () async {
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
          data: {'code': 123},
        ),
      );

      final repo = ZitadelAuthRepository(
        appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
      );

      final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

      expect(result.user, isNull);
      expect(result.failure, isA<UnknownAuthError>());
      verifyNever(() => appAuth.token(any()));
    });

    // Regression: the backend login POST can fail with a response body that IS a Map but whose
    // `code` field is not a String (e.g. a proxy/gateway error page shaped differently, here a
    // numeric HTTP status echoed back as `code`). The old `e.response?.data['code'] as String?`
    // cast threw a TypeError from inside the catch block itself, escaping the whole method
    // uncaught and leaving the UI stuck spinning forever. It must fall through to a generic
    // mapped failure instead.
    test(
      'DioException with a non-String `code` field in the response body does not throw '
      '— falls through to a generic failure',
      () async {
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
              statusCode: 502,
              data: {'code': 502},
            ),
          ),
        );

        final repo = ZitadelAuthRepository(
          appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
        );

        // Must complete without throwing.
        final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

        expect(result.user, isNull);
        // Not InvalidCredentials/AdditionalFactorRequired — those require a String match on
        // `code`, which this response doesn't have — so it falls through to _mapError's generic
        // mapping.
        expect(result.failure, isA<UnknownAuthError>());
        verifyNever(() => appAuth.token(any()));
      },
    );
  });
}
