// dart format width=100
// test/data/sync/submission_queue_offline_test.dart
//
// Offline slice O-3 / audit F25 (P0-7): "a submit never fails for being offline".
//
// The rule under test:
//   * a NO-RESPONSE failure while the device has no reachable network leaves the row
//     `readyToSubmit`, with no error text and NO retry attempt consumed;
//   * only a transient the SERVER answered (5xx / 408 / 429 / 401) spends the budget;
//   * a genuine server rejection still surfaces as `failed` with its Italian message.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';

class MockReportSubmitApiClient extends Mock implements ReportSubmitApiClient {}

class FakeSubmitReportRequest extends Fake implements SubmitReportRequest {}

const _reportId = 'report-offline';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _insertReadyDraft(
  AppDatabase db, {
  int attempts = 0,
  String submissionState = 'readyToSubmit',
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: _reportId,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          title: 'Rapportino firmato',
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          isLocalOnly: const Value(true),
          materialiNotRequired: const Value(true),
          submissionState: Value(submissionState),
          idempotencyKey: const Value('key-offline'),
          submissionAttempts: Value(attempts),
          submissionErrorTransient: const Value(true),
        ),
      );
  // One staff row: `_buildRequest` reads children even though the send never gets that far.
  await db
      .into(db.reportStaffTable)
      .insert(
        ReportStaffTableCompanion.insert(
          id: 'staff-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          reportId: _reportId,
          userId: 'user-1',
        ),
      );
}

/// A DioException shaped like "nothing answered": connectionError, no response.
DioException _noResponse() => DioException(
  requestOptions: RequestOptions(path: '/api/reports/submit'),
  type: DioExceptionType.connectionError,
  message: 'Connection failed',
);

DioException _status(int status) {
  final options = RequestOptions(path: '/api/reports/submit');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(FakeSubmitReportRequest()));

  late AppDatabase db;
  late DraftReportRepository repo;
  late MockReportSubmitApiClient api;

  setUp(() {
    db = _makeDb();
    repo = DraftReportRepository(db);
    api = MockReportSubmitApiClient();
    when(
      () => api.submitReport(
        request: any(named: 'request'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenThrow(_noResponse());
  });

  tearDown(() => db.close());

  Future<void> expectQueued() async {
    final draft = (await repo.getDraft(_reportId))!;
    expect(
      draft.submissionState,
      'readyToSubmit',
      reason: 'being offline is not a failed send — the row must stay queued',
    );
    expect(draft.submissionError, isNull, reason: 'no "Invio fallito" message while queued');
    expect(draft.submissionAttempts, 0, reason: 'being offline must not spend a retry attempt');
    expect(draft.submissionErrorTransient, isFalse);
  }

  group('P0-7 — a no-response failure with no reachable network is not a failure', () {
    test('cached offline, probe offline: row stays readyToSubmit, attempts unchanged', () async {
      await _insertReadyDraft(db);
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => false,
        recheckOnline: () async => false,
      );

      await queue.processAll(force: true);

      await expectQueued();
    });

    test('cached "online" (interface up) but the probe says nothing is reachable — a captive '
        'portal or a dead Wi-Fi still leaves the row queued', () async {
      await _insertReadyDraft(db);
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        // The cached provider value the old code trusted: "the interface is up".
        isOnline: () => true,
        // ...but the authoritative probe says the network is not actually reachable.
        recheckOnline: () async => false,
      );

      await queue.processAll(force: true);

      await expectQueued();
    });

    test('six manual Invia taps offline consume zero retries and never strand the row behind '
        '"Riprova"', () async {
      await _insertReadyDraft(db);
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => false,
        recheckOnline: () async => false,
      );

      for (var i = 0; i < 6; i++) {
        await queue.processAll(force: true);
        await expectQueued();
      }
      // Still queued, so the next reconnect/resume flush sends it unattended.
      expect(await repo.getDraftsReadyToSubmit(), hasLength(1));
    });

    test('an attachment upload with no response while offline also keeps the row queued', () async {
      await _insertReadyDraft(db);
      await db
          .into(db.reportAllegati)
          .insert(
            ReportAllegatiCompanion.insert(
              id: 'allegato-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              fileName: 'foto.jpg',
              contentType: 'image/jpeg',
              sizeBytes: 1024,
              storagePath: '/app/captures/foto.jpg',
              url: '/app/captures/foto.jpg',
              entityType: 1,
              entityId: _reportId,
              uploadedByUserId: 'user-1',
              isPendingUpload: const Value(true),
            ),
          );
      when(
        () => api.uploadAttachment(
          reportId: any(named: 'reportId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
          kind: any(named: 'kind'),
          capturedLatitude: any(named: 'capturedLatitude'),
          capturedLongitude: any(named: 'capturedLongitude'),
          capturedAt: any(named: 'capturedAt'),
        ),
      ).thenThrow(_noResponse());
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => false,
        recheckOnline: () async => false,
      );

      await queue.processAll(force: true);

      await expectQueued();
      // The allegato is still pending, so the retry resumes exactly where it stopped.
      expect(await repo.getPendingAllegati(_reportId), hasLength(1));
    });
  });

  group('P0-7 — only server-answered transients spend the retry budget', () {
    test('a 503 counts exactly one attempt', () async {
      await _insertReadyDraft(db);
      when(
        () => api.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_status(503));
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => true,
        recheckOnline: () async => true,
      );

      await queue.processAll(force: true);

      final draft = (await repo.getDraft(_reportId))!;
      expect(draft.submissionState, 'failed');
      expect(draft.submissionAttempts, 1);
      expect(draft.submissionErrorTransient, isTrue);
      expect(draft.submissionError, isNotNull);
    });

    test('a 429 also counts one attempt (back-pressure is the server answering)', () async {
      await _insertReadyDraft(db);
      when(
        () => api.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_status(429));
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => true,
        recheckOnline: () async => true,
      );

      await queue.processAll(force: true);

      expect((await repo.getDraft(_reportId))!.submissionAttempts, 1);
    });

    test('a no-response failure while the network IS reachable becomes a transient failure but '
        'spends no attempt — the server never saw it, so "five tries" would measure radio flapping',
        () async {
      await _insertReadyDraft(db, attempts: 2);
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => true,
        recheckOnline: () async => true,
      );

      await queue.processAll(force: true);

      final draft = (await repo.getDraft(_reportId))!;
      expect(draft.submissionState, 'failed');
      expect(draft.submissionAttempts, 2, reason: 'attempt counter untouched');
      expect(draft.submissionErrorTransient, isTrue);
      expect(draft.submissionError, isNotNull, reason: 'a real transport failure is still surfaced');
      // Still eligible for the next unattended flush.
      expect(await repo.getRetryableFailedDrafts(maxAttempts: 5), hasLength(1));
    });

    test('a genuine server rejection (400) still surfaces and is never auto-retried', () async {
      await _insertReadyDraft(db);
      when(
        () => api.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_status(400));
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => true,
        recheckOnline: () async => true,
      );

      await queue.processAll(force: true);

      final draft = (await repo.getDraft(_reportId))!;
      expect(draft.submissionState, 'failed');
      expect(draft.submissionErrorTransient, isFalse);
      expect(draft.submissionError, isNotNull);
      expect(await repo.getRetryableFailedDrafts(maxAttempts: 5), isEmpty);
    });
  });
}
