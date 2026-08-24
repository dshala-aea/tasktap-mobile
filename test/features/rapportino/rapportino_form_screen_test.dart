// dart format width=100
// test/features/rapportino/rapportino_form_screen_test.dart
//
// Widget tests for the rapportino checklist (Dettagli/Ore/Materiali/Riepilogo tiles + sheets).
//
// Covers:
//   1. All 4 tiles render.
//   2. Each tile opens its step's content in a bottom sheet.
//   3. Submit blocks when validation not satisfied.
//   4. Submit calls the queue when the draft is valid.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';
import 'package:tasktap_mobile/data/sync/submission_queue_watcher.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/rapportino_form_screen.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSubmissionQueue extends Mock implements SubmissionQueue {}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedDraft(AppDatabase db, String reportId) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: reportId,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 22),
          title: 'Test draft',
          insertedUserId: 'user-1',
          locationId: '',
          isLocalOnly: const Value(true),
          stato: const Value('Bozza'),
        ),
      );
}

Widget _buildForm({required AppDatabase db, required String reportId, SubmissionQueue? fakeQueue}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (fakeQueue != null) realSubmissionQueueProvider.overrideWithValue(fakeQueue),
    ],
    child: MaterialApp(home: RapportinoFormScreen(reportId: reportId)),
  );
}

Future<void> _openTile(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  const reportId = 'draft-test-1';

  group('RapportinoFormScreen — checklist tiles', () {
    testWidgets('renders all four tiles', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      expect(find.text('Dettagli'), findsOneWidget);
      expect(find.text('Ore'), findsOneWidget);
      expect(find.text('Materiali'), findsOneWidget);
      expect(find.text('Riepilogo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Dettagli tile opens a sheet with the titolo field', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      await _openTile(tester, 'Dettagli');

      // Field labels are static text above the field now, not Material floating labels inside
      // it, and a required marker is a coloured span — so this is rich text.
      expect(find.textContaining('TITOLO', findRichText: true), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Ore tile opens a sheet with staff-related content', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      await _openTile(tester, 'Ore');

      expect(find.text('Aggiungi tecnico'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Materiali tile opens a sheet with Aggiungi materiale button', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      await _openTile(tester, 'Materiali');

      expect(find.text('Aggiungi materiale'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Riepilogo tile opens a sheet with firma blocks + validation panel', (
      tester,
    ) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      await _openTile(tester, 'Riepilogo');

      // Invia button present but disabled (missing sigs)
      expect(find.text('Invia rapportino'), findsOneWidget);
      // Validation messages visible
      expect(find.text('Da completare prima dell\'invio:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoFormScreen — submit flow', () {
    testWidgets('Invia rapportino button is disabled when validation not satisfied', (
      tester,
    ) async {
      await _seedDraft(db, reportId);
      final fakeQueue = MockSubmissionQueue();
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId, fakeQueue: fakeQueue));
      await tester.pumpAndSettle();

      await _openTile(tester, 'Riepilogo');

      // Tap "Invia rapportino" — should be no-op because validation fails
      final inviaBtn = find.text('Invia rapportino');
      expect(inviaBtn, findsOneWidget);
      await tester.ensureVisible(inviaBtn);
      await tester.pumpAndSettle();
      await tester.tap(inviaBtn);
      await tester.pumpAndSettle();

      // Queue should NOT have been called
      verifyNever(() => fakeQueue.enqueue(any()));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('submit calls queue.enqueue + processAll when draft is valid', (tester) async {
      await _seedDraft(db, reportId);
      final fakeQueue = MockSubmissionQueue();
      when(() => fakeQueue.enqueue(any())).thenAnswer((_) async {});
      when(() => fakeQueue.processAll()).thenAnswer((_) async {});

      // Pre-populate editor state with customer + signatures using the repo
      // so validateDraft() returns isValid=true.
      final repo = DraftReportRepository(db);
      // Update draft to have customer, staff, and mark sigs
      await repo.saveDraft(
        DraftReportsCompanion(
          id: const Value(reportId),
          tenantId: const Value('tenant-1'),
          createdAt: Value(DateTime.utc(2026, 6, 22)),
          updatedAt: Value(DateTime.utc(2026, 6, 22)),
          title: const Value('Test'),
          insertedUserId: const Value('user-1'),
          locationId: const Value('loc-1'),
          customerId: const Value('cust-1'),
          customerSignatureAllegatoId: const Value('sig-c-1'),
          technicianSignatureAllegatoId: const Value('sig-t-1'),
          stato: const Value('Bozza'),
          isLocalOnly: const Value(true),
        ),
      );
      // Insert a staff row so staffCount >= 1
      await db
          .into(db.reportStaffTable)
          .insert(
            ReportStaffTableCompanion.insert(
              id: 'staff-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 22),
              updatedAt: Value(DateTime.utc(2026, 6, 22)),
              reportId: reportId,
              userId: 'user-1',
              hoursWorked: const Value(8.0),
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            realSubmissionQueueProvider.overrideWithValue(fakeQueue),
            // Pre-fill editor state directly
            reportEditorProvider(reportId).overrideWith(
              (ref) => ReportEditorNotifier(
                initialState: ReportEditorState(
                  reportId: reportId,
                  tenantId: 'tenant-1',
                  insertedUserId: 'user-1',
                  title: 'Test',
                  customerId: 'cust-1',
                  locationId: 'loc-1',
                  customerSignatureAllegatoId: 'sig-c-1',
                  customerSignatureLocalPath: '/tmp/sig-c.png',
                  technicianSignatureAllegatoId: 'sig-t-1',
                  technicianSignatureLocalPath: '/tmp/sig-t.png',
                  materialiNotRequired: true,
                  staffRows: [
                    StaffRow(
                      id: 'staff-1',
                      userId: 'user-1',
                      displayName: 'Mario Rossi',
                      hoursWorked: 8.0,
                    ),
                  ],
                ),
                repo: DraftReportRepository(db),
              ),
            ),
          ],
          child: MaterialApp(home: RapportinoFormScreen(reportId: reportId)),
        ),
      );
      await tester.pumpAndSettle();

      await _openTile(tester, 'Riepilogo');

      // Invia button present + enabled
      final inviaBtn = find.text('Invia rapportino');
      expect(inviaBtn, findsOneWidget);
      await tester.ensureVisible(inviaBtn);
      await tester.pumpAndSettle();
      await tester.tap(inviaBtn);
      await tester.pump();

      // Queue must have been called
      verify(() => fakeQueue.enqueue(reportId)).called(1);
      verify(() => fakeQueue.processAll()).called(1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
