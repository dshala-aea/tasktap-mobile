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

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/altro/notifiche_provider.dart';
import 'package:tasktap_mobile/features/altro/notifiche_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Fake notifier that can be seeded with test data, bypassing DB initialization.
class _FakeNotificheNotifier extends NotificheNotifier {
  _FakeNotificheNotifier(List<AppNotifica> initial)
      : super(AppDatabase(NativeDatabase.memory()), Dio()) {
    // Override state directly, skipping _loadFromCache().
    state = initial;
  }
}

Widget _buildScreen({List<AppNotifica> notifiche = const []}) {
  return ProviderScope(
    overrides: [
      notificheProvider.overrideWith(
        (ref) => _FakeNotificheNotifier(notifiche),
      ),
    ],
    child: const MaterialApp(home: NotificheScreen()),
  );
}

AppNotifica _fakeNotifica({String id = 'n1', bool letta = false}) =>
    AppNotifica(
      id: id,
      titolo: 'Nuovo intervento',
      corpo: 'Ti è stato assegnato un intervento.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      letta: letta,
    );

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
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

    expect(find.text('Nessuna notifica'), findsOneWidget);
    await drain(tester);
  });

  // ── 2. Filter chips ────────────────────────────────────────────────────────
  testWidgets('renders filter chips Tutte and Non lette', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pump();

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

    await tester.pumpWidget(_buildScreen(notifiche: notifiche));
    await tester.pump();

    // Both notifications have the same title in our fake data.
    expect(find.text('Nuovo intervento'), findsNWidgets(2));
    await drain(tester);
  });

  // ── 4. Segna tutte action ──────────────────────────────────────────────────
  testWidgets('Segna tutte action visible when unread exist', (tester) async {
    final notifiche = [_fakeNotifica(id: 'n1', letta: false)];

    await tester.pumpWidget(_buildScreen(notifiche: notifiche));
    await tester.pump();

    expect(find.text('Segna tutte'), findsOneWidget);
    await drain(tester);
  });

  // ── 5. Segna tutte hides after tap ────────────────────────────────────────
  testWidgets('Segna tutte tap marks all as read and hides button', (tester) async {
    final notifiche = [_fakeNotifica(id: 'n1', letta: false)];

    await tester.pumpWidget(_buildScreen(notifiche: notifiche));
    await tester.pump();

    await tester.tap(find.text('Segna tutte'));
    await tester.pump();

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

    await tester.pumpWidget(_buildScreen(notifiche: notifiche));
    await tester.pump();

    // Tap "Non lette" chip.
    await tester.tap(find.text('Non lette'));
    await tester.pump();

    // Only 1 unread notification shown.
    expect(find.text('Nuovo intervento'), findsOneWidget);
    await drain(tester);
  });
}
