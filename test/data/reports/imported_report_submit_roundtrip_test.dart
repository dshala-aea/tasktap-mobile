// dart format width=100
// Editing an imported row must not lose server-set fields the editor does not expose
// (StaffRow has no costPerKm, MaterialeRow no unitPrice). The editor writes children with an
// upsert whose companion omits those columns, so Drift keeps them; a future delete-and-reinsert
// of child rows would silently zero them and, because submit REPLACES children, wipe them on the
// server. These tests pin that through the real request builder.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/import_server_report.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/server_report_api_client.dart';
import 'package:tasktap_mobile/data/reports/server_report_dto.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import 'server_report_dto_test.dart' show backendFixture;

class _Api extends ServerReportApiClient {
  _Api() : super(Dio());
  @override
  Future<ServerReportDto> fetchReport(String id) async => ServerReportDto.fromJson(backendFixture());
}

class _MockSubmit extends Mock implements ReportSubmitApiClient {}

class _FakeReq extends Fake implements SubmitReportRequest {}

void main() {
  const rid = '11111111-1111-1111-1111-111111111111';

  test('editing imported staff/material rows keeps costPerKm and unitPrice in the submit request',
      () async {
    registerFallbackValue(_FakeReq());
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DraftReportRepository(db);
    await importServerReport(db: db, api: _Api(), reportId: rid);

    final notifier = ReportEditorNotifier(
      initialState: const ReportEditorState(reportId: rid),
      repo: repo,
    );
    await notifier.ready;
    final staff = notifier.state.staffRows.single;
    await notifier.updateStaff(
      StaffRow(id: staff.id, userId: staff.userId, hoursWorked: 5, kmTraveled: 20),
    );
    final mat = notifier.state.materialeRows.firstWhere((m) => m.materialeId != null);
    await notifier.updateMateriale(
      MaterialeRow(
        id: mat.id,
        reportId: rid,
        materialeId: mat.materialeId,
        quantity: 7,
        unitOfMeasure: mat.unitOfMeasure,
      ),
    );
    notifier.dispose();

    // Make the draft submittable for the queue.
    await (db.update(db.draftReports)..where((r) => r.id.equals(rid))).write(
      const DraftReportsCompanion(
        submissionState: Value('readyToSubmit'),
        idempotencyKey: Value('k'),
      ),
    );
    final api = _MockSubmit();
    SubmitReportRequest? sent;
    when(
      () => api.submitReport(
        request: any(named: 'request'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((inv) async {
      sent = inv.namedArguments[#request] as SubmitReportRequest;
      return const SubmitReportResponse(id: rid, title: 't', stato: '1', inviatoAt: null);
    });

    await SubmissionQueue(repo: repo, apiClient: api).processAll();

    expect(sent, isNotNull);
    expect(sent!.staff.single.hoursWorked, 5);
    expect(sent!.staff.single.costPerKm, 0.4);
    final sentMat = sent!.materiali.firstWhere((m) => m.materialeId != null);
    expect(sentMat.quantity, 7);
    expect(sentMat.unitPrice, 10.0);
    expect(sent!.toJson()['diagnosi'], 'Pompa bloccata');
    // Not carried by the phone: the backend must keep these when null (see report).
    expect(sent!.toJson().containsKey('customerSignatureAllegatoId'), isFalse);
  });
}
