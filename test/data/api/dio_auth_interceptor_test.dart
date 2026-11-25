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

class MockRequestInterceptorHandler extends Mock implements RequestInterceptorHandler {}

class MockErrorInterceptorHandler extends Mock implements ErrorInterceptorHandler {}

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
  response: Response<dynamic>(requestOptions: options, statusCode: 401),
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

  // ── anonymous (noAuth) requests ───────────────────────────────────────

  group('noAuth requests (version-policy probe)', () {
    test('no Authorization header even when signed in', () {
      when(() => repo.currentUser).thenReturn(_fakeUser(token: 'my-token'));
      final options = RequestOptions(path: '/api/app/version-policy', extra: {'noAuth': true});
      final handler = MockRequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(options)).called(1);
    });

    test('a 401 does not refresh the session nor end it', () async {
      var ended = false;
      interceptor.onForcedSignOut = () async => ended = true;
      final options = RequestOptions(path: '/api/app/version-policy', extra: {'noAuth': true});
      final err = _make401(options);
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
      verifyNever(() => repo.refreshSession());
      verifyNever(() => repo.signOut());
      expect(ended, isFalse);
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
      when(() => repo.refreshSession()).thenAnswer((_) async => (user: newUser, failure: null));

      // Track the options passed to dio.fetch by installing a no-op adapter.
      final List<RequestOptions> fetchedOptions = [];
      dio.httpClientAdapter = _StubAdapter(
        onFetch: (opts) {
          fetchedOptions.add(opts);
          return ResponseBody.fromString('{}', 200);
        },
      );

      final options = RequestOptions(path: '/api/data', baseUrl: 'http://localhost');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verify(() => repo.refreshSession()).called(1);
    });

    test('retry request has new token in Authorization header', () async {
      final newUser = _fakeUser(token: 'refreshed-token');
      when(() => repo.refreshSession()).thenAnswer((_) async => (user: newUser, failure: null));

      final List<RequestOptions> fetchedOptions = [];
      dio.httpClientAdapter = _StubAdapter(
        onFetch: (opts) {
          fetchedOptions.add(opts);
          return ResponseBody.fromString('{}', 200);
        },
      );

      final options = RequestOptions(path: '/api/data', baseUrl: 'http://localhost');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      // The fetched request should have the new token.
      expect(fetchedOptions, isNotEmpty);
      expect(fetchedOptions.first.headers['Authorization'], equals('Bearer refreshed-token'));
    });
  });

  // ── onError: 401 + refresh failure → sign-out ─────────────────────────

  group('onError — 401 + refresh failure', () {
    setUp(() {
      when(
        () => repo.refreshSession(),
      ).thenAnswer((_) async => (user: null, failure: const SessionExpired()));
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
      // The hook is awaited (it is the whole session teardown — `SessionEnder`), so it is a
      // `Future<void> Function()?` rather than a bare callback.
      interceptor.onForcedSignOut = () async {
        signOutCalled = true;
      };

      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      expect(signOutCalled, isTrue);
    });
  });

  // ── onError: 401 + refresh unreachable (NetworkError) → session preserved ──
  //
  // Regression for a real cold-start bug: HomeShell's first sync fires before the radio has
  // finished registering, the 401 lands on the not-yet-re-minted access token, and the refresh
  // attempt races the same signal gap. Treating that NetworkError like a real auth failure was
  // forcing a fresh interactive login — needing network — on every such cold start. Only a
  // genuine failure (SessionExpired etc., covered above) should sign the user out.

  group('onError — 401 + refresh unreachable', () {
    setUp(() {
      when(
        () => repo.refreshSession(),
      ).thenAnswer((_) async => (user: null, failure: const NetworkError()));
      when(() => repo.signOut()).thenAnswer((_) async {});
    });

    test('does NOT call signOut', () async {
      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verifyNever(() => repo.signOut());
    });

    test('does NOT invoke onForcedSignOut', () async {
      var called = false;
      interceptor.onForcedSignOut = () async {
        called = true;
      };

      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      expect(called, isFalse);
    });

    test('still passes the original error through (the request fails for now)', () async {
      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verify(() => handler.next(any())).called(1);
    });
  });

  // ── onError: 401 + refresh fails with an unclassified error → session preserved ──
  //
  // Regression: _mapError's fallback returns UnknownAuthError for things that are not proof the
  // refresh token is dead — a malformed/glitchy token response, a JSON parsing hiccup, a Zitadel
  // 5xx during refresh. Only a confirmed SessionExpired means the session is actually gone (see
  // ZitadelAuthRepository._restore's identical narrowing). Forcing sign-out on anything broader
  // was bouncing users to the login screen on ordinary transient glitches.

  group('onError — 401 + refresh fails with an unclassified error', () {
    setUp(() {
      when(
        () => repo.refreshSession(),
      ).thenAnswer((_) async => (user: null, failure: const UnknownAuthError('glitch')));
      when(() => repo.signOut()).thenAnswer((_) async {});
    });

    test('does NOT call signOut', () async {
      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verifyNever(() => repo.signOut());
    });

    test('does NOT invoke onForcedSignOut', () async {
      var called = false;
      interceptor.onForcedSignOut = () async {
        called = true;
      };

      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      expect(called, isFalse);
    });

    test('still passes the original error through (the request fails for now)', () async {
      final options = RequestOptions(path: '/api/data');
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verify(() => handler.next(any())).called(1);
    });
  });

  // ── onError: already-retried request skips refresh ────────────────────

  group('onError — retry guard', () {
    test('request with _retried=true does NOT call refreshSession', () async {
      // Fresh repo/interceptor to avoid shared mock state.
      final freshRepo = MockAuthRepository();
      final freshInterceptor = AuthInterceptor(dio: dio, authRepo: freshRepo);

      final options = RequestOptions(path: '/api/data', extra: {'_retried': true});
      final handler = MockErrorInterceptorHandler();

      await freshInterceptor.onError(_make401(options), handler);

      verifyNever(() => freshRepo.refreshSession());
      verify(() => handler.next(any())).called(1);
    });
  });

  // ── proactive refresh before a request leaves (queue flush / sync) ─────

  group('onRequest — proactive refresh of an expired token', () {
    AuthUser userExpiringIn(Duration d, {String token = 'stale-token'}) => AuthUser(
      id: 'u1',
      email: 'tech@tasktap.io',
      accessToken: token,
      refreshToken: 'refresh',
      expiresAt: DateTime.now().toUtc().add(d),
    );

    /// Runs onRequest and waits for the handler to be completed (the refresh is async).
    Future<void> send(AuthInterceptor i, RequestOptions options) async {
      final done = Completer<void>();
      final handler = MockRequestInterceptorHandler();
      when(() => handler.next(any())).thenAnswer((_) => done.complete());
      i.onRequest(options, handler);
      await done.future.timeout(const Duration(seconds: 2));
    }

    test('expired token + online: exactly one refresh, the call carries the NEW token', () async {
      var current = userExpiringIn(const Duration(minutes: -5));
      when(() => repo.currentUser).thenAnswer((_) => current);
      when(() => repo.refreshSession()).thenAnswer((_) async {
        current = userExpiringIn(const Duration(hours: 1), token: 'fresh-token');
        return (user: current, failure: null);
      });
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => true);
      final options = RequestOptions(path: '/api/sync');

      await send(i, options);

      verify(() => repo.refreshSession()).called(1);
      expect(options.headers['Authorization'], 'Bearer fresh-token');
    });

    test('a token expiring within 60 s is refreshed too; one with margin is not', () async {
      var current = userExpiringIn(const Duration(seconds: 30));
      when(() => repo.currentUser).thenAnswer((_) => current);
      when(() => repo.refreshSession()).thenAnswer((_) async {
        current = userExpiringIn(const Duration(hours: 1), token: 'fresh-token');
        return (user: current, failure: null);
      });
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => true);

      await send(i, RequestOptions(path: '/api/a'));

      // now fresh (1 h): no further refresh
      final options = RequestOptions(path: '/api/b');
      await send(i, options);

      verify(() => repo.refreshSession()).called(1); // total across both requests
      expect(options.headers['Authorization'], 'Bearer fresh-token');
    });

    test('the offline-restored session (empty access token) is refreshed once online', () async {
      var current = AuthUser(
        id: 'u1',
        email: 'tech@tasktap.io',
        accessToken: '',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().toUtc(),
      );
      when(() => repo.currentUser).thenAnswer((_) => current);
      when(() => repo.refreshSession()).thenAnswer((_) async {
        current = userExpiringIn(const Duration(hours: 1), token: 'fresh-token');
        return (user: current, failure: null);
      });
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => true);
      final options = RequestOptions(path: '/api/sync');

      await send(i, options);

      verify(() => repo.refreshSession()).called(1);
      expect(options.headers['Authorization'], 'Bearer fresh-token');
    });

    test('offline: NO refresh attempt, nothing prompted, the request just goes out', () async {
      when(() => repo.currentUser).thenReturn(userExpiringIn(const Duration(minutes: -5)));
      var ended = false;
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => false)
        ..onForcedSignOut = () async => ended = true;
      final options = RequestOptions(path: '/api/sync');
      final handler = MockRequestInterceptorHandler();

      i.onRequest(options, handler);

      verify(() => handler.next(options)).called(1); // synchronous: nothing awaited
      verifyNever(() => repo.refreshSession());
      verifyNever(() => repo.signOut());
      expect(ended, isFalse);
      expect(options.headers['Authorization'], 'Bearer stale-token');
    });

    test('connectivity unknown (no isOnline wired): behaviour unchanged, no refresh', () async {
      when(() => repo.currentUser).thenReturn(userExpiringIn(const Duration(minutes: -5)));
      final options = RequestOptions(path: '/api/sync');
      final handler = MockRequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      verify(() => handler.next(options)).called(1);
      verifyNever(() => repo.refreshSession());
    });

    test('a failed proactive refresh does not hang the request nor end the session', () async {
      when(() => repo.currentUser).thenReturn(userExpiringIn(const Duration(minutes: -5)));
      when(
        () => repo.refreshSession(),
      ).thenAnswer((_) async => (user: null, failure: const NetworkError()));
      var ended = false;
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => true)
        ..onForcedSignOut = () async => ended = true;
      final options = RequestOptions(path: '/api/sync');

      await send(i, options);

      expect(ended, isFalse);
      expect(options.headers['Authorization'], 'Bearer stale-token');
    });

    test('a refresh that throws still lets the request go', () async {
      when(() => repo.currentUser).thenReturn(userExpiringIn(const Duration(minutes: -5)));
      when(() => repo.refreshSession()).thenThrow(StateError('boom'));
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => true);

      await send(i, RequestOptions(path: '/api/sync')); // completes, does not time out
    });

    test('anonymous (noAuth) requests never trigger a refresh', () async {
      when(() => repo.currentUser).thenReturn(userExpiringIn(const Duration(minutes: -5)));
      final i = AuthInterceptor(dio: dio, authRepo: repo, isOnline: () => true);
      final handler = MockRequestInterceptorHandler();

      i.onRequest(RequestOptions(path: '/api/app/version-policy', extra: {'noAuth': true}), handler);

      verifyNever(() => repo.refreshSession());
    });

    test('end to end: expired token, one refresh, ONE request on the wire, no 401 round trip',
        () async {
      var current = userExpiringIn(const Duration(minutes: -5));
      when(() => repo.currentUser).thenAnswer((_) => current);
      when(() => repo.refreshSession()).thenAnswer((_) async {
        current = userExpiringIn(const Duration(hours: 1), token: 'fresh-token');
        return (user: current, failure: null);
      });
      final wire = <RequestOptions>[];
      final d = Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = _StubAdapter(
          onFetch: (o) {
            wire.add(o);
            return ResponseBody.fromString('{}', 200);
          },
        );
      d.interceptors.add(AuthInterceptor(dio: d, authRepo: repo, isOnline: () => true));

      final r1 = d.get<dynamic>('/api/a');
      final r2 = d.get<dynamic>('/api/b');
      await Future.wait([r1, r2]);

      expect(wire, hasLength(2), reason: 'no request burned on a predictable 401');
      expect(wire.every((o) => o.headers['Authorization'] == 'Bearer fresh-token'), isTrue);
    });
  });

  // ── what the 401 path does after the proactive step ────────────────────

  group('onError — after a failed proactive refresh', () {
    RequestOptions failedPreflight(AuthFailure f) =>
        RequestOptions(path: '/api/data', extra: {'_preflightRefreshFailure': f});

    test('invalid_grant: forced end, WITHOUT redeeming the refresh token a second time', () async {
      var ended = 0;
      interceptor.onForcedSignOut = () async => ended++;
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(failedPreflight(const SessionExpired())), handler);

      verifyNever(() => repo.refreshSession());
      expect(ended, 1);
      verify(() => handler.next(any())).called(1);
    });

    test('network error: session kept, the call fails (retryable), no second refresh', () async {
      var ended = 0;
      interceptor.onForcedSignOut = () async => ended++;
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(failedPreflight(const NetworkError())), handler);

      verifyNever(() => repo.refreshSession());
      verifyNever(() => repo.signOut());
      expect(ended, 0);
      verify(() => handler.next(any())).called(1);
    });
  });

  // ── offline failures are not auth events ───────────────────────────────

  group('onError — offline', () {
    test('a connection error (no response) attempts no refresh and ends nothing', () async {
      var ended = 0;
      interceptor.onForcedSignOut = () async => ended++;
      final options = RequestOptions(path: '/api/data');
      final err = DioException(requestOptions: options, type: DioExceptionType.connectionError);
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      verifyNever(() => repo.refreshSession());
      verifyNever(() => repo.signOut());
      expect(ended, 0);
      verify(() => handler.next(err)).called(1);
    });
  });

  // ── concurrent 401s share one refresh ──────────────────────────────────

  group('onError — concurrent 401s', () {
    test('a 401 whose bearer was already replaced by another caller does not refresh again',
        () async {
      // Request A and B left with the old token; A's 401 refreshed the session; B's 401 arrives
      // afterwards. B must retry with the current token, not redeem the refresh token again.
      final fresh = _fakeUser(token: 'fresh-token');
      when(() => repo.currentUser).thenReturn(fresh);
      final fetched = <RequestOptions>[];
      dio.httpClientAdapter = _StubAdapter(
        onFetch: (o) {
          fetched.add(o);
          return ResponseBody.fromString('{}', 200);
        },
      );
      final options = RequestOptions(
        path: '/api/data',
        baseUrl: 'http://localhost',
        headers: {'Authorization': 'Bearer old-token'},
      );
      final handler = MockErrorInterceptorHandler();

      await interceptor.onError(_make401(options), handler);

      verifyNever(() => repo.refreshSession());
      expect(fetched.single.headers['Authorization'], 'Bearer fresh-token');
    });

    test('two simultaneous 401s on the same stale token both end up on one repo refresh call',
        () async {
      // The repository coalesces overlapping calls (see zitadel_auth_repository_test single-flight);
      // here the interceptor must not add a refresh of its own beyond one per request.
      when(() => repo.currentUser).thenReturn(_fakeUser(token: 'old-token'));
      when(() => repo.refreshSession()).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return (user: _fakeUser(token: 'fresh-token'), failure: null);
      });
      dio.httpClientAdapter = _StubAdapter(onFetch: (_) => ResponseBody.fromString('{}', 200));
      RequestOptions req() => RequestOptions(
        path: '/api/data',
        baseUrl: 'http://localhost',
        headers: {'Authorization': 'Bearer old-token'},
      );

      await Future.wait([
        interceptor.onError(_make401(req()), MockErrorInterceptorHandler()),
        interceptor.onError(_make401(req()), MockErrorInterceptorHandler()),
      ]);

      verify(() => repo.refreshSession()).called(2); // one per request; the repo makes it ONE exchange
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
