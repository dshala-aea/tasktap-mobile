// test/features/altro/notifiche_screen_test.dart
//
// Widget tests for NotificheScreen (D4a).
//
// Covers:
//   1. Shows EmptyState when notificheProvider returns [].
//   2. Filter chips Tutte / Non lette are rendered.
//   3. Notification rows appear when provider has items.
//   4. "Segna tutte" action appears when there are unread items.
//   5. Mark-all-read clears the unread dot.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/altro/notifiche_provider.dart';
import 'package:tasktap_mobile/features/altro/notifiche_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppNotifica _fakeNotifica({String id = 'n1', bool letta = false}) =>
    AppNotifica(
      id: id,
      titolo: 'Nuovo intervento',
      corpo: 'Ti è stato assegnato un intervento.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      letta: letta,
    );

/// Builds a [NotificheScreen] backed by a real [NotificheNotifier] over an
/// in-memory Drift DB seeded with [notifiche].
///
/// [NotificheNotifier] always loads its initial state from Drift in its
/// constructor (`_loadFromCache`, offline-first — see notifiche_provider.dart).
/// That load is async and cannot be intercepted from outside the library
/// (it's a private method), so a subclass that tries to set `state`
/// straight after `super(...)` just races it: `_loadFromCache()` resolves
/// moments later and overwrites the seeded state with whatever (nothing)
/// is actually in the fresh in-memory DB. Seeding the DB itself — rather
/// than trying to stub post-construction state — sidesteps the race
/// entirely: whichever write "wins", the loaded data matches.
Future<Widget> _buildScreen({List<AppNotifica> notifiche = const []}) async {
  final db = AppDatabase(NativeDatabase.memory());
  for (final n in notifiche) {
    await db.into(db.appNotifications).insertOnConflictUpdate(
          AppNotificationsCompanion.insert(
            id: n.id,
            tenantId: 'test-tenant',
            createdAt: n.timestamp,
            userId: 'test-user',
            title: n.titolo,
            message: n.corpo,
            type: 'TicketAssigned',
            deliveryType: 'InApp',
            isRead: Value(n.letta),
          ),
        );
  }

  return ProviderScope(
    overrides: [
      notificheProvider.overrideWith((ref) => NotificheNotifier(db, Dio())),
    ],
    child: const MaterialApp(home: NotificheScreen()),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ── 1. Empty state ─────────────────────────────────────────────────────────
  testWidgets('shows EmptyState when no notifications', (tester) async {
    await tester.pumpWidget(await _buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Nessuna notifica'), findsOneWidget);
    await drain(tester);
  });

  // ── 2. Filter chips ────────────────────────────────────────────────────────
  testWidgets('renders filter chips Tutte and Non lette', (tester) async {
    await tester.pumpWidget(await _buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Tutte'), findsOneWidget);
    expect(find.text('Non lette'), findsOneWidget);
    await drain(tester);
  });

  // ── 3. Notification rows ───────────────────────────────────────────────────
  testWidgets('renders notification rows when provider has items', (tester) async {
    final notifiche = [
      _fakeNotifica(id: 'n1'),
      _fakeNotifica(id: 'n2', letta: true),
    ];

    await tester.pumpWidget(await _buildScreen(notifiche: notifiche));
    await tester.pumpAndSettle();

    // Both notifications have the same title in our fake data.
    expect(find.text('Nuovo intervento'), findsNWidgets(2));
    await drain(tester);
  });

  // ── 4. Segna tutte action ──────────────────────────────────────────────────
  testWidgets('Segna tutte action visible when unread exist', (tester) async {
    final notifiche = [_fakeNotifica(id: 'n1', letta: false)];

    await tester.pumpWidget(await _buildScreen(notifiche: notifiche));
    await tester.pumpAndSettle();

    expect(find.text('Segna tutte'), findsOneWidget);
    await drain(tester);
  });

  // ── 5. Segna tutte hides after tap ────────────────────────────────────────
  testWidgets('Segna tutte tap marks all as read and hides button', (tester) async {
    final notifiche = [_fakeNotifica(id: 'n1', letta: false)];

    await tester.pumpWidget(await _buildScreen(notifiche: notifiche));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Segna tutte'));
    await tester.pumpAndSettle();

    // After marking all read, no unread → button hidden.
    expect(find.text('Segna tutte'), findsNothing);
    await drain(tester);
  });

  // ── 6. Non lette filter shows only unread ─────────────────────────────────
  testWidgets('Non lette chip filters to unread only', (tester) async {
    final notifiche = [
      _fakeNotifica(id: 'n1', letta: false),
      _fakeNotifica(id: 'n2', letta: true),
    ];

    await tester.pumpWidget(await _buildScreen(notifiche: notifiche));
    await tester.pumpAndSettle();

    // Tap "Non lette" chip.
    await tester.tap(find.text('Non lette'));
    await tester.pumpAndSettle();

    // Only 1 unread notification shown.
    expect(find.text('Nuovo intervento'), findsOneWidget);
    await drain(tester);
  });
}
