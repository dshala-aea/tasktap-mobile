// dart format width=100
// test/features/altro/logout_action_test.dart
//
// The regression this file exists for: `confirmLogout` is the only widget path that may end a
// session, because ending it wipes Drift. The Altro hub and the Profilo screen each used to run a
// private generic "Sei sicuro?" and then call `signOut()` directly — a logout with unsent work
// that never named the count and never offered "Invia ora".
//
// The decision logic itself is covered by `logout_flow_test.dart`; this covers the asking and,
// above all, that both screens reach it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/auth/session_ender.dart';
import 'package:tasktap_mobile/data/auth/session_recovery_providers.dart';
import 'package:tasktap_mobile/data/auth/unsent_work_counter.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/altro/altro_hub_screen.dart';
import 'package:tasktap_mobile/features/altro/logout_action.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/screens/profilo/profilo_screen.dart';

class _MockUnsentWorkCounter extends Mock implements UnsentWorkCounter {}

class _MockUnsentWorkFlusher extends Mock implements UnsentWorkFlusher {}

class _MockSessionEnder extends Mock implements SessionEnder {}

class _MockAuthRepository extends Mock implements IAuthRepository {}

AuthUser _fakeUser() => AuthUser(
  id: 'u1',
  email: 'mario@tasktap.io',
  displayName: 'Mario Rossi',
  accessToken: 'tok',
  refreshToken: 'ref',
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
);

void main() {
  late _MockUnsentWorkCounter counter;
  late _MockUnsentWorkFlusher flusher;
  late _MockSessionEnder ender;
  late _MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    counter = _MockUnsentWorkCounter();
    flusher = _MockUnsentWorkFlusher();
    ender = _MockSessionEnder();
    repo = _MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => flusher.flush()).thenAnswer((_) async {});
    when(() => ender.end()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await authStream.close();
  });

  void givenUnsent(int count) {
    when(() => counter.count()).thenAnswer(
      (_) async => UnsentWorkBreakdown(pendingTickets: count),
    );
  }

  List<Override> overrides() => [
    unsentWorkCounterProvider.overrideWithValue(counter),
    unsentWorkFlusherProvider.overrideWithValue(flusher),
    sessionEnderProvider.overrideWithValue(ender),
    authRepositoryProvider.overrideWithValue(repo),
    // The Altro hub gates its tiles on the tenant's modules; nothing cached = the always-on
    // tiles only, and no real repository build.
    cachedEntitlementProvider.overrideWith((ref) async => null),
  ];

  /// A bare host for the action itself — the two screens below are the real call sites, but this
  /// keeps the dialog assertions independent of either screen's layout.
  Widget host() => ProviderScope(
    overrides: overrides(),
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => confirmLogout(context, ref),
            child: const Text('Esci dall\'account'),
          ),
        ),
      ),
    ),
  );

  testWidgets('unsent work is counted and named before any logout', (tester) async {
    givenUnsent(3);
    await tester.pumpWidget(host());

    await tester.tap(find.text('Esci dall\'account'));
    await tester.pumpAndSettle();

    expect(find.text('Elementi non inviati'), findsOneWidget);
    expect(find.textContaining('3 elementi non inviati'), findsOneWidget);
    // The generic confirmation is only for a device with nothing to lose.
    expect(find.textContaining('Sei sicuro di voler uscire'), findsNothing);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    verifyNever(() => ender.end());
  });

  testWidgets('"Esci comunque" is the only way to log out with work still on the device', (
    tester,
  ) async {
    givenUnsent(3);
    await tester.pumpWidget(host());

    await tester.tap(find.text('Esci dall\'account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci comunque'));
    await tester.pumpAndSettle();

    verify(() => ender.end()).called(1);
  });

  testWidgets('a device with nothing unsent still gets the ordinary confirmation', (tester) async {
    givenUnsent(0);
    await tester.pumpWidget(host());

    await tester.tap(find.text('Esci dall\'account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sei sicuro di voler uscire'), findsOneWidget);
    expect(find.text('Elementi non inviati'), findsNothing);

    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    verify(() => ender.end()).called(1);
  });

  testWidgets('"Invia ora" that cannot empty the queue stays signed in and says how much is left', (
    tester,
  ) async {
    givenUnsent(3);
    await tester.pumpWidget(host());

    await tester.tap(find.text('Esci dall\'account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invia ora'));
    await tester.pumpAndSettle();

    verify(() => flusher.flush()).called(1);
    verifyNever(() => ender.end());
    expect(find.textContaining('3 elementi non sono stati inviati'), findsOneWidget);
  });

  // ── The two call sites that used to bypass the count ─────────────────────────

  Future<void> pumpAuthed(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: MaterialApp(home: screen)),
    );
    await tester.pump();
    authStream.add(_fakeUser());
    await tester.pumpAndSettle();
  }

  testWidgets('the Altro hub logout row names the unsent count', (tester) async {
    givenUnsent(2);
    await pumpAuthed(tester, const AltroHubScreen());

    await tester.tap(find.text('Esci dall\'account'));
    await tester.pumpAndSettle();

    expect(find.text('Elementi non inviati'), findsOneWidget);
    expect(find.textContaining('2 elementi non inviati'), findsOneWidget);
    verifyNever(() => ender.end());
  });

  testWidgets('the Profilo screen logout button names the unsent count', (tester) async {
    givenUnsent(2);
    await pumpAuthed(tester, const ProfiloScreen());

    await tester.tap(find.text('Disconnetti'));
    await tester.pumpAndSettle();

    expect(find.text('Elementi non inviati'), findsOneWidget);
    expect(find.textContaining('2 elementi non inviati'), findsOneWidget);
    verifyNever(() => ender.end());
  });
}
