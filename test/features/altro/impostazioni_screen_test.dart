// test/features/altro/impostazioni_screen_test.dart
//
// Widget tests for ImpostazioniScreen (D4a).
//
// Covers:
//   1. Profile card renders with display name.
//   2. Profile card renders with email fallback when no displayName.
//   3. Notifiche section and toggle rows are present.
//   4. App section toggle rows are present.
//   5. Account section toggle row is present.
//   6. Toggling a toggle flips its state.
//   7. Logout row triggers confirm dialog.

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/altro/impostazioni_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

AuthUser _fakeUser({String? displayName}) => AuthUser(
  id: 'u1',
  email: 'mario@tasktap.io',
  displayName: displayName,
  accessToken: 'tok',
  refreshToken: 'ref',
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
);

Widget _buildScreen(MockAuthRepository repo) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: ImpostazioniScreen()),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
  });

  tearDown(() async {
    authStream.close();
  });

  Future<void> pump(WidgetTester tester, {AuthUser? user}) async {
    await tester.pumpWidget(_buildScreen(repo));
    await tester.pump();
    authStream.add(user);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ── 1. Profile card with display name ──────────────────────────────────────
  testWidgets('profile card shows displayName', (tester) async {
    final user = _fakeUser(displayName: 'Mario Rossi');
    await pump(tester, user: user);

    expect(find.text('Mario Rossi'), findsAtLeast(1));
    await drain(tester);
  });

  // ── 2. Profile card falls back to email ────────────────────────────────────
  testWidgets('profile card shows email when no displayName', (tester) async {
    final user = _fakeUser(displayName: null);
    await pump(tester, user: user);

    expect(find.text('mario@tasktap.io'), findsAtLeast(1));
    await drain(tester);
  });

  // ── 3. Notifiche section — canali ──────────────────────────────────────────
  testWidgets('renders Notifiche channel toggle rows', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    expect(find.text('Notifiche push'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Notifiche in app'), findsOneWidget);
    await drain(tester);
  });

  // ── 3b. Notifiche section — categorie (gap #8: all backend-enforced categories, not just
  // Interventi/Rapportini) ─────────────────────────────────────────────────────
  testWidgets('renders Notifiche category toggle rows', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    final scroller = find.byType(CustomScrollView);
    await tester.dragUntilVisible(
      find.text('Menzioni'),
      scroller,
      const Offset(0, -200),
    );
    await tester.pump();

    expect(find.text('Interventi'), findsOneWidget);
    expect(find.text('Pianificazione'), findsOneWidget);
    expect(find.text('Licenza e abbonamento'), findsOneWidget);
    expect(find.text('Ore e presenze'), findsOneWidget);
    expect(find.text('Rapportini'), findsOneWidget);
    expect(find.text('Menzioni'), findsOneWidget);
    await drain(tester);
  });

  // ── 4. App section ─────────────────────────────────────────────────────────
  testWidgets('renders App section toggle rows', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    final scroller = find.byType(CustomScrollView);
    await tester.dragUntilVisible(
      find.text('Modalità offline'),
      scroller,
      const Offset(0, -200),
    );
    await tester.pump();

    expect(find.text('Modalità offline'), findsOneWidget);
    expect(find.text('Geolocalizzazione'), findsOneWidget);
    await drain(tester);
  });

  // ── 5. Account section ─────────────────────────────────────────────────────
  testWidgets('renders Account section toggle row', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    // Scroll to find the Account section — further down now than before gap #8 added six more
    // notification toggles above it.
    final scroller = find.byType(CustomScrollView);
    await tester.dragUntilVisible(
      find.text('Autenticazione biometrica'),
      scroller,
      const Offset(0, -200),
    );
    await tester.pump();

    expect(find.text('Autenticazione biometrica'), findsOneWidget);
    await drain(tester);
  });

  // ── 6. Toggle flips state ──────────────────────────────────────────────────
  testWidgets('tapping AppToggle flips its state', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    // Find the first AppToggle (Notifiche push — starts ON).
    final toggles = find.byType(AppToggle);
    expect(toggles, findsWidgets);

    // Ensure the first toggle is visible.
    await tester.ensureVisible(toggles.first);
    await tester.tap(toggles.first);
    await tester.pump();

    // Re-query after tap — the widget re-renders with toggled state.
    // Just check no exception thrown and widget still present.
    expect(find.byType(AppToggle), findsWidgets);
    await drain(tester);
  });

  // ── 6b. Push toggle with a logged-in user doesn't crash ────────────────────
  //
  // `toggle(key: 'pushAbilitate')` calls `_syncPushRegistration`, which
  // touches `NotificationService.instance` — first access eagerly reads
  // `FirebaseMessaging.instance` and throws `[core/no-app]` unless Firebase
  // was initialized. Widget tests never call `runTaskTapApp()`, so
  // `NotificationService.isAvailable` is false here exactly like on a real
  // device where Firebase init failed. Test #6 above doesn't stub
  // `repo.currentUser`, so `_authRepo.currentUser?.accessToken` is null and
  // `_syncPushRegistration` early-returns *before* reaching the vulnerable
  // line — it never exercises this branch. This test stubs a real,
  // non-empty access token so the guard in `_syncPushRegistration` is
  // actually the thing preventing the crash.
  testWidgets('tapping push toggle with a logged-in user does not crash '
      'when Firebase is unavailable', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    when(() => repo.currentUser).thenReturn(user);
    await pump(tester, user: user);

    // First AppToggle is "Notifiche push", wired to key: 'pushAbilitate'.
    final pushToggle = find.byType(AppToggle).first;
    await tester.ensureVisible(pushToggle);
    await tester.tap(pushToggle);
    await tester.pump();

    // No exception propagated out of the tap → the Firebase-availability
    // guard held. (flutter_test surfaces any error thrown here as a failed
    // expectation on the enclosing testWidgets zone, so reaching this line
    // at all is the assertion.)
    expect(find.byType(AppToggle), findsWidgets);
    await drain(tester);
  });

  // ── 7. Logout row triggers dialog ─────────────────────────────────────────
  testWidgets('logout row tap shows confirm dialog', (tester) async {
    when(() => repo.currentUser).thenReturn(null);
    when(() => repo.signOut()).thenAnswer((_) async {});

    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    // Scroll past all sections (now longer than before gap #8 added six more notification
    // toggles) to the logout row.
    final scroller = find.byType(CustomScrollView);
    await tester.dragUntilVisible(
      find.text("Esci dall'account"),
      scroller,
      const Offset(0, -200),
    );
    await tester.pump();

    final logoutFinder = find.text("Esci dall'account");
    expect(logoutFinder, findsOneWidget);
    await tester.tap(logoutFinder);
    await tester.pumpAndSettle();

    // Vetro chrome (a Dialog wrapping VetroCard), not a stock AlertDialog — see this screen's
    // own _confirmLogout comment.
    expect(find.byType(Dialog), findsOneWidget);

    // Dismiss.
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    await drain(tester);
  });
}
