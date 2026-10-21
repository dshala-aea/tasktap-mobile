import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

/// O-8a/O-8b: the report aggregate reaches the device.
///
/// The payload used to carry report HEADERS only, so a report the technician did not author here
/// opened as a blank shell — Squadra, Materiali, Controlli and Foto all empty. These tests pin the
/// delivery, and as hard as the delivery they pin the two guards that make it safe:
///
///   • a locally-owned draft's children are never replaced (that is unsent work);
///   • the payload's own in-scope report set is the only authority to delete on — a report absent
///     from it is no evidence of anything, and a payload from an older backend is no evidence at
///     all.
class MockDio extends Mock implements Dio {}

const _absent = Object();

Response<Map<String, dynamic>> _ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

Map<String, dynamic> _scope(Map<String, Object?> ids) => {
  'schedules': null,
  'tickets': null,
  'locations': null,
  'customers': null,
  'cantieri': null,
  'agents': null,
  'draftReports': null,
  'submittedReports': null,
  'materiali': null,
  'materialiBarcodes': null,
  'strumenti': null,
  ...ids,
};

Map<String, dynamic> _payload({
  List<Map<String, dynamic>> draftReports = const [],
  Object? scope = _absent,
  Object? reportStaff = _absent,
  Object? reportMateriali = _absent,
  Object? reportControlli = _absent,
  Object? allegati = _absent,
  Object? reportVersions = _absent,
}) => {
  'syncedAt': '2026-10-21T08:00:00Z',
  'since': null,
  if (!identical(scope, _absent)) 'scope': scope,
  'schedules': <Object>[],
  'draftReports': draftReports,
  'submittedReports': <Object>[],
  'customers': <Object>[],
  'locations': <Object>[],
  'tickets': <Object>[],
  'ticketMateriali': <Object>[],
  'materiali': <Object>[],
  'materialiBarcodes': <Object>[],
  'cantieri': <Object>[],
  'ticketStatuses': <Object>[],
  'ticketTypes': <Object>[],
  'colleagues': <Object>[],
  if (!identical(reportStaff, _absent)) 'reportStaff': reportStaff,
  if (!identical(reportMateriali, _absent)) 'reportMateriali': reportMateriali,
  if (!identical(reportControlli, _absent)) 'reportControlli': reportControlli,
  if (!identical(allegati, _absent)) 'allegati': allegati,
  if (!identical(reportVersions, _absent)) 'reportVersions': reportVersions,
};

Map<String, dynamic> _staffJson(String id, String reportId) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-10-20T08:00:00Z',
  'reportId': reportId,
  'userId': 'user-1',
  'hoursWorked': 2.5,
  'kmTraveled': 12,
  'pauseMinutes': 15,
};

Map<String, dynamic> _materialeJson(String id, String reportId) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-10-20T08:00:00Z',
  'reportId': reportId,
  'freeTextName': 'Guarnizione',
  'quantity': 3,
};

Map<String, dynamic> _controlloJson(String id, String reportId) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-10-20T08:00:00Z',
  'reportId': reportId,
  'ticketControlId': 'tc-1',
  'boolValue': true,
  'note': 'ok',
};

Map<String, dynamic> _allegatoJson(
  String id, {
  required int entityType,
  required String entityId,
  bool isActive = true,
  int kind = 0,
  String? contentHash = 'abc123',
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-10-20T08:00:00Z',
  'entityType': entityType,
  'entityId': entityId,
  'fileName': '$id.jpg',
  'contentType': 'image/jpeg',
  'sizeBytes': 2048,
  'kind': kind,
  'uploadedByUserId': 'user-1',
  'isActive': isActive,
  'contentHash': contentHash,
};

Map<String, dynamic> _versionJson(String reportId, String version) => {
  'reportId': reportId,
  'version': version,
};

void main() {
  late AppDatabase db;
  late MockDio dio;
  late SyncService svc;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
    svc = SyncService(db: db, dio: dio);
  });

  tearDown(() => db.close());

  void respond(Map<String, dynamic> body) {
    when(
      () => dio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _ok(body));
  }

  Future<void> seedReport(
    String id, {
    bool isLocalOnly = false,
    String stato = 'Bozza',
  }) => db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 20),
          title: 'Rapportino $id',
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          stato: Value(stato),
          isLocalOnly: Value(isLocalOnly),
        ),
      );

  Future<void> seedStaffRow(String id, String reportId) => db
      .into(db.reportStaffTable)
      .insert(
        ReportStaffTableCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 20),
          reportId: reportId,
          userId: 'user-1',
        ),
      );

  Future<void> seedAllegato(
    String id, {
    required int entityType,
    required String entityId,
    bool isPendingUpload = false,
  }) => db
      .into(db.reportAllegati)
      .insert(
        ReportAllegatiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 20),
          fileName: '$id.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 10,
          storagePath: isPendingUpload ? '/tmp/$id.jpg' : 'https://old',
          url: isPendingUpload ? '/tmp/$id.jpg' : 'https://old',
          entityType: entityType,
          entityId: entityId,
          uploadedByUserId: 'user-1',
          isPendingUpload: Value(isPendingUpload),
        ),
      );

  Future<List<String>> staffIds(String reportId) async {
    final rows = await (db.select(
      db.reportStaffTable,
    )..where((r) => r.reportId.equals(reportId))).get();
    return rows.map((r) => r.id).toList();
  }

  test('children of an in-scope report land in the mirror', () async {
    await seedReport('r-1');
    respond(
      _payload(
        reportStaff: [_staffJson('s-1', 'r-1')],
        reportMateriali: [_materialeJson('m-1', 'r-1')],
        reportControlli: [_controlloJson('c-1', 'r-1')],
        reportVersions: [_versionJson('r-1', '42')],
      ),
    );

    await svc.sync();

    expect(await staffIds('r-1'), ['s-1']);
    final materiali = await db.select(db.reportMateriali).get();
    expect(materiali.single.freeTextName, 'Guarnizione');
    final controlli = await db.select(db.reportControlli).get();
    expect(controlli.single.controlId, 'tc-1');
    expect(controlli.single.note, 'ok');

    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('r-1'))).getSingle();
    expect(report.expectedVersion, '42');
  });

  test('a child the office deleted is removed, and only that report\'s', () async {
    await seedReport('r-1');
    await seedReport('r-2');
    await seedStaffRow('s-old', 'r-1');
    await seedStaffRow('s-keep', 'r-2');

    // r-1 is still in scope but has no staff line any more; r-2 is absent from the in-scope set
    // entirely, which is no evidence of a deletion.
    respond(
      _payload(
        reportStaff: const [],
        reportVersions: [_versionJson('r-1', '43')],
      ),
    );

    await svc.sync();

    expect(await staffIds('r-1'), isEmpty);
    expect(await staffIds('r-2'), ['s-keep']);
  });

  test('a locally-owned draft keeps its own children', () async {
    await seedReport('r-1', isLocalOnly: true);
    await seedStaffRow('s-local', 'r-1');

    respond(
      _payload(
        reportStaff: [_staffJson('s-server', 'r-1')],
        reportVersions: [_versionJson('r-1', '43')],
      ),
    );

    await svc.sync();

    expect(await staffIds('r-1'), ['s-local']);
    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('r-1'))).getSingle();
    // The imported copy's version is captured at import time and must survive a sync.
    expect(report.expectedVersion, isNull);
  });

  test('children of a report this device does not hold are not written', () async {
    respond(
      _payload(
        reportStaff: [_staffJson('s-1', 'r-missing')],
        reportVersions: [_versionJson('r-missing', '1')],
      ),
    );

    await svc.sync();

    expect(await staffIds('r-missing'), isEmpty);
  });

  test('a payload with no aggregate leaves the mirror untouched', () async {
    await seedReport('r-1');
    await seedStaffRow('s-old', 'r-1');

    respond(_payload());

    await svc.sync();

    expect(await staffIds('r-1'), ['s-old']);
  });

  test(
    'a report attachment lands with a fetchable url and no fake local path',
    () async {
      await seedReport('r-1');
      respond(
        _payload(
          allegati: [
            _allegatoJson('a-1', entityType: 1, entityId: 'r-1', kind: 1),
          ],
          reportVersions: [_versionJson('r-1', '1')],
        ),
      );

      await svc.sync();

      final rows = await db.select(db.reportAllegati).get();
      final a = rows.single;
      expect(a.id, 'a-1');
      expect(
        a.storagePath,
        isEmpty,
        reason: 'the bytes are on the server, not here',
      );
      expect(a.url, '/api/reports/r-1/attachments/a-1/content');
      expect(a.kind, 1);
      expect(a.contentHash, 'abc123');
      expect(a.isPendingUpload, isFalse);
    },
  );

  test('a capture still waiting to upload survives the replace', () async {
    await seedReport('r-1');
    await seedAllegato(
      'a-pending',
      entityType: 1,
      entityId: 'r-1',
      isPendingUpload: true,
    );

    respond(
      _payload(
        allegati: const [],
        reportVersions: [_versionJson('r-1', '1')],
      ),
    );

    await svc.sync();

    final rows = await db.select(db.reportAllegati).get();
    expect(rows.map((r) => r.id), ['a-pending']);
  });

  test('ticket attachments are pruned only against the ticket manifest', () async {
    await seedAllegato('t-1', entityType: 0, entityId: 'ticket-1');

    respond(_payload(allegati: const [], reportVersions: const []));
    await svc.sync();
    expect(
      (await db.select(db.reportAllegati).get()).map((r) => r.id),
      ['t-1'],
      reason: 'no manifest means no evidence that the ticket lost its files',
    );

    respond(
      _payload(
        scope: _scope({
          'tickets': ['ticket-1'],
        }),
        allegati: [_allegatoJson('t-2', entityType: 0, entityId: 'ticket-1')],
      ),
    );
    await svc.sync();
    expect((await db.select(db.reportAllegati).get()).map((r) => r.id), ['t-2']);
  });
}
