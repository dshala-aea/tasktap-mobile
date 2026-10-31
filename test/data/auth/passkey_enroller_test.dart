// Tests for the passkey enrolment client.
//
// The flow under test is the enrolment half of the passkey design's §8:
// `register/start` returns ZITADEL's creation options wrapped in a top-level
// `publicKey`, which must be unwrapped before `RegisterRequestType.fromJson`;
// the platform authenticator produces the credential; `register/complete`
// receives the package's own `toJson()` shape. The bearer token is attached by
// `dioProvider`'s interceptor, so nothing here sets one.
//
// Dio and the passkey authenticator are mocked (mocktail); no test touches a
// platform channel.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:tasktap_mobile/data/auth/passkey_enroller.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';

class MockDio extends Mock implements Dio {}

class MockPasskeyAuthenticator extends Mock implements PasskeyAuthenticator {}

const _publicKey = <String, dynamic>{
  'challenge': 'Y2hhbGxlbmdl',
  'rp': {'name': 'TaskTap', 'id': 'auth.tasktap.it'},
  'user': {'id': 'dXNlci0x', 'name': 'tech@tasktap.io', 'displayName': 'Tecnico'},
  'pubKeyCredParams': [
    {'type': 'public-key', 'alg': -7},
  ],
  'timeout': 60000,
  'authenticatorSelection': {'residentKey': 'required', 'userVerification': 'required'},
  'excludeCredentials': <dynamic>[],
  'attestation': 'none',
};

/// The start endpoint's response, with the creation options nested inside
/// `publicKey` exactly as ZITADEL wraps them.
Map<String, dynamic> _startPayload({Map<String, dynamic>? publicKey = _publicKey}) => {
  'passkeyId': 'pk-1',
  'publicKeyCredentialCreationOptions': {'publicKey': publicKey},
};

RegisterResponseType _credential() => const RegisterResponseType(
  id: 'cred-1',
  rawId: 'cred-1',
  clientDataJSON: 'client-data-json',
  attestationObject: 'attestation-object',
  transports: ['internal'],
);

DioException _dioError({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Map<String, dynamic>? body,
  String path = '/api/MobileAuth/passkey',
}) => DioException(
  requestOptions: RequestOptions(path: path),
  type: type,
  response: statusCode == null
      ? null
      : Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: statusCode,
          data: body,
        ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      RegisterRequestType(
        challenge: 'challenge',
        relyingParty: RelyingPartyType(name: 'TaskTap', id: 'auth.tasktap.it'),
        user: const UserType(id: 'user-1', name: 'tech@tasktap.io', displayName: 'Tecnico'),
        excludeCredentials: const [],
      ),
    );
  });

  late MockDio dio;
  late MockPasskeyAuthenticator authenticator;

  setUp(() {
    dio = MockDio();
    authenticator = MockPasskeyAuthenticator();
  });

  PasskeyEnroller enroller() => PasskeyEnroller(dio, passkeyAuthenticator: authenticator);

  void stubStart(Map<String, dynamic> data) {
    when(
      () => dio.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/register/start')),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/MobileAuth/passkey/register/start'),
        statusCode: 200,
        data: data,
      ),
    );
  }

  void stubStartError(DioException error) {
    when(
      () => dio.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/register/start')),
        data: any(named: 'data'),
      ),
    ).thenThrow(error);
  }

  void stubComplete({DioException? error}) {
    final stub = when(
      () => dio.post<dynamic>(
        any(that: contains('/api/MobileAuth/passkey/register/complete')),
        data: any(named: 'data'),
      ),
    );
    if (error != null) {
      stub.thenThrow(error);
    } else {
      stub.thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/MobileAuth/passkey/register/complete'),
          statusCode: 204,
        ),
      );
    }
  }

  group('enrol', () {
    test('enrol unwraps publicKey, registers, and posts publicKeyCredential', () async {
      stubStart(_startPayload());
      when(() => authenticator.register(any())).thenAnswer((_) async => _credential());
      stubComplete();

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isTrue);
      expect(result.failure, isNull);

      final request =
          verify(() => authenticator.register(captureAny())).captured.single as RegisterRequestType;
      expect(request.challenge, 'Y2hhbGxlbmdl');
      expect(request.relyingParty.id, 'auth.tasktap.it');
      expect(request.user.name, 'tech@tasktap.io');

      final body =
          verify(
                () => dio.post<dynamic>(
                  any(that: contains('/api/MobileAuth/passkey/register/complete')),
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(body, {
        'passkeyId': 'pk-1',
        'publicKeyCredential': _credential().toJson(),
        'passkeyName': 'Pixel 9',
      });
    });

    test('enrol offline returns NetworkError and does not claim success', () async {
      stubStartError(
        _dioError(
          type: DioExceptionType.connectionError,
          path: '/api/MobileAuth/passkey/register/start',
        ),
      );

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isFalse);
      expect(result.failure, isA<NetworkError>());
      verifyNever(() => authenticator.register(any()));
    });

    test('enrol complete failure returns UnknownAuthError', () async {
      stubStart(_startPayload());
      when(() => authenticator.register(any())).thenAnswer((_) async => _credential());
      stubComplete(
        error: _dioError(
          statusCode: 400,
          body: {'code': 'something_unexpected'},
          path: '/api/MobileAuth/passkey/register/complete',
        ),
      );

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isFalse);
      expect(result.failure, isA<UnknownAuthError>());
    });

    test('passkey_registration_failed maps to PasskeyRegistrationFailed', () async {
      stubStart(_startPayload());
      when(() => authenticator.register(any())).thenAnswer((_) async => _credential());
      stubComplete(
        error: _dioError(
          statusCode: 400,
          body: {'code': 'passkey_registration_failed'},
          path: '/api/MobileAuth/passkey/register/complete',
        ),
      );

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isFalse);
      expect(result.failure, isA<PasskeyRegistrationFailed>());
      expect(authFailureMessage(result.failure!), 'Impossibile attivare la passkey. Riprova.');
    });

    test('cancelled registration is ok=false, failure=null', () async {
      stubStart(_startPayload());
      when(() => authenticator.register(any())).thenThrow(PasskeyAuthCancelledException());

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isFalse);
      expect(result.failure, isNull);
      verifyNever(
        () => dio.post<dynamic>(
          any(that: contains('/api/MobileAuth/passkey/register/complete')),
          data: any(named: 'data'),
        ),
      );
    });

    test('platform domain errors map to PasskeyUnavailable', () async {
      stubStart(_startPayload());
      when(
        () => authenticator.register(any()),
      ).thenThrow(DomainNotAssociatedException('bad rp id'));

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isFalse);
      expect(result.failure, isA<PasskeyUnavailable>());
    });

    test('a start response without the publicKey wrapper is not passed to the platform', () async {
      stubStart({'passkeyId': 'pk-1', 'publicKeyCredentialCreationOptions': _publicKey});

      final result = await enroller().enrol(name: 'Pixel 9');

      expect(result.ok, isFalse);
      expect(result.failure, isA<UnknownAuthError>());
      verifyNever(() => authenticator.register(any()));
    });
  });

  group('list', () {
    test('list parses id and name', () async {
      when(() => dio.get<dynamic>(any(that: contains('/api/MobileAuth/passkey')))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/MobileAuth/passkey'),
          statusCode: 200,
          data: [
            {'id': 'pk-1', 'name': 'Pixel 9'},
            {'id': 'pk-2', 'name': 'iPad ufficio'},
          ],
        ),
      );

      final passkeys = await enroller().list();

      expect(passkeys, const [(id: 'pk-1', name: 'Pixel 9'), (id: 'pk-2', name: 'iPad ufficio')]);
    });
  });

  group('remove', () {
    test('remove issues DELETE for the id', () async {
      when(
        () => dio.delete<dynamic>(any(that: contains('/api/MobileAuth/passkey/pk-1'))),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/MobileAuth/passkey/pk-1'),
          statusCode: 204,
        ),
      );

      final result = await enroller().remove('pk-1');

      expect(result.ok, isTrue);
      expect(result.failure, isNull);
      verify(
        () => dio.delete<dynamic>(any(that: contains('/api/MobileAuth/passkey/pk-1'))),
      ).called(1);
    });
  });
}
