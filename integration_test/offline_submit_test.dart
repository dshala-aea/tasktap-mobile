// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// Integration test: offline → submit happy path
//
// IMPORTANT: This test requires a real device or emulator.
// Run with:
//   flutter test integration_test/offline_submit_test.dart \
//     --dart-define=SUPABASE_URL=... \
//     --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=API_BASE_URL=...
//
// The API is MOCKED with Mocktail — no real network calls are made.
// The test exercises the full offline→submit flow:
//   1. Create a draft in the local Drift DB
//   2. Fill all required fields (title, cliente, ≥1 staff, materiali or flag,
//      both signatures)
//   3. Mark the draft as readyToSubmit (enqueue)
//   4. Run processAll() against a mocked ReportSubmitApiClient
//   5. Assert the draft transitions to `submitted`
// ══════════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';
import 'package:tasktap_mobile/domain/reports/draft_validation.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockReportSubmitApiClient extends Mock implements ReportSubmitApiClient {}

class FakeSubmitReportRequest extends Fake implements SubmitReportRequest {}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// IDs used throughout the test.
const _reportId = 'integ-report-1';
const _tenantId = 'tenant-integ';
const _userId = 'user-integ';
const _locationId = 'loc-integ';
const _customerSigId = 'sig-customer';
const _techSigId = 'sig-tech';

/// Inserts a fully-populated draft (all required fields filled).
Future<void> _createFullDraft(AppDatabase db) async {
  // ── 1. Draft header ────────────────────────────────────────────────────────
  await db.into(db.draftReports).insert(
        DraftReportsCompanion.insert(
          id: _reportId,
          tenantId: _tenantId,
          createdAt: DateTime.utc(2026, 6, 21, 8),
          title: 'Intervento impianto elettrico',
          insertedUserId: _userId,
          locationId: _locationId,
          // customerId set → cliente presente
          customerId: const Value('cliente-integ'),
          isLocalOnly: const Value(true),
          stato: const Value('Bozza'),
          // Both signatures present
          customerSignatureAllegatoId: const Value(_customerSigId),
          technicianSignatureAllegatoId: const Value(_techSigId),
          // materialiNotRequired = false → we add a materiale row below
          materialiNotRequired: const Value(false),
        ),
      );

  // ── 2. At least one staff row ──────────────────────────────────────────────
  await db.into(db.reportStaffTable).insert(
        ReportStaffTableCompanion.insert(
          id: 'staff-integ-1',
          tenantId: _tenantId,
          createdAt: DateTime.utc(2026, 6, 21, 8),
          reportId: _reportId,
          userId: _userId,
          hoursWorked: const Value(6.0),
          kmTraveled: const Value(40.0),
        ),
      );

  // ── 3. At least one materiale row ─────────────────────────────────────────
  await db.into(db.reportMateriali).insert(
        ReportMaterialiCompanion.insert(
          id: 'mat-integ-1',
          tenantId: _tenantId,
          createdAt: DateTime.utc(2026, 6, 21, 8),
          reportId: _reportId,
          quantity: 2.0,
          freeTextName: const Value('Cavo elettrico 2.5mm²'),
        ),
      );

  // ── 4. Customer signature allegato ────────────────────────────────────────
  await db.into(db.reportAllegati).insert(
        ReportAllegatiCompanion.insert(
          id: _customerSigId,
          tenantId: _tenantId,
          createdAt: DateTime.utc(2026, 6, 21, 9),
          fileName: 'firma_cliente.png',
          contentType: 'image/png',
          sizeBytes: 8192,
          storagePath: '/local/firma_cliente.png',
          url: '/local/firma_cliente.png',
          entityType: 1,
          entityId: _reportId,
          uploadedByUserId: _userId,
          isPendingUpload: const Value(true),
        ),
      );

  // ── 5. Technician signature allegato ─────────────────────────────────────
  await db.into(db.reportAllegati).insert(
        ReportAllegatiCompanion.insert(
          id: _techSigId,
          tenantId: _tenantId,
          createdAt: DateTime.utc(2026, 6, 21, 9, 1),
          fileName: 'firma_tecnico.png',
          contentType: 'image/png',
          sizeBytes: 7168,
          storagePath: '/local/firma_tecnico.png',
          url: '/local/firma_tecnico.png',
          entityType: 1,
          entityId: _reportId,
          uploadedByUserId: _userId,
          isPendingUpload: const Value(true),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeSubmitReportRequest());
  });

  late AppDatabase db;
  late DraftReportRepository repo;
  late MockReportSubmitApiClient mockApi;
  late SubmissionQueue queue;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DraftReportRepository(db);
    mockApi = MockReportSubmitApiClient();
    queue = SubmissionQueue(repo: repo, apiClient: mockApi);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Test 1: Validation passes for a fully-filled draft ────────────────────
  testWidgets(
    'A fully-filled draft passes all validation checks',
    (WidgetTester tester) async {
      await _createFullDraft(db);

      final draft = await repo.getDraft(_reportId);
      expect(draft, isNotNull);

      final staffCount = (await repo.getStaff(_reportId)).length;
      final materialiCount = (await repo.getMateriali(_reportId)).length;

      final result = validateDraft(
        draft: draft!,
        staffCount: staffCount,
        materialiCount: materialiCount,
      );

      expect(result.isValid, isTrue,
          reason: 'Expected no validation issues but got: '
              '${result.italianMessages}');
    },
  );

  // ── Test 2: offline → submitted happy path ────────────────────────────────
  testWidgets(
    'Offline draft reaches submitted state after processAll with mocked API',
    (WidgetTester tester) async {
      await _createFullDraft(db);

      // Mock: attachment upload succeeds — return the same allegato id as server id.
      when(
        () => mockApi.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer((invocation) async {
        final localPath =
            invocation.namedArguments[#localPath] as String;
        // Derive a predictable server id from the local path.
        final serverId = localPath.contains('cliente')
            ? 'server-sig-customer'
            : 'server-sig-tech';
        return ReportAttachmentUploadResponse(allegatoId: serverId);
      });

      // Mock: submit returns success.
      when(
        () => mockApi.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const SubmitReportResponse(
          id: _reportId,
          title: 'Intervento impianto elettrico',
          stato: '1',
          inviatoAt: null,
          replayed: false,
        ),
      );

      // ── Flow: enqueue → processAll ────────────────────────────────────────
      await queue.enqueue(_reportId);

      final afterEnqueue = await repo.getDraft(_reportId);
      expect(afterEnqueue!.submissionState, 'readyToSubmit',
          reason: 'After enqueue the state should be readyToSubmit');

      await queue.processAll();

      // ── Assertions ────────────────────────────────────────────────────────
      final submitted = await repo.getDraft(_reportId);
      expect(submitted, isNotNull);

      final state =
          DraftSubmissionState.fromString(submitted!.submissionState);
      expect(state, DraftSubmissionState.submitted,
          reason: 'Draft should reach submitted state. '
              'Actual state: ${submitted.submissionState}');

      // isLocalOnly should be cleared.
      expect(submitted.isLocalOnly, isFalse,
          reason: 'Submitted draft should no longer be local-only');

      // stato should be updated to "Inviato".
      expect(submitted.stato, 'Inviato',
          reason: 'Submitted draft stato should be Inviato');

      // Verify the API was called exactly once for submit.
      verify(
        () => mockApi.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).called(1);

      // Verify attachments were uploaded (2 signatures).
      verify(
        () => mockApi.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).called(2);
    },
  );

  // ── Test 3: idempotency key is reused on retry ────────────────────────────
  testWidgets(
    'Retry reuses the same idempotency key (server deduplication)',
    (WidgetTester tester) async {
      await _createFullDraft(db);

      // First attempt — API fails.
      when(
        () => mockApi.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenThrow(Exception('Network error'));

      await queue.enqueue(_reportId);
      final keyAfterEnqueue =
          (await repo.getDraft(_reportId))!.idempotencyKey;

      await queue.processAll();

      final failed = await repo.getDraft(_reportId);
      expect(DraftSubmissionState.fromString(failed!.submissionState),
          DraftSubmissionState.failed);
      // Key must be preserved.
      expect(failed.idempotencyKey, keyAfterEnqueue);

      // Second attempt — API succeeds.
      when(
        () => mockApi.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer((inv) async {
        final localPath = inv.namedArguments[#localPath] as String;
        return ReportAttachmentUploadResponse(
          allegatoId: localPath.contains('cliente')
              ? 'server-sig-customer-2'
              : 'server-sig-tech-2',
        );
      });

      when(
        () => mockApi.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const SubmitReportResponse(
          id: _reportId,
          title: 'Intervento impianto elettrico',
          stato: '1',
          inviatoAt: null,
          replayed: false,
        ),
      );

      await queue.retry(_reportId);

      final retried = await repo.getDraft(_reportId);
      expect(DraftSubmissionState.fromString(retried!.submissionState),
          DraftSubmissionState.submitted);
      // The idempotency key must still be the original one.
      expect(retried.idempotencyKey, keyAfterEnqueue,
          reason: 'Idempotency key must not change across retries');
    },
  );
}
