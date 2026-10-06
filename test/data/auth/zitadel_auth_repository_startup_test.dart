// Cold-start hardening for ZitadelAuthRepository._restore().
//
// App Store review rejected build 1.0 (50): "stuck on the splash screen". _restore() is started
// unawaited from the constructor; if the keychain read threw/hung, or the native AppAuth refresh
// hung, NOTHING was ever emitted and authStateProvider stayed AsyncLoading forever. These tests
// pin that every such path now settles (emit) within a bounded time, while keeping the
// offline-tolerance semantics: only a confirmed SessionExpired wipes the token.
//
// Timers run on the testWidgets fake clock; `tester.pump(duration)` advances it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/auth/zitadel_auth_repository.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';

class MockAppAuth extends Mock implements FlutterAppAuth {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

const _refreshTokenKey = 'tt.oidc.refresh_token';
const _cachedIdentityKey = 'tt.oidc.cached_identity';

String _fakeIdToken({String sub = 'u-fresh'}) {
  String seg(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m)));
  return '${seg({'alg': 'none'})}.${seg({'sub': sub, 'email': 'f@t.io', 'name': 'Fresh'})}.sig';
}

void main() {
  setUpAll(() {
    registerFallbackValue(TokenRequest('client', 'redirect', issuer: 'https://issuer.test'));
  });

  late MockAppAuth appAuth;
  late MockSecureStorage storage;
  late Map<String, String> store;
  late List<AuthUser?> emitted;

  setUp(() {
    store = {};
    emitted = [];
    appAuth = MockAppAuth();
    storage = MockSecureStorage();
    when(
      () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
    ).thenAnswer((inv) async {
      store[inv.namedArguments[#key] as String] = inv.namedArguments[#value] as String;
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((inv) async {
      store.remove(inv.namedArguments[#key] as String);
    });
  });

  ZitadelAuthRepository build() {
    final repo = ZitadelAuthRepository(appAuth: appAuth, storage: storage);
    repo.authStateChanges.listen(emitted.add);
    return repo;
  }

  void stubReadFromMap() {
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((inv) async => store[inv.namedArguments[#key] as String]);
  }

  testWidgets('keychain read THROWS -> emits null, deletes nothing', (tester) async {
    when(() => storage.read(key: any(named: 'key'))).thenThrow(Exception('keychain locked'));

    build();
    await tester.pump(Duration.zero);

    expect(emitted, [null]);
    verifyNever(() => storage.delete(key: any(named: 'key')));
  });

  testWidgets('keychain read NEVER completes -> emits null after 5s, deletes nothing', (
    tester,
  ) async {
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) => Completer<String?>().future);

    build();
    await tester.pump(const Duration(seconds: 4));
    expect(emitted, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    expect(emitted, [null]);
    verifyNever(() => storage.delete(key: any(named: 'key')));
  });

  group('refreshSession single-flight vs a hung native call', () {
    setUp(() {
      stubReadFromMap();
      store[_refreshTokenKey] = 'rt-1';
    });

    ZitadelAuthRepository noRestore() =>
        ZitadelAuthRepository(appAuth: appAuth, storage: storage, restore: false);

    testWidgets('times out at 12s as NetworkError, clears the slot, next call is a fresh exchange', (
      tester,
    ) async {
      var calls = 0;
      when(() => appAuth.token(any())).thenAnswer((_) {
        calls++;
        return Completer<TokenResponse>().future;
      });
      final repo = noRestore();

      final results = <({AuthUser? user, AuthFailure? failure})>[];
      unawaited(repo.refreshSession().then(results.add));
      await tester.pump(const Duration(seconds: 11));
      expect(results, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      expect(results.single.failure, isA<NetworkError>());
      expect(store[_refreshTokenKey], 'rt-1');
      expect(calls, 1);

      // The slot is free: a second call must start a NEW exchange, not reuse the hung one.
      unawaited(repo.refreshSession().then(results.add));
      await tester.pump(Duration.zero);
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 13));
      expect(results, hasLength(2));
    });

    testWidgets('concurrent callers during the window still share ONE exchange', (tester) async {
      var calls = 0;
      when(() => appAuth.token(any())).thenAnswer((_) {
        calls++;
        return Completer<TokenResponse>().future;
      });
      final repo = noRestore();

      final results = <({AuthUser? user, AuthFailure? failure})>[];
      unawaited(repo.refreshSession().then(results.add));
      unawaited(repo.refreshSession().then(results.add));
      await tester.pump(const Duration(seconds: 5));
      unawaited(repo.refreshSession().then(results.add));
      await tester.pump(const Duration(seconds: 8));

      expect(calls, 1);
      expect(results, hasLength(3));
      expect(results.every((r) => r.failure is NetworkError), isTrue);
    });
  });

  group('native refresh never completes', () {
    setUp(() {
      stubReadFromMap();
      store[_refreshTokenKey] = 'rt-1';
      when(() => appAuth.token(any())).thenAnswer((_) => Completer<TokenResponse>().future);
    });

    testWidgets('with cached identity -> falls back to it after ~12s, token kept', (tester) async {
      store[_cachedIdentityKey] = jsonEncode({
        'id': 'u1',
        'email': 'tech@tasktap.io',
        'displayName': 'Tecnico',
      });

      final repo = build();
      await tester.pump(const Duration(seconds: 11));
      expect(emitted, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      expect(emitted, hasLength(1));
      expect(emitted.single?.id, 'u1');
      expect(repo.currentUser?.refreshToken, 'rt-1');
      expect(store[_refreshTokenKey], 'rt-1');
    });

    testWidgets('without cached identity -> emits null after ~12s', (tester) async {
      build();
      await tester.pump(const Duration(seconds: 13));

      expect(emitted, [null]);
    });

    testWidgets('a LATE successful native result after the timeout is discarded', (tester) async {
      store[_cachedIdentityKey] = jsonEncode({'id': 'u1', 'email': 'e', 'displayName': 'T'});
      final late = Completer<TokenResponse>();
      when(() => appAuth.token(any())).thenAnswer((_) => late.future);

      build();
      await tester.pump(const Duration(seconds: 13));
      expect(emitted.map((u) => u?.id), ['u1']);

      late.complete(
        TokenResponse(
          'at-new',
          'rt-new',
          DateTime.now().add(const Duration(hours: 1)),
          _fakeIdToken(),
          'Bearer',
          null,
          null,
        ),
      );
      await tester.pump(Duration.zero);

      // The native call is now abandoned at the timeout (single-flight slot freed), so its late
      // result is discarded: no emit, no persist. The reconnect watcher / 401 path retries.
      expect(emitted.map((u) => u?.id), ['u1']);
      expect(store[_refreshTokenKey], 'rt-1');
    });
  });
}
