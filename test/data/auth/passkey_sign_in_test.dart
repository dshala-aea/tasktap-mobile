// Tests for the native passkey sign-in path of ZitadelAuthRepository.
//
// The flow under test is the one in the passkey design's §7: capture an
// authRequestId, POST the backend's `passkey/login/start`, unwrap the
// ZITADEL-issued `publicKey` options, run the platform authenticator, POST
// `passkey/login/complete` with the package's own `toJson()` shape, then reuse
// the password flow's code exchange → persist → emit path.
//
// FlutterSecureStorage, FlutterAppAuth, Dio and the passkey authenticator are
// all mocked (mocktail); no test touches a platform channel.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:tasktap_mobile/data/auth/zitadel_auth_repository.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAppAuth extends Mock implements FlutterAppAuth {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

class MockDio extends Mock implements Dio {}

class MockPasskeyAuthenticator extends Mock implements PasskeyAuthenticator {}

// ── Helpers ────────────────────────────────────────────────────────────────

const _refreshTokenKey = 'tt.oidc.refresh_token';
const _cachedIdentityKey = 'tt.oidc.cached_identity';

/// Builds an unsigned JWT with the given claims (the repository only reads
/// claims; signature verification happens server-side).
String _fakeIdToken({
  String sub = 'u1',
  String email = 'tech@tasktap.io',
  String name = 'Tecnico',
}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m)));
  final header = seg({'alg': 'none'});
  final payload = seg({'sub': sub, 'email': email, 'name': name});
  return '$header.$payload.sig';
}

/// The unwrapped `publicKey` object ZITADEL actually sends: the wrapper is
/// stripped by the repository before `AuthenticateRequestType.fromJson`.
const _publicKey = <String, dynamic>{
  'challenge': 'Y2hhbGxlbmdl',
  'rpId': 'auth.tasktap.it',
  'userVerification': 'required',
};

/// The start endpoint's response, with the options nested inside `publicKey`
/// exactly as ZITADEL wraps them.
Map<String, dynamic> _startPayload({
  Map<String, dynamic>? publicKey = _publicKey,
  String? sessionId = 's1',
  String? sessionToken = 'st',
}) => {
  'sessionId': sessionId,
  'sessionToken': sessionToken,
  'publicKeyCredentialRequestOptions': {'publicKey': publicKey},
};

AuthenticateResponseType _assertion() => const AuthenticateResponseType(
  id: 'cred-1',
  rawId: 'cred-1',
  clientDataJSON: 'client-data-json',
  authenticatorData: 'authenticator-data',
  signature: 'signature',
  userHandle: '',
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      TokenRequest('client', 'redirect', issuer: 'https://issuer.test'),
    );
    registerFallbackValue(Options());
    registerFallbackValue(
      const AuthenticateRequestType(
        relyingPartyId: 'rp.test',
        challenge: 'challenge',
        mediation: MediationType.Optional,
        preferImmediatelyAvailableCredentials: true,
      ),
    );
  });

  late MockAppAuth appAuth;
  late MockSecureStorage storage;
  late MockDio http;
  late MockPasskeyAuthenticator passkeyAuthenticator;
  late Map<String, String> store;

  setUp(() {
    store = {};
    appAuth = MockAppAuth();
    storage = MockSecureStorage();
    http = MockDio();
    passkeyAuthenticator = MockPasskeyAuthenticator();

    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((inv) async => store[inv.namedArguments[#key] as String]);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((inv) async {
      store[inv.namedArguments[#key] as String] =
          inv.namedArguments[#value] as String;
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((inv) async {
      store.remove(inv.namedArguments[#key] as String);
    });
  });

  /// Stubs the GET /oauth/v2/authorize redirect-capture call, matching the
  /// password flow's tests (deployed ZITADEL names the query param `authRequest`).
  void stubAuthorizeRedirect(String authRequestId) {
    when(
      () => http.get<void>(
        any(that: contains('/oauth/v2/authorize')),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: '/oauth/v2/authorize'),
        statusCode: 302,
        headers: Headers.fromMap({
          'location': [
            'https://issuer.test/ui/v1/login?authRequest=$authRequestId',
          ],
        }),
      ),
    );
  }

  void stubStart(Map<String, dynamic> data) {
    when(
      () => http.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/login/start')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/MobileAuth/passkey/login/start',
        ),
        statusCode: 200,
        data: data,
      ),
    );
  }

  void stubStartError(String code) {
    when(
      () => http.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/login/start')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(
          path: '/api/MobileAuth/passkey/login/start',
        ),
        response: Response<dynamic>(
          requestOptions: RequestOptions(
            path: '/api/MobileAuth/passkey/login/start',
          ),
          statusCode: 400,
          data: {'code': code},
        ),
      ),
    );
  }

  void stubComplete({String code = 'auth-code-1'}) {
    when(
      () => http.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/login/complete')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/MobileAuth/passkey/login/complete',
        ),
        statusCode: 200,
        data: {'code': code},
      ),
    );
  }

  void stubCompleteError(String code) {
    when(
      () => http.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/login/complete')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(
          path: '/api/MobileAuth/passkey/login/complete',
        ),
        response: Response<dynamic>(
          requestOptions: RequestOptions(
            path: '/api/MobileAuth/passkey/login/complete',
          ),
          statusCode: 400,
          data: {'code': code},
        ),
      ),
    );
  }

  void stubTokenExchange() {
    when(() => appAuth.token(any())).thenAnswer(
      (_) async => TokenResponse(
        'access-1',
        'refresh-1',
        DateTime.now().add(const Duration(hours: 1)),
        _fakeIdToken(),
        null,
        null,
        null,
      ),
    );
  }

  ZitadelAuthRepository repo() => ZitadelAuthRepository(
    appAuth: appAuth,
    storage: storage,
    revocationHttpClient: http,
    passkeyAuthenticator: passkeyAuthenticator,
    restore: false,
  );

  group('signInWithPasskey', () {
    test(
      'unwraps publicKey before authenticating and sends toJson() to complete',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenAnswer((_) async => _assertion());
        stubComplete();
        stubTokenExchange();

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.failure, isNull);
        expect(result.user?.accessToken, 'access-1');

        // Start: the exact contract body — no rpId, no password.
        final startBody =
            verify(
                  () => http.post<dynamic>(
                    any(that: contains('/api/MobileAuth/passkey/login/start')),
                    data: captureAny(named: 'data'),
                    options: any(named: 'options'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(startBody, {
          'authRequestId': 'authreq-1',
          'loginName': 'tech@tasktap.io',
        });
        expect(startBody.containsKey('rpId'), isFalse);

        // The authenticator received the UNWRAPPED options.
        final authRequest =
            verify(
                  () => passkeyAuthenticator.authenticate(captureAny()),
                ).captured.single
                as AuthenticateRequestType;
        expect(authRequest.challenge, 'Y2hhbGxlbmdl');
        expect(authRequest.relyingPartyId, 'auth.tasktap.it');

        // Complete: the package's nested toJson() shape, and no loginName.
        final completeBody =
            verify(
                  () => http.post<dynamic>(
                    any(
                      that: contains('/api/MobileAuth/passkey/login/complete'),
                    ),
                    data: captureAny(named: 'data'),
                    options: any(named: 'options'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(completeBody['authRequestId'], 'authreq-1');
        expect(completeBody['sessionId'], 's1');
        expect(completeBody['sessionToken'], 'st');
        expect(completeBody.containsKey('loginName'), isFalse);

        final assertionData =
            completeBody['credentialAssertionData'] as Map<String, dynamic>;
        expect(assertionData['id'], 'cred-1');
        expect(assertionData['type'], 'public-key');
        final assertionResponse =
            assertionData['response'] as Map<String, dynamic>;
        expect(assertionResponse['clientDataJSON'], 'client-data-json');
        expect(assertionResponse['authenticatorData'], 'authenticator-data');
        expect(assertionResponse['signature'], 'signature');

        // The existing code-exchange / persist / emit path is reused.
        final tokenCall =
            verify(() => appAuth.token(captureAny())).captured.single
                as TokenRequest;
        expect(tokenCall.authorizationCode, 'auth-code-1');
        expect(tokenCall.codeVerifier, isNotEmpty);
        expect(store[_refreshTokenKey], 'refresh-1');
        expect(store[_cachedIdentityKey], contains('tech@tasktap.io'));
      },
    );

    test('no_passkey_registered maps to PasskeyNotRegistered', () async {
      stubAuthorizeRedirect('authreq-1');
      stubStartError('no_passkey_registered');

      final result = await repo().signInWithPasskey('nobody@tasktap.io');

      expect(result.user, isNull);
      expect(result.failure, isA<PasskeyNotRegistered>());
      verifyNever(() => passkeyAuthenticator.authenticate(any()));
      verifyNever(() => appAuth.token(any()));
    });

    test(
      'passkey_verification_failed maps to PasskeyVerificationFailed',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenAnswer((_) async => _assertion());
        stubCompleteError('passkey_verification_failed');

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<PasskeyVerificationFailed>());
        expect(
          authFailureMessage(result.failure!),
          'Non è stato possibile verificare la passkey. Riprova o accedi con la password.',
        );
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'identity_provider_unavailable maps to ServiceUnavailable',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenAnswer((_) async => _assertion());
        stubCompleteError('identity_provider_unavailable');

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<ServiceUnavailable>());
        expect(
          authFailureMessage(result.failure!),
          'Servizio temporaneamente non disponibile. Riprova tra poco.',
        );
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'additional_factor_required maps to AdditionalFactorRequired',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenAnswer((_) async => _assertion());
        stubCompleteError('additional_factor_required');

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<AdditionalFactorRequired>());
        verifyNever(() => appAuth.token(any()));
      },
    );

    test('a cancelled sheet maps to PasskeyCancelled', () async {
      stubAuthorizeRedirect('authreq-1');
      stubStart(_startPayload());
      when(
        () => passkeyAuthenticator.authenticate(any()),
      ).thenThrow(PasskeyAuthCancelledException());

      final result = await repo().signInWithPasskey('tech@tasktap.io');

      expect(result.user, isNull);
      expect(result.failure, isA<PasskeyCancelled>());
      verifyNever(
        () => http.post<dynamic>(
          any(that: contains('/api/MobileAuth/passkey/login/complete')),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
      verifyNever(() => appAuth.token(any()));
    });

    test(
      'no credentials on this device maps to PasskeyNotRegistered',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenThrow(NoCredentialsAvailableException());

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<PasskeyNotRegistered>());
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'missing publicKey in the options maps to UnknownAuthError, never throws',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart({
          'sessionId': 's1',
          'sessionToken': 'st',
          'publicKeyCredentialRequestOptions': <String, dynamic>{},
        });

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        verifyNever(() => passkeyAuthenticator.authenticate(any()));
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'missing session fields maps to UnknownAuthError, never throws',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload(sessionToken: null));

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        verifyNever(() => passkeyAuthenticator.authenticate(any()));
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'a publicKey that is present but not an object maps to UnknownAuthError, '
      'never throws',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart({
          'sessionId': 's1',
          'sessionToken': 'st',
          'publicKeyCredentialRequestOptions': {'publicKey': 'not-an-object'},
        });

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        verifyNever(() => passkeyAuthenticator.authenticate(any()));
        verifyNever(() => appAuth.token(any()));
      },
    );

    // Distinct from the "not an object" branch above: the unwrapped publicKey IS
    // a Map, so it reaches AuthenticateRequestType.fromJson, which throws on a
    // non-String challenge. The catch-all around start parsing must turn that
    // into a typed failure rather than let the TypeError escape.
    test(
      'a publicKey that AuthenticateRequestType.fromJson rejects maps to '
      'UnknownAuthError, never throws',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart({
          'sessionId': 's1',
          'sessionToken': 'st',
          'publicKeyCredentialRequestOptions': {
            'publicKey': <String, dynamic>{
              'challenge': 123,
              'rpId': 'auth.tasktap.it',
            },
          },
        });

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        verifyNever(() => passkeyAuthenticator.authenticate(any()));
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'a passkey-unsupported platform error maps to PasskeyUnavailable',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenThrow(PasskeyUnsupportedException('Android API < 28'));

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<PasskeyUnavailable>());
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'a domain-not-associated platform error maps to PasskeyUnavailable',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(() => passkeyAuthenticator.authenticate(any())).thenThrow(
          DomainNotAssociatedException('app is not associated with the RP ID'),
        );

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<PasskeyUnavailable>());
        verifyNever(() => appAuth.token(any()));
      },
    );

    test(
      'a malformed complete response returns UnknownAuthError, does not throw',
      () async {
        stubAuthorizeRedirect('authreq-1');
        stubStart(_startPayload());
        when(
          () => passkeyAuthenticator.authenticate(any()),
        ).thenAnswer((_) async => _assertion());
        when(
          () => http.post<dynamic>(
            any(that: contains('/api/MobileAuth/passkey/login/complete')),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenAnswer(
          (_) async => Response<dynamic>(
            requestOptions: RequestOptions(
              path: '/api/MobileAuth/passkey/login/complete',
            ),
            statusCode: 200,
            data: <String, dynamic>{},
          ),
        );

        final result = await repo().signInWithPasskey('tech@tasktap.io');

        expect(result.user, isNull);
        expect(result.failure, isA<UnknownAuthError>());
        verifyNever(() => appAuth.token(any()));
      },
    );
  });
}
