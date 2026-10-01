// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/import_server_report.dart';
import 'package:tasktap_mobile/data/reports/server_report_api_client.dart';
import 'package:tasktap_mobile/data/reports/server_report_dto.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import 'server_report_dto_test.dart' show backendFixture;

const _rid = '11111111-1111-1111-1111-111111111111';
const _tc1 = '99999999-9999-9999-9999-999999999999';
const _tc2 = '88888888-8888-8888-8888-888888888888';

class _FakeApi extends ServerReportApiClient {
  _FakeApi(this.json) : super(Dio());
  Map<String, dynamic> json;
  Object? error;
  int calls = 0;

  @override
  Future<ServerReportDto> fetchReport(String reportId) async {
    calls++;
    if (error != null) throw error!;
    return ServerReportDto.fromJson(json);
  }
}

void main() {
  late AppDatabase db;
  late DraftReportRepository repo;
  late _FakeApi api;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DraftReportRepository(db);
    api = _FakeApi(backendFixture());
  });
  tearDown(() => db.close());

  Future<void> run({
    String? cantiereId,
    bool overwriteLocal = false,
    Future<void> Function(String)? prefetchControls,
  }) => importServerReport(
    db: db,
    api: api,
    reportId: _rid,
    cantiereId: cantiereId,
    overwriteLocal: overwriteLocal,
    prefetchControls: prefetchControls,
  );

  test('writes the header with the server id, real tenant/location and diagnosi/soluzione', () async {
    await run(cantiereId: 'cantiere-1');

    final d = (await repo.getDraft(_rid))!;
    expect(d.tenantId, '22222222-2222-2222-2222-222222222222');
    expect(d.insertedUserId, '55555555-5555-5555-5555-555555555555');
    expect(d.locationId, '66666666-6666-6666-6666-666666666666');
    expect(d.ticketId, '33333333-3333-3333-3333-333333333333');
    expect(d.customerId, '44444444-4444-4444-4444-444444444444');
    expect(d.cantiereId, 'cantiere-1');
    expect(d.title, 'Sostituzione pompa');
    expect(d.details, 'Sostituita pompa; verificata tenuta');
    expect(d.diagnosi, 'Pompa bloccata');
    expect(d.soluzione, 'Sostituita');
    expect(d.customerSignoffText, 'Lavoro accettato');
    expect(d.stato, 'Bozza');
    expect(d.isLocalOnly, isTrue);
    expect(d.submissionState, 'draft');
  });

  test('replaces children: staff, materiali and controlli with the editor id convention', () async {
    await run();

    final staff = await repo.getStaff(_rid);
    expect(staff, hasLength(1));
    expect(staff.single.userId, '55555555-5555-5555-5555-555555555555');
    expect(staff.single.hoursWorked, 3.5);
    expect(staff.single.kmTraveled, 12);
    expect(staff.single.vehicle, 'Furgone');
    expect(staff.single.pauseMinutes, 15);
    expect(staff.single.tenantId, '22222222-2222-2222-2222-222222222222');

    final mats = await repo.getMateriali(_rid);
    expect(mats, hasLength(2));
    expect(
      mats.firstWhere((m) => m.materialeId != null).quantity,
      2.5,
    );
    expect(mats.firstWhere((m) => m.freeTextName == 'Guarnizione').notes, 'a misura');
    expect(mats.firstWhere((m) => m.materialeId != null).unitPrice, 10.0);

    final ctrls = await repo.getControlli(_rid);
    expect(ctrls.map((c) => c.id).toSet(), {'ctrl-$_rid-$_tc1', 'ctrl-$_rid-$_tc2'});
    expect(ctrls.firstWhere((c) => c.controlId == _tc1).boolValue, isTrue);
    expect(ctrls.firstWhere((c) => c.controlId == _tc2).numberValue, 4.2);
  });

  test('upgrades a header-only synced row and drops stale local children', () async {
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _rid,
            tenantId: 't',
            createdAt: DateTime.utc(2026, 10, 1),
            title: 'header sync',
            insertedUserId: 'u',
            locationId: 'l',
            metadataJson: const Value('{"gpsLatitude":1.5,"gpsLongitude":2.5}'),
          ),
        );
    await repo.upsertStaff(
      ReportStaffTableCompanion.insert(
        id: 'stale',
        tenantId: 't',
        createdAt: DateTime.utc(2026, 10, 1),
        reportId: _rid,
        userId: 'someone-else',
      ),
    );

    await run();

    expect((await repo.getStaff(_rid)).map((s) => s.userId), [
      '55555555-5555-5555-5555-555555555555',
    ]);
    final d = (await repo.getDraft(_rid))!;
    expect(d.title, 'Sostituzione pompa');
    expect(d.isLocalOnly, isTrue);
    // Local-only data the server does not hold survives the upsert.
    expect(d.metadataJson, contains('gpsLatitude'));
  });

  test('re-importing with overwriteLocal is idempotent (no duplicate rows)', () async {
    await run();
    await run(overwriteLocal: true);

    expect(await repo.getStaff(_rid), hasLength(1));
    expect(await repo.getMateriali(_rid), hasLength(2));
    expect(await repo.getControlli(_rid), hasLength(2));
    expect(await db.select(db.draftReports).get(), hasLength(1));
  });

  test('a local row already being edited is NOT overwritten by default, and no fetch happens', () async {
    await run();
    await (db.update(db.draftReports)..where((r) => r.id.equals(_rid))).write(
      const DraftReportsCompanion(diagnosi: Value('Modificato in locale')),
    );
    api.calls = 0;

    await run();

    expect(api.calls, 0);
    expect((await repo.getDraft(_rid))!.diagnosi, 'Modificato in locale');
  });

  test('fetch failure throws and writes nothing', () async {
    api.error = DioException(requestOptions: RequestOptions(path: '/x'));

    await expectLater(run(), throwsA(isA<DioException>()));

    expect(await repo.getDraft(_rid), isNull);
    expect(await repo.getStaff(_rid), isEmpty);
  });

  test('a server report that is no longer Bozza is refused, nothing written', () async {
    api.json = {...backendFixture(), 'stato': 1};

    await expectLater(run(), throwsA(isA<ServerReportNotEditableException>()));

    expect(await repo.getDraft(_rid), isNull);
  });

  test('prefetches the ticket checklist; a prefetch failure does not fail the import', () async {
    final seen = <String>[];
    await run(
      prefetchControls: (t) async {
        seen.add(t);
        throw StateError('offline');
      },
    );

    expect(seen, ['33333333-3333-3333-3333-333333333333']);
    expect(await repo.getDraft(_rid), isNotNull);
  });

  test('the editor hydrates the imported report and edits do not duplicate controls', () async {
    await run();

    final notifier = ReportEditorNotifier(
      initialState: const ReportEditorState(reportId: _rid),
      repo: repo,
    );
    await notifier.ready;

    expect(notifier.state.diagnosi, 'Pompa bloccata');
    expect(notifier.state.soluzione, 'Sostituita');
    expect(notifier.state.staffRows, hasLength(1));
    expect(notifier.state.materialeRows, hasLength(2));
    expect(notifier.state.controlloRows.map((c) => c.id).toSet(), {
      'ctrl-$_rid-$_tc1',
      'ctrl-$_rid-$_tc2',
    });
    expect(notifier.state.tenantId, '22222222-2222-2222-2222-222222222222');
    expect(notifier.state.locationId, '66666666-6666-6666-6666-666666666666');

    // Answering the same checklist item again (what the Controlli step does) uses the same row id.
    await notifier.upsertControllo(
      ControlloRow(
        id: 'ctrl-$_rid-$_tc1',
        reportId: _rid,
        controlId: _tc1,
        boolValue: false,
      ),
    );
    expect(await repo.getControlli(_rid), hasLength(2));

    // An unrelated autosave keeps diagnosi/soluzione and the server tenant.
    await notifier.setTitle('Nuovo titolo');
    final d = (await repo.getDraft(_rid))!;
    expect(d.diagnosi, 'Pompa bloccata');
    expect(d.tenantId, '22222222-2222-2222-2222-222222222222');
    notifier.dispose();
  });
}
