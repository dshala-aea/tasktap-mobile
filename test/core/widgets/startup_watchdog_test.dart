// StartupWatchdog: last-resort visible fallback when kiosk/auth loading never finishes (App
// Store rejection: stuck on the splash screen forever).
//
// KioskModeNotifier now bounds its own reads (5s), so a stuck kiosk can no longer be produced
// through the store; a fake notifier that re-enters `loading` stands in for "something the
// per-call timeouts did not cover".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/kiosk/kiosk_lock_service.dart';
import 'package:tasktap_mobile/core/widgets/startup_watchdog.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_api_client.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_credentials_store.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/providers/kiosk_providers.dart';

class MockStore extends Mock implements KioskCredentialsStore {}

class MockApi extends Mock implements KioskApiClient {}

class MockLock extends Mock implements IKioskLockService {}

/// Settles immediately (no credentials), then — when [stuck] — flips back to `loading`.
class _FakeKiosk extends KioskModeNotifier {
  _FakeKiosk(MockStore store, {required bool stuck})
    : super(store, MockApi(), MockLock()) {
    if (stuck) {
      Future<void>.delayed(const Duration(milliseconds: 1), () {
        if (mounted) state = const KioskModeState();
      });
    }
  }

  void finish() => state = const KioskModeState(loading: false);
}

void main() {
  late MockStore store;
  late StreamController<AuthUser?> authController;
  late _FakeKiosk kiosk;
  late int kioskBuilds;
  late int authBuilds;
  late bool kioskStuck;
  late bool authStuck;

  setUp(() {
    store = MockStore();
    when(() => store.read()).thenAnswer((_) async => null);
    kioskBuilds = 0;
    authBuilds = 0;
    kioskStuck = true;
    authStuck = true;
    authController = StreamController<AuthUser?>.broadcast();
  });

  tearDown(() => authController.close());

  Widget app() => ProviderScope(
    overrides: [
      kioskModeProvider.overrideWith((ref) {
        kioskBuilds++;
        return kiosk = _FakeKiosk(store, stuck: kioskStuck);
      }),
      authStateProvider.overrideWith((ref) {
        authBuilds++;
        return authStuck ? authController.stream : Stream<AuthUser?>.value(null);
      }),
    ],
    child: const MaterialApp(
      home: StartupWatchdog(child: Text('contenuto app')),
    ),
  );

  final failureTitle = find.text('Impossibile avviare TaskTap');

  testWidgets('shows the fallback after 10s of loading, not before', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 9));
    expect(failureTitle, findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(failureTitle, findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('never shows when loading finishes quickly, and leaves no timer behind', (
    tester,
  ) async {
    kioskStuck = false;
    authStuck = false;

    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 30));

    expect(failureTitle, findsNothing);
    expect(find.text('contenuto app'), findsOneWidget);
    // testWidgets itself fails the test if a Timer is still pending at the end.
  });

  testWidgets('auth alone still loading is enough to trigger it', (tester) async {
    kioskStuck = false;

    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 11));

    expect(failureTitle, findsOneWidget);
  });

  testWidgets('kiosk alone still loading is enough to trigger it', (tester) async {
    authStuck = false;

    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 11));

    expect(failureTitle, findsOneWidget);
  });

  testWidgets('Riprova invalidates kiosk + auth providers and the screen goes away', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 11));
    final kioskBefore = kioskBuilds;
    final authBefore = authBuilds;

    // The retry will succeed this time.
    kioskStuck = false;
    authStuck = false;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(kioskBuilds, greaterThan(kioskBefore));
    expect(authBuilds, greaterThan(authBefore));
    expect(failureTitle, findsNothing);
    expect(find.text('contenuto app'), findsOneWidget);
  });

  testWidgets('disappears by itself when loading finishes late', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 11));
    expect(failureTitle, findsOneWidget);

    // Auth settles but kiosk is still stuck -> still shown.
    authController.add(null);
    await tester.pump();
    expect(failureTitle, findsOneWidget);

    // Kiosk settles too -> gone.
    kiosk.finish();
    await tester.pump();
    expect(failureTitle, findsNothing);
    expect(find.text('contenuto app'), findsOneWidget);
  });
}
