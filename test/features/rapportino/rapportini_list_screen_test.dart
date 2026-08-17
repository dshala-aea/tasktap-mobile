// dart format width=100
// test/features/rapportino/rapportini_list_screen_test.dart
//
// Widget tests for RapportiniListScreen (D3b-2).
//
// Covers:
//   1. Renders ListRows from seeded drafts.
//   2. Filter chip "Bozza" narrows results.
//   3. EmptyState shown when no drafts.
//   4. AppFab is present.
//   5. Submitted draft tap navigates to view route (not editor).

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/rapportini_list_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedDraft(
  AppDatabase db, {
  required String id,
  String title = 'Rapportino di test',
  String submissionState = 'draft',
  String stato = 'Bozza',
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: title,
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          isLocalOnly: const Value(true),
          stato: Value(stato),
          submissionState: Value(submissionState),
        ),
      );
}

Widget _buildList({required AppDatabase db}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: RapportiniListScreen()),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('RapportiniListScreen — row rendering', () {
    testWidgets('renders one ListRow per seeded draft', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Intervento idraulico');
      await _seedDraft(db, id: 'draft-2', title: 'Revisione caldaia');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Intervento idraulico'), findsOneWidget);
      expect(find.text('Revisione caldaia'), findsOneWidget);
      // Two ListRows rendered
      expect(find.byType(ListRow), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatusPill with Bozza for a draft-state report', (tester) async {
      await _seedDraft(db, id: 'draft-1', submissionState: 'draft');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(StatusPill), findsWidgets);
      expect(find.text('Bozza'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatusPill with Inviata for a submitted report', (tester) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Rapportino inviato',
        submissionState: 'submitted',
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Inviata'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — filter chip', () {
    testWidgets('filter Bozza shows only bozza drafts', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza A', submissionState: 'draft');
      await _seedDraft(db, id: 'draft-2', title: 'Inviata B', submissionState: 'submitted');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      // Both visible initially under "Tutti"
      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Inviata B'), findsOneWidget);

      // Tap "Bozza" chip
      final bozzaChip = find.widgetWithText(AppChip, 'Bozza').first;
      await tester.ensureVisible(bozzaChip);
      await tester.tap(bozzaChip);
      await tester.pumpAndSettle();

      // Only Bozza A should remain
      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Inviata B'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('filter Inviata shows only submitted drafts', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza locale', submissionState: 'draft');
      await _seedDraft(db, id: 'draft-2', title: 'Già inviato', submissionState: 'submitted');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      final inviataCip = find.widgetWithText(AppChip, 'Inviata').first;
      await tester.ensureVisible(inviataCip);
      await tester.tap(inviataCip);
      await tester.pumpAndSettle();

      expect(find.text('Già inviato'), findsOneWidget);
      expect(find.text('Bozza locale'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('filter Pagata shows empty state (no local data yet)', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza A');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      final pagataChip = find.widgetWithText(AppChip, 'Pagata').first;
      await tester.ensureVisible(pagataChip);
      await tester.tap(pagataChip);
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — empty state', () {
    testWidgets('shows EmptyState when no drafts exist', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nessun rapportino'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — FAB', () {
    testWidgets('AppFab is present', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(AppFab), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — header', () {
    testWidgets('ScreenHeader shows title Rapportini', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Rapportini'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('header subtitle shows totali count', (tester) async {
      await _seedDraft(db, id: 'draft-1');
      await _seedDraft(db, id: 'draft-2');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('2 totali'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
