import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/security/biometric_lock.dart';
import 'package:tasktap_mobile/core/security/biometric_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _Bio implements IBiometricService {
  _Bio({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return succeeds;
  }
}

class _Store implements LockActivityStore {
  DateTime? at;

  @override
  Future<DateTime?> lastActiveAt() async => at;

  @override
  Future<void> markActive(DateTime when) async => at = when;
}

final _user = AuthUser(
  id: 'u1',
  email: 'a@b.it',
  accessToken: 't',
  refreshToken: 'r',
  expiresAt: DateTime.utc(2100),
);

class _Auth implements IAuthRepository {
  _Auth({this.signedIn = true, this.refreshThrows = false});

  final bool signedIn;
  final bool refreshThrows;
  int refreshes = 0;

  @override
  Future<({AuthFailure? failure, AuthUser? user})> refreshSession() async {
    refreshes++;
    if (refreshThrows) throw Exception('offline');
    return (user: null, failure: null);
  }

  @override
  AuthUser? get currentUser => signedIn ? _user : null;

  @override
  Stream<AuthUser?> get authStateChanges =>
      Stream.value(signedIn ? _user : null);

  @override
  Future<({AuthFailure? failure, AuthUser? user})> signIn({
    String? loginHint,
  }) async => (user: null, failure: null);

  @override
  Future<void> signOut() async {}
}

/// A session restore that lands after the cold start gave up waiting.
class _LateAuth implements IAuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? user;

  void restore() {
    user = _user;
    _controller.add(_user);
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<({AuthFailure? failure, AuthUser? user})> refreshSession() async =>
      (user: null, failure: null);

  @override
  Future<({AuthFailure? failure, AuthUser? user})> signIn({String? loginHint}) async =>
      (user: null, failure: null);

  @override
  Future<void> signOut() async {}
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

void main() {
  late DateTime now;
  late _Store store;

  setUp(() {
    now = DateTime.utc(2026, 11, 25, 10);
    store = _Store();
  });

  Future<void> pump(
    WidgetTester tester, {
    required _Bio bio,
    _Auth? auth,
    bool atBuilder = false,
    IAuthRepository? repo,
    Duration? sessionWait,
  }) async {
    Widget lock(Widget child) => BiometricLock(
      enabled: true,
      sessionWait: sessionWait ?? const Duration(seconds: 30),
      store: store,
      clock: () => now,
      child: child,
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          biometricServiceProvider.overrideWithValue(bio),
          authRepositoryProvider.overrideWithValue(repo ?? auth ?? _Auth()),
        ],
        child: atBuilder
            // Above the Navigator, exactly like main.dart: no Overlay, no Scaffold, no Material.
            ? MaterialApp(
                builder: (context, child) => lock(child!),
                home: const Scaffold(body: Text('dati riservati')),
              )
            : MaterialApp(
                home: lock(const Scaffold(body: Text('dati riservati'))),
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<bool> swallowsBack() => WidgetsBinding.instance.handlePopRoute();

  testWidgets('cold start with no recent activity prompts and unlocks', (
    tester,
  ) async {
    final bio = _Bio();
    await pump(tester, bio: bio);
    expect(bio.prompts, 1);
    expect(find.text('Sblocca'), findsNothing);
    expect(store.at, now);
  });

  testWidgets('failed or cancelled prompt stays locked and offers Sblocca', (
    tester,
  ) async {
    final bio = _Bio(succeeds: false);
    await pump(tester, bio: bio);
    expect(find.text('Sblocca'), findsOneWidget);
    expect(await swallowsBack(), isTrue);

    bio.succeeds = true;
    await tester.tap(find.text('Sblocca'));
    await tester.pumpAndSettle();
    expect(find.text('Sblocca'), findsNothing);
    expect(await swallowsBack(), isFalse);
  });

  testWidgets('unavailable device never locks and never prompts', (
    tester,
  ) async {
    final bio = _Bio(available: false);
    await pump(tester, bio: bio);
    expect(bio.prompts, 0);
    expect(find.text('Sblocca'), findsNothing);
    expect(find.text('TaskTap è bloccato'), findsNothing);
    expect(await swallowsBack(), isFalse);

    // Nor on the way back from the background.
    await _lifecycle(tester, AppLifecycleState.paused);
    now = now.add(kBiometricGrace * 2);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bio.prompts, 0);
    expect(find.text('Sblocca'), findsNothing);
  });

  testWidgets('no session never locks (login screen, after logout)', (
    tester,
  ) async {
    final bio = _Bio();
    await pump(tester, bio: bio, auth: _Auth(signedIn: false));
    expect(bio.prompts, 0);
    expect(find.text('dati riservati'), findsOneWidget);
    expect(find.text('Sblocca'), findsNothing);
    expect(await swallowsBack(), isFalse);
  });

  testWidgets('resume within the grace window does not lock', (tester) async {
    final bio = _Bio();
    await pump(tester, bio: bio);
    expect(bio.prompts, 1);

    await _lifecycle(tester, AppLifecycleState.paused);
    now = now.add(kBiometricGrace - const Duration(seconds: 1));
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bio.prompts, 1);
    expect(find.text('Sblocca'), findsNothing);
  });

  testWidgets('resume after the grace window locks and prompts', (
    tester,
  ) async {
    final bio = _Bio();
    await pump(tester, bio: bio);

    bio.succeeds = false;
    await _lifecycle(tester, AppLifecycleState.paused);
    now = now.add(kBiometricGrace + const Duration(seconds: 1));
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bio.prompts, 2);
    expect(find.text('Sblocca'), findsOneWidget);
    expect(await swallowsBack(), isTrue);
  });

  testWidgets('refreshSession runs on unlock; its failure does not re-lock', (
    tester,
  ) async {
    final auth = _Auth(refreshThrows: true);
    await pump(tester, bio: _Bio(), auth: auth);
    expect(auth.refreshes, 1);
    expect(find.text('Sblocca'), findsNothing);
  });

  testWidgets('mounted above the Navigator (MaterialApp builder) renders', (
    tester,
  ) async {
    final bio = _Bio(succeeds: false);
    await pump(tester, bio: bio, atBuilder: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Sblocca'), findsOneWidget);
    expect(find.text('TaskTap è bloccato'), findsOneWidget);

    // The app underneath stays mounted.
    expect(find.text('dati riservati', skipOffstage: false), findsOneWidget);

    bio.succeeds = true;
    await tester.tap(find.text('Sblocca'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sblocca'), findsNothing);
  });

  testWidgets('a session restore that lands AFTER the cold-start wait still arms the lock', (
    tester,
  ) async {
    final bio = _Bio(succeeds: false);
    final lateAuth = _LateAuth();
    addTearDown(lateAuth._controller.close);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          biometricServiceProvider.overrideWithValue(bio),
          authRepositoryProvider.overrideWithValue(lateAuth),
        ],
        child: MaterialApp(
          home: BiometricLock(
            enabled: true,
            store: store,
            clock: () => now,
            sessionWait: const Duration(milliseconds: 50),
            child: const Scaffold(body: Text('dati riservati')),
          ),
        ),
      ),
    );
    // The wait runs out with no session: nothing to protect yet, the cover lifts.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(bio.prompts, 0);
    expect(find.text('Sblocca'), findsNothing);

    // The restore finally completes: the decision is re-run and the lock arms.
    lateAuth.restore();
    await tester.pumpAndSettle();
    expect(bio.prompts, 1);
    expect(find.text('Sblocca'), findsOneWidget);
  });
}
