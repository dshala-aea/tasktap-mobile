import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

// ── Fallback stubs ─────────────────────────────────────────────────────────

class FakeDioException extends Fake implements DioException {}

class FakeResponse extends Fake implements Response<dynamic> {}

// ── Helpers ────────────────────────────────────────────────────────────────

AuthUser _fakeUser({String token = 'old-token'}) => AuthUser(
      id: 'u1',
      email: 'tech@tasktap.io',
      accessToken: token,
      refreshToken: 'refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

DioException _make401(RequestOptions options) => DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(FakeDioException());
    registerFallbackValue(FakeResponse());
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late MockAuthRepository repo;
  late Dio dio;
  late AuthInterceptor interceptor;

  setUp(() {
    repo = MockAuthRepository();
    dio = Dio();
    interceptor = AuthInterceptor(dio: dio, authRepo: repo);
  });

  // ── onRequest: attaches Bearer token ──────────────────────────────────

  group('onRequest', () {
    test('adds Authorization header when user is authenticated', () {
      when(() => repo.currentUser).thenReturn(_fakeUser(token: 'my-token'));

      final options = RequestOptions(path: '/api/test');
      final handler = MockRequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], equals('Bearer my-token'));
      verify(() => handler.next(options)).called(1);
    });

    test('does not add Authorization header when user is null', () {
      when(() => repo.currentUser).thenReturn(null);

      final options = RequestOptions(path: '/api/test');
      final handler = MockRequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(options)).called(1);
    });
  });

  // ── onError: non-401 pass-through ─────────────────────────────────────

  group('onError — non-401 pass-through', () {
    test('500 errors pass through unchanged without calling refreshSession', () async {
      final options = RequestOptions(path: '/api/test');
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(requestOptions: options, statusCode: 500),
        type: DioExceptionType.badResponse,
      );
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
      verifyNever(() => repo.refreshSession());
    });
  });

  // ── onError: 401 + refresh success ────────────────────────────────────

  group('onError — 401 + refresh success', () {
    test('calls refreshSession on 401', () async {
      final newUser = _fakeUser(token: 'new-token');
      when(() => repo.refreshSession()).thenAnswer(
        (_) async => (user: newUser, failure: null),
      );

      // Track the options passed to dio.fetch by installing a no-op adapter.
      final List<RequestOptions> fetchedOptions = [];
      dio.httpClientAdapter = _StubAdapter(
        onFetch: (opts) {
          fetchedOptions.add(opts);
          return ResponseBody.fromString('{}', 200);
        },
      );

      final options = RequestOptions(
        path: '/api/data',
        baseUrl: 'http://localhost',
      );
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verify(() => repo.refreshSession()).called(1);
    });

    test('retry request has new token in Authorization header', () async {
      final newUser = _fakeUser(token: 'refreshed-token');
      when(() => repo.refreshSession()).thenAnswer(
        (_) async => (user: newUser, failure: null),
      );

      final List<RequestOptions> fetchedOptions = [];
      dio.httpClientAdapter = _StubAdapter(
        onFetch: (opts) {
          fetchedOptions.add(opts);
          return ResponseBody.fromString('{}', 200);
        },
      );

      final options = RequestOptions(
        path: '/api/data',
        baseUrl: 'http://localhost',
      );
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      // The fetched request should have the new token.
      expect(fetchedOptions, isNotEmpty);
      expect(
        fetchedOptions.first.headers['Authorization'],
        equals('Bearer refreshed-token'),
      );
    });
  });

  // ── onError: 401 + refresh failure → sign-out ─────────────────────────

  group('onError — 401 + refresh failure', () {
    setUp(() {
      when(() => repo.refreshSession()).thenAnswer(
        (_) async => (user: null, failure: const SessionExpired()),
      );
      when(() => repo.signOut()).thenAnswer((_) async {});
    });

    test('calls signOut when refresh fails', () async {
      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verify(() => repo.signOut()).called(1);
    });

    test('calls handler.next (passing the original error through)', () async {
      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verify(() => handler.next(any())).called(1);
    });

    test('invokes onForcedSignOut callback when set', () async {
      var signOutCalled = false;
      interceptor.onForcedSignOut = () => signOutCalled = true;

      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      expect(signOutCalled, isTrue);
    });
  });

  // ── onError: already-retried request skips refresh ────────────────────

  group('onError — retry guard', () {
    test('request with _retried=true does NOT call refreshSession', () async {
      // Fresh repo/interceptor to avoid shared mock state.
      final freshRepo = MockAuthRepository();
      final freshInterceptor = AuthInterceptor(dio: dio, authRepo: freshRepo);

      final options = RequestOptions(
        path: '/api/data',
        extra: {'_retried': true},
      );
      final handler = MockErrorInterceptorHandler();

      await freshInterceptor.onError(_make401(options), handler);

      verifyNever(() => freshRepo.refreshSession());
      verify(() => handler.next(any())).called(1);
    });
  });
}

// ── Stub HTTP adapter ─────────────────────────────────────────────────────

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.onFetch});

  final ResponseBody Function(RequestOptions) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}
