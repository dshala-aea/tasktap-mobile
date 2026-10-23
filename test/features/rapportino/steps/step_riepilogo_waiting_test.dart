// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';
import 'package:tasktap_mobile/data/sync/submission_queue_watcher.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import 'dart:typed_data';

const _reportId = 'draft-w';

class _NoSignature implements UserSignatureApiClient {
  const _NoSignature();
  @override
  Future<Uint8List?> fetchSavedSignatureContent() async => null;
  @override
  Future<UserSignatureUploadResult> uploadSignature(Uint8List bytes) =>
      throw UnimplementedError();
}

/// Every send fails with "nothing answered", the shape a device with no usable network produces.
class _UnreachableApi implements ReportSubmitApiClient {
  const _UnreachableApi();
  @override
  Future<ReportAttachmentUploadResponse> uploadAttachment({
    required String reportId,
    required String localPath,
    required String fileName,
    required String contentType,
    String? kind,
    double? capturedLatitude,
    double? capturedLongitude,
    DateTime? capturedAt,
  }) async => throw _noResponse();
  @override
  Future<SubmitReportResponse> submitReport({
    required SubmitReportRequest request,
    required String idempotencyKey,
  }) async => throw _noResponse();
}

DioException _noResponse() => DioException(
  requestOptions: RequestOptions(path: '/api/reports/submit'),
  type: DioExceptionType.connectionError,
);

void main() {
  Future<void> pump(WidgetTester tester, {required bool online}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _reportId,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            title: 'T',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            submissionState: const Value('readyToSubmit'),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        userSignatureApiClientProvider.overrideWithValue(const _NoSignature()),
        reportEditorProvider(_reportId).overrideWith(
          (ref) => ReportEditorNotifier(
            initialState: const ReportEditorState(
              reportId: _reportId,
              tenantId: 'tenant-1',
              insertedUserId: 'user-1',
            ),
            repo: DraftReportRepository(db),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StepRiepilogo(reportId: _reportId))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  // Unmount and flush drift's zero-duration stream-close timer before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  /// A COMPLETE draft (everything `validateDraft` requires, no ticket so no signature), plus a
  /// real SubmissionQueue whose every send fails with "nothing answered" while the probe says the
  /// network is unreachable — i.e. the offline Invia of audit F25. `cachedOnline` is what the
  /// cached `isOnlineProvider` reports: true is the interesting case (interface up, no internet).
  Future<AppDatabase> pumpSubmittable(WidgetTester tester, {required bool cachedOnline}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _reportId,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            title: 'Rapportino completo',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            customerId: const Value('cust-1'),
            materialiNotRequired: const Value(true),
            submissionState: const Value('draft'),
            idempotencyKey: const Value('key-w'),
          ),
        );
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
    final repo = DraftReportRepository(db);
    final queue = SubmissionQueue(
      repo: repo,
      apiClient: const _UnreachableApi(),
      isOnline: () => cachedOnline,
      recheckOnline: () async => false,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(cachedOnline),
        userSignatureApiClientProvider.overrideWithValue(const _NoSignature()),
        realSubmissionQueueProvider.overrideWithValue(queue),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StepRiepilogo(reportId: _reportId))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    return db;
  }

  testWidgets('a queued row while offline says it is waiting for the connection', (tester) async {
    await pump(tester, online: false);
    expect(find.text('In attesa di connessione'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a queued row while online shows no waiting card', (tester) async {
    await pump(tester, online: true);
    expect(find.text('In attesa di connessione'), findsNothing);
    await unmount(tester);
  });

  // ── P0-7 (audit F25): a submit never fails for being offline ────────────────

  testWidgets('tapping Invia with nothing reachable shows the calm waiting card, not '
      '"Invio fallito", and leaves the row queued', (tester) async {
    final db = await pumpSubmittable(tester, cachedOnline: true);

    final invia = find.text('Invia rapporto di lavoro');
    expect(invia, findsOneWidget);
    await tester.ensureVisible(invia);
    await tester.pump();
    await tester.tap(invia);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('In attesa di connessione'), findsOneWidget);
    expect(find.text('Invio fallito'), findsNothing);
    // No red "Riprova invio" either: there is nothing for the technician to fix.
    expect(find.text('Riprova invio'), findsNothing);

    final row = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals(_reportId))).getSingle();
    expect(row.submissionState, 'readyToSubmit');
    expect(row.submissionError, isNull);
    expect(row.submissionAttempts, 0);

    await unmount(tester);
  });

  testWidgets('a real server rejection still surfaces as a failure', (tester) async {
    // The row is seeded already `failed`, the way the queue persists a 400 ("già in stato
    // Inviato"): the offline change must not swallow it.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _reportId,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            title: 'T',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            submissionState: const Value('failed'),
            submissionError: const Value('Il rapportino è già stato inviato.'),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        userSignatureApiClientProvider.overrideWithValue(const _NoSignature()),
        reportEditorProvider(_reportId).overrideWith(
          (ref) => ReportEditorNotifier(
            initialState: const ReportEditorState(
              reportId: _reportId,
              tenantId: 'tenant-1',
              insertedUserId: 'user-1',
            ),
            repo: DraftReportRepository(db),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StepRiepilogo(reportId: _reportId))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Invio fallito'), findsOneWidget);
    expect(find.text('Il rapportino è già stato inviato.'), findsOneWidget);
    await unmount(tester);
  });
}
