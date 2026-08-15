// dart format width=100
// test/features/rapportino/rapportino_form_screen_test.dart
//
// Widget tests for the 4-step rapportino form (D3b).
//
// Covers:
//   1. All 4 steps render without errors.
//   2. "Avanti" navigates forward through steps.
//   3. "Indietro" navigates backward.
//   4. Validate blocks submit on step 4 when firma is missing.
//   5. Submit calls the queue (fake realSubmissionQueueProvider).

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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  const reportId = 'draft-test-1';

  group('RapportinoFormScreen — step rendering', () {
    testWidgets('step 1 (Dettagli) renders titolo field', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      // The step should contain a titolo text field
      expect(find.text('Titolo *'), findsWidgets);
      // Avanti button visible on step 1
      expect(find.text('Avanti'), findsOneWidget);
      // Indietro NOT visible on step 1
      expect(find.text('Indietro'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Avanti navigates from step 1 to step 2', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // Step 2 shows staff-related text
      expect(find.text('Aggiungi tecnico'), findsOneWidget);
      // Indietro now visible
      expect(find.text('Indietro'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Indietro navigates from step 2 back to step 1', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      // Go to step 2
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      expect(find.text('Aggiungi tecnico'), findsOneWidget);

      // Go back
      await tester.tap(find.text('Indietro'));
      await tester.pumpAndSettle();

      // Back on step 1
      expect(find.text('Titolo *'), findsWidgets);
      expect(find.text('Indietro'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('step 3 (Materiali) renders Aggiungi materiale button', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      // Navigate to step 3
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      expect(find.text('Aggiungi materiale'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('step 4 (Riepilogo) renders firma blocks + validation panel', (tester) async {
      await _seedDraft(db, reportId);
      await tester.pumpWidget(_buildForm(db: db, reportId: reportId));
      await tester.pumpAndSettle();

      // Navigate to step 4
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Avanti'));
        await tester.pumpAndSettle();
      }

      // Invia button present but disabled (missing sigs)
      expect(find.text('Invia rapportino'), findsOneWidget);
      // Validation messages visible
      expect(find.text('Da completare prima dell\'invio:'), findsOneWidget);
      // No Avanti on last step
      expect(find.text('Avanti'), findsNothing);

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

      // Navigate to step 4
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Avanti'));
        await tester.pumpAndSettle();
      }

      // Tap "Invia rapportino" — should be no-op because validation fails
      final inviaBtn = find.text('Invia rapportino');
      expect(inviaBtn, findsOneWidget);
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

      // Navigate to step 4
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Avanti'));
        await tester.pumpAndSettle();
      }

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
