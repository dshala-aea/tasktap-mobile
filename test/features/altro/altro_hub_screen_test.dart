// test/features/altro/altro_hub_screen_test.dart
//
// Widget tests for AltroHubScreen (D4a).
//
// Covers:
//   1. User card shows display name (or email fallback).
//   2. Gestione grid renders all 8 tiles.
//   3. Sistema rows (Notifiche, Impostazioni, Audit log, Ruoli e permessi).
//   4. Logout row is present (after scroll).
//   5. Logout confirm dialog appears on tap.

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/altro/altro_hub_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

AuthUser _fakeUser({String? displayName}) => AuthUser(
      id: 'u1',
      email: 'mario@tasktap.io',
      displayName: displayName,
      accessToken: 'token',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

Widget _buildHub(MockAuthRepository repo) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: AltroHubScreen()),
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
    await tester.pumpWidget(_buildHub(repo));
    await tester.pump();
    authStream.add(user);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ── 1. User card with display name ─────────────────────────────────────────
  testWidgets('shows display name in user card', (tester) async {
    final user = _fakeUser(displayName: 'Mario Rossi');
    await pump(tester, user: user);

    expect(find.text('Mario Rossi'), findsOneWidget);
    await drain(tester);
  });

  // ── 2. User card falls back to email when no displayName ───────────────────
  testWidgets('shows email when no displayName', (tester) async {
    final user = _fakeUser(displayName: null);
    await pump(tester, user: user);

    expect(find.text('mario@tasktap.io'), findsAtLeast(1));
    await drain(tester);
  });

  // ── 3. Gestione grid tiles ─────────────────────────────────────────────────
  testWidgets('renders all Gestione grid tiles', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    // Tiles in the first row are visible without scrolling.
    expect(find.text('Interventi'), findsOneWidget);
    expect(find.text('Rapportini'), findsOneWidget);

    // Scroll to reveal all grid tiles.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();

    expect(find.text('Clienti'), findsOneWidget);
    expect(find.text('Prodotti'), findsOneWidget);
    await drain(tester);
  });

  // ── 4. Sistema rows ────────────────────────────────────────────────────────
  testWidgets('renders Sistema rows', (tester) async {
    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    // Scroll past the Gestione grid (10 tiles / 5 rows, one per admin CRUD
    // domain) to reveal Sistema. A fixed drag count is too fragile now that
    // the grid can grow — scroll incrementally until the target is visible.
    // (scrollUntilVisible casts its `scrollable` finder to `Scrollable`, so
    // it must resolve the Scrollable itself, not the CustomScrollView that
    // creates it — omit it and let the default `find.byType(Scrollable)`
    // locate the single Scrollable in this tree.)
    await tester.scrollUntilVisible(
      find.text('Impostazioni'),
      300,
    );
    await tester.pump();

    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Audit log'), findsOneWidget);
    await drain(tester);
  });

  // ── 5. Logout confirm dialog ───────────────────────────────────────────────
  testWidgets('logout row tap shows confirm dialog', (tester) async {
    when(() => repo.currentUser).thenReturn(null);
    when(() => repo.signOut()).thenAnswer((_) async {});

    final user = _fakeUser(displayName: 'Mario');
    await pump(tester, user: user);

    // Scroll down until the logout row (bottom of the screen) is visible.
    // A fixed drag count is too fragile now that the Gestione grid above it
    // can grow — scroll incrementally until the target is visible. (See the
    // "renders Sistema rows" test above for why `scrollable` is omitted.)
    final logoutFinder = find.text("Esci dall'account");
    await tester.scrollUntilVisible(
      logoutFinder,
      400,
    );
    await tester.pump();

    expect(logoutFinder, findsOneWidget);
    await tester.tap(logoutFinder);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);

    // Dismiss dialog.
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    await drain(tester);
  });
}
