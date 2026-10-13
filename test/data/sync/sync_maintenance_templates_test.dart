import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

Map<String, dynamic> templateJson(
  String id, {
  String origin = 'System',
  String? name,
  bool isActive = true,
  int? latestPublishedVersion = 1,
}) => {
  'id': id,
  'origin': origin,
  'name': name ?? 'Modello $id',
  'description': null,
  'isActive': isActive,
  'latestPublishedVersion': latestPublishedVersion,
};

Map<String, dynamic> base({List<Map<String, dynamic>>? templates}) => {
  'syncedAt': '2026-10-08T08:00:00Z',
  'since': null,
  'customers': <Object>[],
  'tickets': <Object>[],
  // Absent entirely when the caller passes none, which is how an older backend's payload looks.
  'maintenanceTemplates': ?templates,
};

void main() {
  late AppDatabase db;
  late MockDio dio;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
  });
  tearDown(() => db.close());

  void respondWith(Map<String, dynamic> body) {
    when(
      () => dio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => ok(body));
  }

  Future<void> queueTicket(String id, {String? templateId}) => db
      .into(db.pendingTickets)
      .insert(
        PendingTicketsCompanion.insert(
          id: id,
          createdAt: DateTime.utc(2026, 10, 1),
          title: 'Ticket $id',
          customerId: 'cu1',
          locationId: 'l1',
          statusId: 1,
          typeId: 1,
          maintenanceTemplateId: Value(templateId),
        ),
      );

  test('a payload carrying the catalogue fills the local table', () async {
    respondWith(
      base(
        templates: [
          templateJson('t1', name: 'Caldaia'),
          templateJson('t2', origin: 'Tenant', name: 'Clima', latestPublishedVersion: null),
          templateJson('t3', name: 'Ritirato', isActive: false),
        ],
      ),
    );

    await SyncService(db: db, dio: dio).sync();

    final rows = {for (final r in await db.select(db.maintenanceTemplates).get()) r.id: r};
    expect(rows.keys, containsAll(['t1', 't2', 't3']));
    expect(rows['t1']!.name, 'Caldaia');
    expect(rows['t2']!.origin, 'Tenant');
    expect(rows['t2']!.latestPublishedVersion, isNull);
    // Inactive templates are carried, not filtered: the picker hides them, the mirror keeps them.
    expect(rows['t3']!.isActive, isFalse);
  });

  test('a payload that stops listing a template removes it (wholesale replace)', () async {
    respondWith(base(templates: [templateJson('t1'), templateJson('t2')]));
    await SyncService(db: db, dio: dio).sync();
    expect(await db.select(db.maintenanceTemplates).get(), hasLength(2));

    respondWith(base(templates: [templateJson('t1')]));
    await SyncService(db: db, dio: dio).sync();

    final ids = (await db.select(db.maintenanceTemplates).get()).map((r) => r.id);
    expect(ids, ['t1']);
  });

  /// An older backend omits the member entirely. That must NOT read as "every template was deleted":
  /// a device talking to a server that has not been upgraded keeps the catalogue it already has.
  test('a payload from an older backend leaves the catalogue alone', () async {
    respondWith(base(templates: [templateJson('t1')]));
    await SyncService(db: db, dio: dio).sync();

    respondWith(base()); // no 'maintenanceTemplates' key at all
    await SyncService(db: db, dio: dio).sync();

    expect((await db.select(db.maintenanceTemplates).get()).single.id, 't1');
  });

  /// The hazard this member exists to close: a queued ticket pinned to a template the server has
  /// since stopped offering would resend that id forever — a bad template id is a 400 with no field,
  /// so the create queue never classifies it repairable. Clearing the choice on the row lets the
  /// ticket resolve like any other unset pick.
  test('a queued ticket whose template left the catalogue has its choice cleared', () async {
    await queueTicket('q-stale', templateId: 'gone');
    await queueTicket('q-kept', templateId: 't1');

    respondWith(base(templates: [templateJson('t1')]));
    await SyncService(db: db, dio: dio).sync();

    final stale =
        await (db.select(db.pendingTickets)..where((t) => t.id.equals('q-stale'))).getSingle();
    final kept =
        await (db.select(db.pendingTickets)..where((t) => t.id.equals('q-kept'))).getSingle();

    expect(
      stale.maintenanceTemplateId,
      isNull,
      reason: 'a template the catalogue no longer offers must not stay pinned to a queued ticket',
    );
    expect(
      kept.maintenanceTemplateId,
      't1',
      reason: 'a choice that is still offered must survive the sync untouched',
    );
  });

  test('a queued ticket with no choice is left with none', () async {
    await queueTicket('q-none');

    respondWith(base(templates: [templateJson('t1')]));
    await SyncService(db: db, dio: dio).sync();

    final row = await (db.select(db.pendingTickets)..where((t) => t.id.equals('q-none')))
        .getSingle();
    expect(row.maintenanceTemplateId, isNull);
  });
}
