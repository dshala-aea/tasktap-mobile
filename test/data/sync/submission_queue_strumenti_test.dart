// dart format width=100
// The submit body carries the Strumenti selection: strumentoId + expiredAcknowledged only, the
// acknowledgement forced to match the local expiry verdict, nothing when the step was never used.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';

class _MockApi extends Mock implements ReportSubmitApiClient {}

class _FakeRequest extends Fake implements SubmitReportRequest {}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(_FakeRequest());
  });

  late AppDatabase db;
  late _MockApi api;
  late SubmissionQueue queue;
  SubmitReportRequest? sent;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = _MockApi();
    queue = SubmissionQueue(repo: DraftReportRepository(db), apiClient: api);
    sent = null;
    when(
      () => api.submitReport(
        request: any(named: 'request'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((inv) async {
      sent = inv.namedArguments[#request] as SubmitReportRequest;
      return const SubmitReportResponse(id: 'r1', title: 't', stato: '1', inviatoAt: null);
    });
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'r1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 6, 22, 12),
            title: 'Titolo',
            insertedUserId: 'u1',
            locationId: 'loc-1',
            startedAt: Value(DateTime.utc(2026, 6, 22, 12)),
            isLocalOnly: const Value(true),
            submissionState: const Value('readyToSubmit'),
            idempotencyKey: const Value('k1'),
          ),
        );
    await db
        .into(db.reportStaffTable)
        .insert(
          ReportStaffTableCompanion.insert(
            id: 's1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 1, 1),
            reportId: 'r1',
            userId: 'u1',
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> localRow(
    String id,
    String? expiry, {
    bool ack = false,
    String? usage,
    String? outcome,
  }) => db
      .into(db.reportStrumenti)
      .insert(
        ReportStrumentiCompanion.insert(
          id: 'str-r1-$id',
          reportId: 'r1',
          strumentoId: Value(id),
          name: 'N-$id',
          matricola: 'M-$id',
          calibrationExpiry: Value(expiry),
          expiredAcknowledged: Value(ack),
          expiredAtUse: const Value(true), // server-side display value: must never be sent
          usageDescription: Value(usage),
          outcome: Value(outcome),
          isLocal: const Value(true),
        ),
      );

  test('sends the selection: ack kept for expired, forced false for valid, no expiredAtUse', () async {
    await localRow('valid', '2027-01-01', ack: true); // stale ack on a valid instrument
    await localRow('expired', '2026-01-01', ack: true);
    await localRow('expired-unacked', '2026-02-02');
    await localRow('noexpiry', null);

    await queue.processAll();

    final body = {for (final s in sent!.strumenti) s.strumentoId: s.expiredAcknowledged};
    expect(body, {
      'valid': false,
      'expired': true,
      'expired-unacked': false,
      'noexpiry': false,
    });
    final json = sent!.toJson()['strumenti'] as List;
    expect(json, hasLength(4));
    for (final j in json) {
      expect((j as Map).keys.toSet(), {'strumentoId', 'expiredAcknowledged'});
    }
  });

  test('catalogue expiry beats the stale snapshot on the row (recalibrated instrument)', () async {
    await localRow('recal', '2026-01-01', ack: true); // snapshot says expired
    await db
        .into(db.strumenti)
        .insert(
          StrumentiCompanion.insert(
            id: 'recal',
            name: 'N',
            matricola: 'M',
            calibrationExpiry: const Value('2027-05-05'), // recalibrated since
          ),
        );

    await queue.processAll();

    expect(sent!.strumenti.single.expiredAcknowledged, isFalse);
  });

  test('server-origin rows are never sent; a draft without a local selection sends []', () async {
    await db
        .into(db.reportStrumenti)
        .insert(
          ReportStrumentiCompanion.insert(
            id: 'srv',
            reportId: 'r1',
            strumentoId: const Value('x'),
            name: 'X',
            matricola: 'X',
          ),
        );

    await queue.processAll();

    expect(sent!.strumenti, isEmpty);
  });

  test('the notes are sent only when non-blank, trimmed; blank ones are omitted', () async {
    await localRow('both', null, usage: '  Misura sul quadro B ', outcome: 'Conforme');
    await localRow('usage-only', null, usage: 'Solo utilizzo');
    await localRow('blank', null, usage: '   ', outcome: '');
    await localRow('none', null);

    await queue.processAll();

    final byId = {
      for (final j in sent!.toJson()['strumenti'] as List)
        (j as Map)['strumentoId'] as String: j.cast<String, dynamic>(),
    };
    expect(byId['both']!['usageDescription'], 'Misura sul quadro B');
    expect(byId['both']!['outcome'], 'Conforme');
    expect(byId['usage-only']!.containsKey('outcome'), isFalse);
    expect(byId['usage-only']!['usageDescription'], 'Solo utilizzo');
    expect(byId['blank']!.keys.toSet(), {'strumentoId', 'expiredAcknowledged'});
    expect(byId['none']!.keys.toSet(), {'strumentoId', 'expiredAcknowledged'});
  });
}
