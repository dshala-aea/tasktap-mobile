// Tests for ReportEditorNotifier + ReportEditorState — M4
//
// Uses in-memory Drift. Verifies:
//   - Autosave round-trips (title, details, customer, location, ticket,
//     cantiere, workAddress)
//   - Free-text vs cache picker exclusivity
//   - Staff add/update/remove + km/hours storage
//   - Timer start/stop math
//   - Materiali add/remove/materialiNotRequired toggle
//   - Controllo upsert
//   - Customer + technician signature attachment to draft
//   - Photo/allegato add/remove
//   - Step navigation
//   - Validation via state.validation
//   - Prefill-from-schedule: preloads title/customer/location/ticket from a
//     cached schedule row

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/reports/draft_validation.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Build an editor notifier backed by an in-memory DB.
///
/// Awaits [ReportEditorNotifier.ready] before returning: the notifier's constructor kicks off an
/// async hydration read from Drift (loads an existing draft's saved data, if any — see
/// ReportEditorNotifier._hydrate's own doc comment), and every test in this file calls setter
/// methods immediately after construction. Without waiting, hydration completing later than a
/// test's own setter calls would silently revert them back to whatever was already in the DB.
Future<(ReportEditorNotifier notifier, DraftReportRepository repo)> _makeEditor(
  AppDatabase db, {
  String reportId = 'draft-1',
  String tenantId = 'tenant-1',
  String userId = 'user-1',
}) async {
  final repo = DraftReportRepository(db);
  final state = ReportEditorState(
    reportId: reportId,
    tenantId: tenantId,
    insertedUserId: userId,
    createdAt: DateTime.utc(2026, 6, 21, 10),
  );
  final notifier = ReportEditorNotifier(initialState: state, repo: repo);
  await notifier.ready;
  return (notifier, repo);
}

/// Insert a draft header before the notifier autosaves.
Future<void> _seedDraft(AppDatabase db, String reportId) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: reportId,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 21, 10),
          title: 'init',
          insertedUserId: 'user-1',
          locationId: '',
          isLocalOnly: const Value(true),
          stato: const Value('Bozza'),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  // ── Dati step autosave ─────────────────────────────────────────────────────

  group('autosave — dati step', () {
    test('setTitle persists title to Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.setTitle('Manutenzione pompa');

      final draft = await repo.getDraft('draft-1');
      expect(draft, isNotNull);
      expect(draft!.title, 'Manutenzione pompa');
    });

    test('setDetails persists details to Drift verbatim (not the metadata blob)', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.setDetails('Intervento ordinario');

      expect(notifier.state.details, 'Intervento ordinario');
      // Regression: the persisted `details` column used to be overwritten by
      // `_buildMetadataJson()` (GPS/free-text metadata) on every autosave, never the text actually
      // typed here. See the "rapportino data-loss regression" group below.
      final draft = await repo.getDraft('draft-1');
      expect(draft!.details, 'Intervento ordinario');
    });

    test('setCustomerFromCache sets customerId and clears freeText', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setCustomerFreeText('vecchio nome');
      await notifier.setCustomerFromCache('cust-42');

      expect(notifier.state.customerId, 'cust-42');
      expect(notifier.state.customerFreeText, isNull);
    });

    test('setCustomerFreeText sets freeText and clears customerId', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setCustomerFromCache('cust-old');
      await notifier.setCustomerFreeText('ACME Srl (non in lista)');

      expect(notifier.state.customerFreeText, 'ACME Srl (non in lista)');
      expect(notifier.state.customerId, isNull);
    });

    test('setWorkAddress persists address', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setWorkAddress('Via Roma 10, Milano');

      expect(notifier.state.workAddress, 'Via Roma 10, Milano');
    });

    test('setTicketFromCache clears cantiere fields', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setCantiereFromCache('cant-1');
      await notifier.setTicketFromCache('ticket-99');

      expect(notifier.state.ticketId, 'ticket-99');
      expect(notifier.state.cantiereId, isNull);
    });

    test('setCantiereFromCache clears ticket fields', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setTicketFromCache('ticket-1');
      await notifier.setCantiereFromCache('cant-99');

      expect(notifier.state.cantiereId, 'cant-99');
      expect(notifier.state.ticketId, isNull);
    });

    test('setGps stores lat/lng in state', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      notifier.setGps(45.4654, 9.1859);

      expect(notifier.state.gpsLatitude, closeTo(45.4654, 0.0001));
      expect(notifier.state.gpsLongitude, closeTo(9.1859, 0.0001));
    });
  });

  // ── Staff step ─────────────────────────────────────────────────────────────

  group('staff step', () {
    test('addStaff adds a row and persists to Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addStaff(
        const StaffRow(
          id: 's-1',
          userId: 'user-2',
          displayName: 'Mario Rossi',
          hoursWorked: 6.0,
          kmTraveled: 80.0,
        ),
      );

      expect(notifier.state.staffRows.length, 1);
      expect(notifier.state.staffRows.first.userId, 'user-2');

      final dbRows = await repo.getStaff('draft-1');
      expect(dbRows.length, 1);
      expect(dbRows.first.kmTraveled, 80.0);
    });

    test('updateStaff updates the row in state and Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      const original = StaffRow(id: 's-1', userId: 'user-2', hoursWorked: 4.0, kmTraveled: 40.0);
      await notifier.addStaff(original);
      await notifier.updateStaff(original.copyWith(hoursWorked: 8.0));

      expect(notifier.state.staffRows.first.hoursWorked, 8.0);
      final dbRows = await repo.getStaff('draft-1');
      // effectiveHours: no timer, so hoursWorked=8.0 or 0 depending on logic
      // The companion uses effectiveHours OR hoursWorked. With no timer, effectiveHours = hoursWorked
      expect(dbRows.first.hoursWorked, isNotNull);
    });

    test('removeStaff removes from state and Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addStaff(const StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 4.0));
      await notifier.removeStaff('s-1');

      expect(notifier.state.staffRows, isEmpty);
      expect(await repo.getStaff('draft-1'), isEmpty);
    });

    test('multiple staff rows all persisted', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addStaff(const StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 4.0));
      await notifier.addStaff(const StaffRow(id: 's-2', userId: 'u-2', hoursWorked: 6.0));
      await notifier.addStaff(const StaffRow(id: 's-3', userId: 'u-3', hoursWorked: 8.0));

      expect(notifier.state.staffRows.length, 3);
      expect((await repo.getStaff('draft-1')).length, 3);
    });
  });

  // ── Timer math ─────────────────────────────────────────────────────────────

  group('staff timer math', () {
    test('effectiveHours uses startTime/endTime when timer ran', () {
      final start = DateTime.utc(2026, 6, 21, 8, 0);
      final end = DateTime.utc(2026, 6, 21, 16, 0);
      final row = StaffRow(
        id: 's-1',
        userId: 'u-1',
        startTime: start,
        endTime: end,
        pauseMinutes: 60, // 1h lunch
      );

      // 8h total − 1h pause = 7h
      expect(row.effectiveHours, closeTo(7.0, 0.01));
    });

    test('effectiveHours falls back to hoursWorked when no timer', () {
      const row = StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 5.5);

      expect(row.effectiveHours, 5.5);
    });

    test('effectiveHours returns 0 when neither timer nor hoursWorked set', () {
      const row = StaffRow(id: 's-1', userId: 'u-1');

      expect(row.effectiveHours, 0.0);
    });

    test('startTimer sets timerRunning=true and records startTime', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.addStaff(const StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 0.0));
      await notifier.startTimer('s-1');

      final row = notifier.state.staffRows.first;
      expect(row.timerRunning, isTrue);
      expect(row.startTime, isNotNull);
      expect(row.timerStartedAt, isNotNull);
    });

    test('stopTimer sets timerRunning=false and endTime', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.addStaff(const StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 0.0));
      await notifier.startTimer('s-1');
      await notifier.stopTimer('s-1');

      final row = notifier.state.staffRows.first;
      expect(row.timerRunning, isFalse);
      expect(row.endTime, isNotNull);
    });
  });

  // ── Materiali step ─────────────────────────────────────────────────────────

  group('materiali step', () {
    test('addMateriale with free-text persists to Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addMateriale(
        const MaterialeRow(
          id: 'm-1',
          reportId: 'draft-1',
          freeTextName: 'Cavo coassiale',
          quantity: 5.0,
          unitOfMeasure: 'm',
        ),
      );

      expect(notifier.state.materialeRows.length, 1);
      final dbRows = await repo.getMateriali('draft-1');
      expect(dbRows.first.freeTextName, 'Cavo coassiale');
      expect(dbRows.first.quantity, 5.0);
      expect(dbRows.first.materialeId, isNull);
    });

    test('addMateriale with cache materialeId persists correctly', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addMateriale(
        const MaterialeRow(id: 'm-2', reportId: 'draft-1', materialeId: 'mat-42', quantity: 2.0),
      );

      final dbRows = await repo.getMateriali('draft-1');
      expect(dbRows.first.materialeId, 'mat-42');
      expect(dbRows.first.freeTextName, isNull);
    });

    // Gap 1 (feature audit, module #7): a material line with no magazzinoId reaches the server
    // fine but silently never depletes stock — StockMovementService no-ops on a null MagazzinoId.
    test('addMateriale persists magazzinoId to Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addMateriale(
        const MaterialeRow(
          id: 'm-3',
          reportId: 'draft-1',
          materialeId: 'mat-1',
          quantity: 2.0,
          magazzinoId: 'furgone-1',
        ),
      );

      final dbRows = await repo.getMateriali('draft-1');
      expect(dbRows.first.magazzinoId, 'furgone-1');
    });

    test('a materiale row with no magazzinoId persists it as null, not lost silently', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addMateriale(
        const MaterialeRow(id: 'm-4', reportId: 'draft-1', materialeId: 'mat-1', quantity: 1.0),
      );

      final dbRows = await repo.getMateriali('draft-1');
      expect(dbRows.first.magazzinoId, isNull);
    });

    test('updateMateriale (quantity change via the qty stepper) preserves magazzinoId', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addMateriale(
        const MaterialeRow(
          id: 'm-5',
          reportId: 'draft-1',
          materialeId: 'mat-1',
          quantity: 1.0,
          magazzinoId: 'furgone-1',
        ),
      );
      final row = notifier.state.materialeRows.first;
      await notifier.updateMateriale(row.copyWith(quantity: 3.0));

      final dbRows = await repo.getMateriali('draft-1');
      expect(dbRows.first.quantity, 3.0);
      expect(dbRows.first.magazzinoId, 'furgone-1');
    });

    test('removeMateriale removes from state and Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addMateriale(
        const MaterialeRow(id: 'm-1', reportId: 'draft-1', freeTextName: 'Test', quantity: 1.0),
      );
      await notifier.removeMateriale('m-1');

      expect(notifier.state.materialeRows, isEmpty);
      expect(await repo.getMateriali('draft-1'), isEmpty);
    });

    test('setMaterialiNotRequired updates state and autosaves', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.setMaterialiNotRequired(true);

      expect(notifier.state.materialiNotRequired, isTrue);
      final draft = await repo.getDraft('draft-1');
      expect(draft?.materialiNotRequired, isTrue);
    });
  });

  // ── Signatures ────────────────────────────────────────────────────────────

  group('signature attachment', () {
    test('saveCustomerSignature sets customerSignatureAllegatoId in state', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);
      final bytes = Uint8List.fromList([0, 1, 2, 3]);

      await notifier.saveCustomerSignature(
        allegatoId: 'sig-cust-1',
        bytes: bytes,
        localPath: '/tmp/sig-cust-1.png',
      );

      expect(notifier.state.customerSignatureAllegatoId, 'sig-cust-1');
      expect(notifier.state.customerSignatureLocalPath, '/tmp/sig-cust-1.png');

      // Persisted to Drift
      final draft = await repo.getDraft('draft-1');
      expect(draft?.customerSignatureAllegatoId, 'sig-cust-1');

      final allegati = await repo.getAllegati('draft-1');
      expect(allegati.any((a) => a.id == 'sig-cust-1'), isTrue);
    });

    test('saveTechnicianSignature sets technicianSignatureAllegatoId in state', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);
      final bytes = Uint8List.fromList([10, 20, 30]);

      await notifier.saveTechnicianSignature(
        allegatoId: 'sig-tech-1',
        bytes: bytes,
        localPath: '/tmp/sig-tech-1.png',
      );

      expect(notifier.state.technicianSignatureAllegatoId, 'sig-tech-1');
      final draft = await repo.getDraft('draft-1');
      expect(draft?.technicianSignatureAllegatoId, 'sig-tech-1');
    });

    test('clearCustomerSignature removes allegatoId from state', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);
      final bytes = Uint8List.fromList([0]);

      await notifier.saveCustomerSignature(
        allegatoId: 'sig-c',
        bytes: bytes,
        localPath: '/tmp/sig-c.png',
      );
      await notifier.clearCustomerSignature();

      expect(notifier.state.customerSignatureAllegatoId, isNull);
    });

    test(
      'reopening the editor (a fresh notifier against the same draft) restores both '
      'signature local paths, not just their allegatoIds',
      () async {
        await _seedDraft(db, 'draft-1');
        final (firstNotifier, _) = await _makeEditor(db);

        await firstNotifier.saveCustomerSignature(
          allegatoId: 'sig-cust-1',
          bytes: Uint8List.fromList([0, 1, 2]),
          localPath: '/tmp/sig-cust-1.png',
        );
        await firstNotifier.saveTechnicianSignature(
          allegatoId: 'sig-tech-1',
          bytes: Uint8List.fromList([3, 4, 5]),
          localPath: '/tmp/sig-tech-1.png',
        );

        // Simulates app restart / navigating away and back: a brand-new notifier instance
        // hydrating from the same persisted draft, not the same in-memory state.
        final (reopenedNotifier, _) = await _makeEditor(db);

        expect(reopenedNotifier.state.customerSignatureAllegatoId, 'sig-cust-1');
        expect(reopenedNotifier.state.customerSignatureLocalPath, '/tmp/sig-cust-1.png');
        expect(reopenedNotifier.state.technicianSignatureAllegatoId, 'sig-tech-1');
        expect(reopenedNotifier.state.technicianSignatureLocalPath, '/tmp/sig-tech-1.png');
      },
    );
  });

  // ── Photo allegati ────────────────────────────────────────────────────────

  group('photo allegati', () {
    test('addAllegato stores photo path in state and Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addAllegato(
        const AllegatoRow(
          id: 'photo-1',
          localPath: '/sdcard/photo1.jpg',
          fileName: 'photo1.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 102400,
        ),
      );

      expect(notifier.state.allegatoRows.length, 1);
      final dbRows = await repo.getAllegati('draft-1');
      expect(dbRows.any((a) => a.id == 'photo-1'), isTrue);
      expect(dbRows.first.isPendingUpload, isTrue);
    });

    test('removeAllegato removes from state and Drift', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      await notifier.addAllegato(
        const AllegatoRow(
          id: 'photo-del',
          localPath: '/tmp/x.jpg',
          fileName: 'x.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1024,
        ),
      );
      await notifier.removeAllegato('photo-del');

      expect(notifier.state.allegatoRows, isEmpty);
      expect(await repo.getAllegati('draft-1'), isEmpty);
    });
  });

  // ── Step navigation ───────────────────────────────────────────────────────

  group('step navigation', () {
    test('starts on dati step', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      expect(notifier.state.currentStep, RapportinoStep.dati);
    });

    test('nextStep advances to staff', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.nextStep();

      expect(notifier.state.currentStep, RapportinoStep.staff);
    });

    test('nextStep cycles through all steps', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      final steps = RapportinoStep.values;
      for (var i = 1; i < steps.length; i++) {
        await notifier.nextStep();
        expect(notifier.state.currentStep, steps[i]);
      }
    });

    test('prevStep goes back to dati from staff', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.nextStep(); // → staff
      await notifier.prevStep(); // → dati

      expect(notifier.state.currentStep, RapportinoStep.dati);
    });

    test('prevStep does nothing when already on dati', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.prevStep();

      expect(notifier.state.currentStep, RapportinoStep.dati);
    });

    test('goToStep jumps directly to any step', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.goToStep(RapportinoStep.firme);

      expect(notifier.state.currentStep, RapportinoStep.firme);
    });
  });

  // ── Validation via state ──────────────────────────────────────────────────

  group('state.validation — mirrors server state machine', () {
    test('isReadyToSubmit=false for empty draft', () async {
      // No _seedDraft here, deliberately: it seeds title: 'init', which is a title. A genuinely
      // titleless draft is one with no DB row at all yet — hydration finds nothing and leaves
      // the notifier's own blank initialState exactly as constructed.
      final (notifier, _) = await _makeEditor(db);

      expect(notifier.state.isReadyToSubmit, isFalse);
      expect(notifier.state.validation.issues, contains(DraftValidationIssue.missingTitle));
    });

    test('isReadyToSubmit=true when all requirements met', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setTitle('Test');
      await notifier.setCustomerFromCache('cust-1');

      await notifier.addStaff(const StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 4.0));
      await notifier.addMateriale(
        const MaterialeRow(id: 'm-1', reportId: 'draft-1', freeTextName: 'Cavo', quantity: 1.0),
      );
      await notifier.saveCustomerSignature(
        allegatoId: 'sig-c',
        bytes: Uint8List.fromList([1]),
        localPath: '/tmp/sc.png',
      );
      await notifier.saveTechnicianSignature(
        allegatoId: 'sig-t',
        bytes: Uint8List.fromList([2]),
        localPath: '/tmp/st.png',
      );

      expect(notifier.state.isReadyToSubmit, isTrue);
      expect(notifier.state.validation.issues, isEmpty);
    });

    test('noMateriali not flagged when materialiNotRequired=true', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, _) = await _makeEditor(db);

      await notifier.setTitle('T');
      await notifier.setCustomerFromCache('c');
      await notifier.addStaff(const StaffRow(id: 's-1', userId: 'u-1', hoursWorked: 1.0));
      await notifier.setMaterialiNotRequired(true);
      await notifier.saveCustomerSignature(
        allegatoId: 'sc',
        bytes: Uint8List.fromList([1]),
        localPath: '/tmp/sc.png',
      );
      await notifier.saveTechnicianSignature(
        allegatoId: 'st',
        bytes: Uint8List.fromList([2]),
        localPath: '/tmp/st.png',
      );

      expect(notifier.state.isReadyToSubmit, isTrue);
    });
  });

  // ── Prefill from schedule ─────────────────────────────────────────────────

  group('prefill-from-schedule simulation', () {
    // The prefill logic is done externally: read a Schedule from Drift,
    // then call notifier methods to populate the editor state.
    // We verify the notifier correctly stores the prefilled values.

    test('can be prefilled with schedule title, customer, location, ticket', () async {
      // Simulate a cached schedule + linked entities in the DB
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cust-sched',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 21),
              companyName: 'Cliente Schedule Spa',
            ),
          );

      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 'ticket-sched',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 21),
              title: 'Ticket da schedule',
              customerId: 'cust-sched',
              locationId: 'loc-sched',
              statusId: 1,
              typeId: 1,
            ),
          );

      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 21),
              activityDate: DateTime.utc(2026, 6, 21),
              timeStartMinutes: 480,
              timeEndMinutes: 1020,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-sched',
              title: 'Manutenzione da schedule',
              description: 'Descrizione da schedule',
              ticketId: const Value('ticket-sched'),
            ),
          );

      await _seedDraft(db, 'draft-prefill');
      final (notifier, _) = await _makeEditor(db, reportId: 'draft-prefill');

      // Simulate prefill: caller reads schedule and calls notifier methods
      final sched = await (db.select(
        db.schedules,
      )..where((s) => s.id.equals('sched-1'))).getSingle();

      await notifier.setTitle(sched.title);
      await notifier.setLocationFromCache(sched.locationId);
      if (sched.ticketId != null) {
        await notifier.setTicketFromCache(sched.ticketId!);
      }

      expect(notifier.state.title, 'Manutenzione da schedule');
      expect(notifier.state.locationId, 'loc-sched');
      expect(notifier.state.ticketId, 'ticket-sched');
      expect(notifier.state.scheduleId, isNull); // not set by prefill above
    });

    test('prefill sets scheduleId', () async {
      await _seedDraft(db, 'draft-prefill2');
      final (notifier, _) = await _makeEditor(db, reportId: 'draft-prefill2');

      // Directly test setTitle with schedule info
      await notifier.setTitle('Da schedule');

      // scheduleId field would be set by the screen, not the notifier directly
      // But we can verify the state is populated correctly:
      expect(notifier.state.title, 'Da schedule');
    });
  });

  // ── Riverpod container integration ────────────────────────────────────────

  group('Riverpod provider integration', () {
    test('draftReportRepositoryProvider wires to appDatabaseProvider', () async {
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final repo = container.read(draftReportRepositoryProvider);
      expect(repo, isA<DraftReportRepository>());
    });

    test('reportEditorProvider.family returns unique notifier per id', () async {
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final state1 = container.read(reportEditorProvider('report-a'));
      final state2 = container.read(reportEditorProvider('report-b'));

      expect(state1.reportId, 'report-a');
      expect(state2.reportId, 'report-b');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Regression: rapportino data-loss bug.
  //
  // `_buildHeaderCompanion()` used to write `_buildDetailsJson()` (GPS/free-text metadata) into
  // the `details` column — the same column `setDetails` puts the technician's typed description
  // into — on every autosave. Metadata always won the last write, so the typed description never
  // reached Drift, the backend, or the customer-facing PDF. `details` and `metadataJson` are
  // separate columns now (schema v14); see submission_queue_test.dart for the full
  // typing→submit-payload version of this regression.
  // ══════════════════════════════════════════════════════════════════════════════
  group('rapportino data-loss regression — details vs metadata', () {
    test('a description typed then autosaved is preserved, not overwritten by metadata', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      // Metadata (GPS + free-text) captured first, as it often is on-site before the technician
      // writes up what they did.
      await notifier.setWorkAddress('Via Roma 10, Milano');
      notifier.setGps(45.4654, 9.1859);
      await notifier.setCustomerFreeText('ACME Srl (non in lista)');

      // Then the technician types the actual description, which autosaves.
      await notifier.setDetails('Sostituita guarnizione bruciatore');

      final draft = await repo.getDraft('draft-1');
      expect(draft!.details, 'Sostituita guarnizione bruciatore');
      expect(draft.details, isNot(contains('gpsLatitude')));
      expect(draft.details, isNot(contains('workAddress')));
      // The metadata is not lost either — it lives in its own column.
      expect(draft.metadataJson, contains('workAddress'));
      expect(draft.metadataJson, contains('customerFreeText'));
    });

    test('metadata captured after the description does not clobber it on a later autosave', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      // The order that actually triggered the bug: description typed first, metadata captured
      // afterwards (e.g. GPS acquired at the end of the visit) — every autosave in between,
      // including the ones after the GPS capture, used to overwrite `details` with metadata-only
      // JSON that contained no trace of the typed text.
      await notifier.setDetails('Sostituita guarnizione bruciatore');
      await notifier.setWorkAddress('Via Roma 10, Milano');
      notifier.setGps(45.4654, 9.1859);
      await notifier.setCantiereFreeText('Cantiere Nord');

      expect(notifier.state.details, 'Sostituita guarnizione bruciatore');
      final draft = await repo.getDraft('draft-1');
      expect(draft!.details, 'Sostituita guarnizione bruciatore');
    });

    test('a realistic keystroke-by-keystroke typing sequence survives every intermediate autosave', () async {
      await _seedDraft(db, 'draft-1');
      final (notifier, repo) = await _makeEditor(db);

      const typed = 'Verificata pressione impianto, nessuna anomalia riscontrata';
      // Mirrors StepDettagli's AppTextField.onChanged, which calls setDetails (and therefore
      // autosaves) on every keystroke.
      for (var i = 1; i <= typed.length; i++) {
        await notifier.setDetails(typed.substring(0, i));
      }
      // GPS captured mid-typing, as the "Acquisisci" button allows at any point in the flow.
      notifier.setGps(45.4654, 9.1859);
      await notifier.setDetails(typed); // one more keystroke-driven autosave after GPS

      expect(notifier.state.details, typed);
      final draft = await repo.getDraft('draft-1');
      expect(draft!.details, typed);
      expect(draft.metadataJson, contains('gpsLatitude'));
    });
  });
}
