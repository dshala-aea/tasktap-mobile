// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Mocks & fallbacks
// ══════════════════════════════════════════════════════════════════════════════

class MockReportSubmitApiClient extends Mock implements ReportSubmitApiClient {}

class FakeSubmitReportRequest extends Fake implements SubmitReportRequest {}

class FakeReportAttachmentUploadResponse extends Fake implements ReportAttachmentUploadResponse {}

// ══════════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════════

AppDatabase _makeInMemoryDb() => AppDatabase(NativeDatabase.memory());

Future<void> _insertDraft(
  AppDatabase db, {
  String id = 'report-1',
  String submissionState = 'draft',
  String? idempotencyKey,
  bool isPendingAllegato = false,
  String? customerSigId,
  String? technicianSigId,
  // unique suffix for child rows when inserting multiple drafts in same test
  String? suffix,
}) async {
  final s = suffix ?? id;
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          title: 'Test rapportino',
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          isLocalOnly: const Value(true),
          submissionState: Value(submissionState),
          idempotencyKey: Value(idempotencyKey),
          customerSignatureAllegatoId: Value(customerSigId),
          technicianSignatureAllegatoId: Value(technicianSigId),
        ),
      );

  // Insert a staff row
  await db
      .into(db.reportStaffTable)
      .insert(
        ReportStaffTableCompanion.insert(
          id: 'staff-$s',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          reportId: id,
          userId: 'user-1',
        ),
      );

  // Insert a materiale row
  await db
      .into(db.reportMateriali)
      .insert(
        ReportMaterialiCompanion.insert(
          id: 'mat-$s',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          reportId: id,
          quantity: 1.0,
          freeTextName: const Value('Vite'),
        ),
      );

  if (isPendingAllegato) {
    await db
        .into(db.reportAllegati)
        .insert(
          ReportAllegatiCompanion.insert(
            id: 'allegato-local-$s',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            fileName: 'photo.jpg',
            contentType: 'image/jpeg',
            sizeBytes: 1024,
            storagePath: '/local/photo.jpg',
            url: '/local/photo.jpg',
            entityType: 1,
            entityId: id,
            uploadedByUserId: 'user-1',
            isPendingUpload: const Value(true),
          ),
        );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSubmitReportRequest());
  });

  late AppDatabase db;
  late DraftReportRepository repo;
  late MockReportSubmitApiClient mockApiClient;
  late SubmissionQueue queue;

  setUp(() {
    db = _makeInMemoryDb();
    repo = DraftReportRepository(db);
    mockApiClient = MockReportSubmitApiClient();
    queue = SubmissionQueue(repo: repo, apiClient: mockApiClient);
  });

  tearDown(() => db.close());

  group('DraftSubmissionState', () {
    test('fromString maps all known values', () {
      expect(DraftSubmissionState.fromString('draft'), DraftSubmissionState.draft);
      expect(DraftSubmissionState.fromString('readyToSubmit'), DraftSubmissionState.readyToSubmit);
      expect(
        DraftSubmissionState.fromString('uploadingMedia'),
        DraftSubmissionState.uploadingMedia,
      );
      expect(DraftSubmissionState.fromString('submitting'), DraftSubmissionState.submitting);
      expect(DraftSubmissionState.fromString('submitted'), DraftSubmissionState.submitted);
      expect(DraftSubmissionState.fromString('failed'), DraftSubmissionState.failed);
    });

    test('fromString returns draft for null or unknown', () {
      expect(DraftSubmissionState.fromString(null), DraftSubmissionState.draft);
      expect(DraftSubmissionState.fromString('garbage'), DraftSubmissionState.draft);
    });

    test('toPersistedString is stable', () {
      expect(DraftSubmissionState.draft.toPersistedString(), 'draft');
      expect(DraftSubmissionState.readyToSubmit.toPersistedString(), 'readyToSubmit');
      expect(DraftSubmissionState.submitted.toPersistedString(), 'submitted');
      expect(DraftSubmissionState.failed.toPersistedString(), 'failed');
    });
  });

  group('SubmissionQueue.enqueue', () {
    test('transitions draft → readyToSubmit and generates idempotency key', () async {
      await _insertDraft(db);
      await queue.enqueue('report-1');

      final draft = await repo.getDraft('report-1');
      expect(draft, isNotNull);
      expect(draft!.submissionState, 'readyToSubmit');
      expect(draft.idempotencyKey, isNotNull);
      expect(draft.idempotencyKey!.isNotEmpty, isTrue);
    });

    test('enqueue is idempotent — second call does not change key', () async {
      await _insertDraft(db);
      await queue.enqueue('report-1');
      final first = await repo.getDraft('report-1');
      final firstKey = first!.idempotencyKey;

      // Calling enqueue again should not change the key
      await queue.enqueue('report-1');
      final second = await repo.getDraft('report-1');
      // Already readyToSubmit so enqueue is a no-op
      expect(second!.submissionState, 'readyToSubmit');
      // The key is stable (not regenerated on second enqueue call)
      // Note: the second enqueue is a no-op so the key persists from the first
      expect(second.idempotencyKey, firstKey);
    });

    test('enqueue does not change submitted drafts', () async {
      await _insertDraft(db, submissionState: 'submitted');
      await queue.enqueue('report-1');

      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'submitted');
    });
  });

  group('idempotency key stability across retries', () {
    test('retry reuses the same idempotency key', () async {
      await _insertDraft(db, submissionState: 'failed', idempotencyKey: 'stable-key-abc');

      // Mock API to succeed on retry
      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const SubmitReportResponse(
          id: 'report-1',
          title: 'Test',
          stato: '1',
          inviatoAt: null,
          replayed: false,
        ),
      );

      // Capture the idempotency key used in the submit call
      String? capturedKey;
      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((inv) async {
        capturedKey = inv.namedArguments[#idempotencyKey] as String?;
        return const SubmitReportResponse(
          id: 'report-1',
          title: 'Test',
          stato: '1',
          inviatoAt: null,
          replayed: false,
        );
      });

      await queue.retry('report-1');

      expect(capturedKey, 'stable-key-abc');
    });
  });

  group('SubmissionQueue.processAll — no pending allegati', () {
    test('draft with no pending allegati skips to submitting', () async {
      await _insertDraft(db, submissionState: 'readyToSubmit', idempotencyKey: 'key-1');

      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async =>
            const SubmitReportResponse(id: 'report-1', title: 'Test', stato: '1', inviatoAt: null),
      );

      await queue.processAll();

      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'submitted');
      expect(draft.isLocalOnly, isFalse);
      expect(draft.stato, 'Inviato');
    });

    test('submit maps draft → SubmitReportRequest with correct field names', () async {
      await _insertDraft(db, submissionState: 'readyToSubmit', idempotencyKey: 'key-1');

      SubmitReportRequest? capturedRequest;
      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((inv) async {
        capturedRequest = inv.namedArguments[#request] as SubmitReportRequest?;
        return const SubmitReportResponse(
          id: 'report-1',
          title: 'Test',
          stato: '1',
          inviatoAt: null,
        );
      });

      await queue.processAll();

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.id, 'report-1');
      expect(capturedRequest!.title, 'Test rapportino');
      expect(capturedRequest!.locationId, 'loc-1');
      expect(capturedRequest!.staff.length, 1);
      expect(capturedRequest!.staff.first.userId, 'user-1');
      expect(capturedRequest!.materiali.length, 1);
      expect(capturedRequest!.materiali.first.freeTextName, 'Vite');
    });
  });

  group('SubmissionQueue.processAll — with pending allegati', () {
    test('uploads pending allegati before submitting', () async {
      await _insertDraft(
        db,
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-1',
        isPendingAllegato: true,
      );

      when(
        () => mockApiClient.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer(
        (_) async => const ReportAttachmentUploadResponse(allegatoId: 'server-allegato-1'),
      );

      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async =>
            const SubmitReportResponse(id: 'report-1', title: 'Test', stato: '1', inviatoAt: null),
      );

      await queue.processAll();

      // Upload was called once
      verify(
        () => mockApiClient.uploadAttachment(
          reportId: 'report-1',
          localPath: '/local/photo.jpg',
          fileName: 'photo.jpg',
          contentType: 'image/jpeg',
        ),
      ).called(1);

      // Allegato is no longer pending
      final allegati = await repo.getAllegati('report-1');
      final uploaded = allegati.where((a) => !a.isPendingUpload).toList();
      expect(uploaded.length, 1);

      // Draft is submitted
      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'submitted');
    });

    test('maps local allegato id → server allegato id in photoAllegatoIds', () async {
      await _insertDraft(
        db,
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-1',
        isPendingAllegato: true,
      );

      when(
        () => mockApiClient.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer(
        (_) async => const ReportAttachmentUploadResponse(allegatoId: 'server-allegato-99'),
      );

      SubmitReportRequest? capturedRequest;
      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((inv) async {
        capturedRequest = inv.namedArguments[#request] as SubmitReportRequest?;
        return const SubmitReportResponse(
          id: 'report-1',
          title: 'Test',
          stato: '1',
          inviatoAt: null,
        );
      });

      await queue.processAll();

      // photoAllegatoIds now contains the SERVER id, not the local one
      expect(capturedRequest!.photoAllegatoIds, contains('server-allegato-99'));
      expect(capturedRequest!.photoAllegatoIds, isNot(contains('allegato-local-report-1')));
    });
  });

  group('SubmissionQueue — failure path', () {
    test('failure sets state to failed and preserves draft', () async {
      await _insertDraft(db, submissionState: 'readyToSubmit', idempotencyKey: 'key-fail');

      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(Exception('Network error'));

      await queue.processAll();

      final draft = await repo.getDraft('report-1');
      expect(draft, isNotNull); // draft is NOT deleted
      expect(draft!.submissionState, 'failed');
      // This column is rendered verbatim under "Invio fallito" in the Riepilogo step, so it must
      // hold a sentence rather than the exception. It used to store `e.toString()`.
      expect(draft.submissionError, isNot(contains('Network error')));
      expect(draft.submissionError, isNot(contains('Exception')));
      expect(draft.submissionError, contains('Niente è andato perso'));
    });

    test('failed draft can be retried', () async {
      await _insertDraft(db, submissionState: 'failed', idempotencyKey: 'stable-retry-key');

      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async =>
            const SubmitReportResponse(id: 'report-1', title: 'Test', stato: '1', inviatoAt: null),
      );

      await queue.retry('report-1');

      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'submitted');
    });

    test('attachment upload failure sets failed state', () async {
      await _insertDraft(
        db,
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-attach-fail',
        isPendingAllegato: true,
      );

      when(
        () => mockApiClient.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenThrow(Exception('Storage error'));

      await queue.processAll();

      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'failed');
      expect(draft.submissionError, isNot(contains('Storage error')));
      expect(draft.submissionError, isNot(contains('Exception')));
      // submit was NOT called
      verifyNever(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      );
    });
  });

  group('SubmissionQueue — multiple drafts', () {
    test('processAll processes each ready draft independently', () async {
      // Insert two separate ready drafts
      await _insertDraft(
        db,
        id: 'report-A',
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-A',
      );
      await _insertDraft(
        db,
        id: 'report-B',
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-B',
      );

      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((inv) async {
        final req = inv.namedArguments[#request] as SubmitReportRequest;
        return SubmitReportResponse(id: req.id, title: req.title, stato: '1', inviatoAt: null);
      });

      await queue.processAll();

      final a = await repo.getDraft('report-A');
      final b = await repo.getDraft('report-B');
      expect(a!.submissionState, 'submitted');
      expect(b!.submissionState, 'submitted');
    });

    test('failure on one draft does not prevent other from submitting', () async {
      await _insertDraft(
        db,
        id: 'report-good',
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-good',
      );
      await _insertDraft(
        db,
        id: 'report-bad',
        submissionState: 'readyToSubmit',
        idempotencyKey: 'key-bad',
      );

      when(
        () => mockApiClient.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((inv) async {
        final req = inv.namedArguments[#request] as SubmitReportRequest;
        if (req.id == 'report-bad') {
          throw Exception('Bad draft fails');
        }
        return SubmitReportResponse(id: req.id, title: req.title, stato: '1', inviatoAt: null);
      });

      await queue.processAll();

      final good = await repo.getDraft('report-good');
      final bad = await repo.getDraft('report-bad');
      // good submitted, bad failed but NOT deleted
      expect(good!.submissionState, 'submitted');
      expect(bad, isNotNull);
      expect(bad!.submissionState, 'failed');
    });
  });

  group('SubmitReportRequest JSON serialization', () {
    test('toJson includes all required fields', () {
      const req = SubmitReportRequest(
        id: 'guid-1',
        locationId: 'loc-1',
        title: 'Test',
        materialiNotRequired: false,
        staff: [SubmitReportStaffDto(userId: 'user-1', kmTraveled: 10.5)],
        materiali: [SubmitReportMaterialeDto(quantity: 2.0, freeTextName: 'Bullone')],
        controlli: [SubmitReportControlloDto(ticketControlId: 'ctrl-1', boolValue: true)],
      );

      final json = req.toJson();
      expect(json['id'], 'guid-1');
      expect(json['locationId'], 'loc-1');
      expect(json['title'], 'Test');
      expect(json['materialiNotRequired'], false);
      expect((json['staff'] as List).length, 1);
      expect((json['materiali'] as List).length, 1);
      expect((json['controlli'] as List).length, 1);
      expect((json['photoAllegatoIds'] as List).isEmpty, isTrue);
    });

    test('toJson omits null optional fields', () {
      const req = SubmitReportRequest(id: 'guid-1', locationId: 'loc-1', title: 'T');
      final json = req.toJson();
      expect(json.containsKey('scheduleId'), isFalse);
      expect(json.containsKey('ticketId'), isFalse);
      expect(json.containsKey('startedAt'), isFalse);
      expect(json.containsKey('customerSignatureAllegatoId'), isFalse);
    });

    test('staff toJson includes all fields', () {
      const staff = SubmitReportStaffDto(
        userId: 'u-1',
        hoursWorked: 8.0,
        kmTraveled: 120.0,
        vehicle: 'Furgone',
        pauseMinutes: 30,
      );
      final json = staff.toJson();
      expect(json['userId'], 'u-1');
      expect(json['hoursWorked'], 8.0);
      expect(json['kmTraveled'], 120.0);
      expect(json['vehicle'], 'Furgone');
      expect(json['pauseMinutes'], 30);
    });

    test('materiale toJson mirrors backend SubmitReportMaterialeDto fields', () {
      const m = SubmitReportMaterialeDto(
        materialeId: 'mat-guid-1',
        quantity: 3.5,
        unitOfMeasure: 'pz',
        unitPrice: 2.50,
        magazzinoId: 'mag-1',
      );
      final json = m.toJson();
      expect(json['materialeId'], 'mat-guid-1');
      expect(json['quantity'], 3.5);
      expect(json['unitOfMeasure'], 'pz');
      expect(json['unitPrice'], 2.50);
      expect(json['magazzinoId'], 'mag-1');
    });

    test('controllo toJson mirrors backend SubmitReportControlloDto fields', () {
      const c = SubmitReportControlloDto(
        ticketControlId: 'ctrl-1',
        stringValue: 'OK',
        boolValue: true,
      );
      final json = c.toJson();
      // 'ticketControlId' — the id of the *ticket's* control, not the template's. This test
      // asserted 'controlId' and passed for months while every real submission was rejected: it
      // mirrored the Dart class back to itself rather than the backend DTO its name claims.
      expect(json['ticketControlId'], 'ctrl-1');
      expect(json['stringValue'], 'OK');
      expect(json['boolValue'], true);
    });
  });

  group('DraftReportRepository — submission state methods', () {
    test('updateSubmissionState persists state and key', () async {
      await _insertDraft(db);
      await repo.updateSubmissionState(
        reportId: 'report-1',
        state: DraftSubmissionState.readyToSubmit,
        idempotencyKey: 'my-key',
      );

      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'readyToSubmit');
      expect(draft.idempotencyKey, 'my-key');
    });

    test('updateSubmissionState with error persists error message', () async {
      await _insertDraft(db);
      await repo.updateSubmissionState(
        reportId: 'report-1',
        state: DraftSubmissionState.failed,
        error: 'Connection refused',
      );

      final draft = await repo.getDraft('report-1');
      expect(draft!.submissionState, 'failed');
      expect(draft.submissionError, 'Connection refused');
    });

    test('getDraftsReadyToSubmit returns only readyToSubmit drafts', () async {
      await _insertDraft(db, id: 'r1', submissionState: 'readyToSubmit');
      await _insertDraft(db, id: 'r2', submissionState: 'draft');
      await _insertDraft(db, id: 'r3', submissionState: 'submitted');

      final ready = await repo.getDraftsReadyToSubmit();
      expect(ready.length, 1);
      expect(ready.first.id, 'r1');
    });

    test('getPendingAllegati returns only isPendingUpload=true allegati', () async {
      await _insertDraft(db, isPendingAllegato: true);
      // Also insert a non-pending allegato
      await db
          .into(db.reportAllegati)
          .insert(
            ReportAllegatiCompanion.insert(
              id: 'allegato-uploaded',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              fileName: 'old.jpg',
              contentType: 'image/jpeg',
              sizeBytes: 512,
              storagePath: '/server/old.jpg',
              url: 'https://server/old.jpg',
              entityType: 1,
              entityId: 'report-1',
              uploadedByUserId: 'user-1',
              isPendingUpload: const Value(false),
            ),
          );

      final pending = await repo.getPendingAllegati('report-1');
      expect(pending.length, 1);
      expect(pending.first.id, 'allegato-local-report-1');
    });

    test('markAllegatoUploaded clears isPendingUpload when same id', () async {
      await _insertDraft(db, isPendingAllegato: true);
      await repo.markAllegatoUploaded(
        localId: 'allegato-local-report-1',
        serverAllegatoId: 'allegato-local-1', // same id
      );

      final allegati = await repo.getAllegati('report-1');
      expect(allegati.first.isPendingUpload, isFalse);
    });

    test('markAllegatoUploaded replaces local id with server id when different', () async {
      await _insertDraft(db, isPendingAllegato: true);
      await repo.markAllegatoUploaded(
        localId: 'allegato-local-report-1',
        serverAllegatoId: 'server-999',
      );

      final allegati = await repo.getAllegati('report-1');
      expect(allegati.length, 1);
      expect(allegati.first.id, 'server-999');
      expect(allegati.first.isPendingUpload, isFalse);
    });

    test('markSubmitted sets stato=Inviato and isLocalOnly=false', () async {
      await _insertDraft(db);
      await repo.markSubmitted('report-1');

      final draft = await repo.getDraft('report-1');
      expect(draft!.stato, 'Inviato');
      expect(draft.isLocalOnly, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Regression: rapportino autosave data-loss bug.
  //
  // ReportEditorNotifier's autosave used to write the GPS/free-text metadata blob into the same
  // `details` column the technician's typed description lives in, so every autosave silently
  // discarded whatever the technician had typed — and that blob is exactly what SubmissionQueue
  // sends to the backend/customer PDF as the report's description. This drives a real
  // ReportEditorNotifier through a realistic typing + autosave sequence, then submits through the
  // real SubmissionQueue, and asserts the *typed text* — not the metadata blob — reaches the
  // backend payload.
  // ══════════════════════════════════════════════════════════════════════════════
  group('rapportino autosave data-loss regression', () {
    test(
      'typed description reaches the submit payload verbatim, GPS/free-text metadata does not '
      'clobber it',
      () async {
        final editorRepo = DraftReportRepository(db);
        final notifier = ReportEditorNotifier(
          initialState: const ReportEditorState(
            reportId: 'report-1',
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
          ),
          repo: editorRepo,
        );

        // A realistic sequence: title, then the description typed keystroke-by-keystroke (each
        // keystroke triggers autosave in the real UI — see step_dettagli.dart's onChanged), then
        // free-text customer + GPS captured afterwards (also autosaving), exactly the ordering
        // that used to let the metadata blob win the last write to `details`.
        await notifier.setTitle('Manutenzione caldaia');
        const typed = 'Sostituita guarnizione, verificata pressione impianto';
        for (var i = 1; i <= typed.length; i++) {
          await notifier.setDetails(typed.substring(0, i));
        }
        await notifier.setCustomerFreeText('ACME Srl (non in lista)');
        await notifier.setWorkAddress('Via Roma 10, Milano');
        notifier.setGps(45.4642, 9.19);
        // setGps's autosave is fire-and-forget; give it a tick to land before reading back.
        await Future<void>.delayed(Duration.zero);

        // Locally persisted: both survive, in separate columns.
        final draft = await editorRepo.getDraft('report-1');
        expect(draft, isNotNull);
        expect(draft!.details, typed);
        expect(draft.metadataJson, contains('ACME Srl'));
        expect(draft.metadataJson, contains('Via Roma 10'));
        expect(draft.metadataJson, contains('45.4642'));
        // The metadata blob must never appear in `details` again.
        expect(draft.details, isNot(contains('customerFreeText')));
        expect(draft.details, isNot(contains('gpsLatitude')));

        // Fill in what enqueue()/processAll() require to actually submit.
        await db
            .into(db.reportStaffTable)
            .insert(
              ReportStaffTableCompanion.insert(
                id: 'staff-1',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                reportId: 'report-1',
                userId: 'user-1',
              ),
            );
        await db
            .into(db.reportMateriali)
            .insert(
              ReportMaterialiCompanion.insert(
                id: 'mat-1',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                reportId: 'report-1',
                quantity: 1.0,
                freeTextName: const Value('Guarnizione'),
              ),
            );
        await repo.updateSignatureAllegatoId(
          reportId: 'report-1',
          isCustomer: true,
          serverAllegatoId: 'sig-cust',
        );
        await repo.updateSignatureAllegatoId(
          reportId: 'report-1',
          isCustomer: false,
          serverAllegatoId: 'sig-tech',
        );

        SubmitReportRequest? capturedRequest;
        when(
          () => mockApiClient.submitReport(
            request: any(named: 'request'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer((inv) async {
          capturedRequest = inv.namedArguments[#request] as SubmitReportRequest?;
          return const SubmitReportResponse(
            id: 'report-1',
            title: 'Manutenzione caldaia',
            stato: '1',
            inviatoAt: null,
          );
        });

        await queue.enqueue('report-1');
        await queue.processAll();

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.details, typed);
        expect(capturedRequest!.details, isNot(contains('customerFreeText')));
        expect(capturedRequest!.details, isNot(contains('gpsLatitude')));
      },
    );
  });
}
