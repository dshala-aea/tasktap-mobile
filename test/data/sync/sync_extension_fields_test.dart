// Covers the P2-7 half of the sync: the tenant's custom-field definitions ("campi aggiuntivi") and
// the per-entity `extensionValues` the server has always sent inside each ticket/cantiere/report.
//
// The definitions member travels whole on every sync (no delta filter — a deactivated field has no
// change marker of its own), so the mirror is replaced wholesale. The three replace semantics that
// matter and that an upsert would get wrong are pinned here: a field the server stopped listing must
// disappear, an older backend (no member at all) must not look like "every field was deleted", and a
// carried-but-empty list is the no-permission case, not an empty tenant.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
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

Map<String, dynamic> definitionJson(
  String id, {
  String entityType = 'ticket',
  String fieldType = 'text',
  String? options,
  String? unit,
  String? defaultValue,
  String? placeholder,
  bool isRequired = false,
  bool showInCard = false,
  int sortOrder = 0,
}) => {
  'id': id,
  'key': 'key-$id',
  'label': 'Campo $id',
  'entityType': entityType,
  'fieldType': fieldType,
  'isRequired': isRequired,
  'showInList': false,
  'showInCard': showInCard,
  'sortOrder': sortOrder,
  'options': options,
  'unit': unit,
  'defaultValue': defaultValue,
  'placeholder': placeholder,
};

Map<String, dynamic> ticketJson(String id, {String? extensionValues}) => {
  'id': id,
  'tenantId': 'ten1',
  'createdAt': '2026-10-01T08:00:00Z',
  'title': 'Ticket $id',
  'customerId': 'cu1',
  'locationId': 'loc1',
  'statusId': 1,
  'typeId': 1,
  'extensionValues': ?extensionValues,
};

Map<String, dynamic> cantiereJson(String id, {String? extensionValues}) => {
  'id': id,
  'tenantId': 'ten1',
  'createdAt': '2026-10-01T08:00:00Z',
  'name': 'Cantiere $id',
  'status': 'Active',
  'extensionValues': ?extensionValues,
};

Map<String, dynamic> reportJson(String id, {String? extensionValues}) => {
  'id': id,
  'tenantId': 'ten1',
  'createdAt': '2026-10-01T08:00:00Z',
  'title': 'Rapportino $id',
  'insertedUserId': 'u1',
  'locationId': 'loc1',
  'stato': 'Bozza',
  'extensionValues': ?extensionValues,
};

/// A payload with everything optional left out; callers add only the member under test, so an
/// absent member always means "an older backend", never "an empty collection I forgot to fill".
Map<String, dynamic> base({List<Map<String, dynamic>>? definitions}) => {
  'syncedAt': '2026-10-08T08:00:00Z',
  'since': null,
  'customers': <Object>[],
  'tickets': <Object>[],
  'extensionFieldDefinitions': ?definitions,
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
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => ok(body));
  }

  Future<List<ExtensionFieldDefinition>> mirrors() =>
      (db.select(db.extensionFieldDefinitions)..orderBy([(d) => OrderingTerm.asc(d.id)])).get();

  test('a payload carrying the definitions fills the local mirror', () async {
    respondWith(
      base(definitions: [definitionJson('d1'), definitionJson('d2', entityType: 'cantiere')]),
    );

    await SyncService(db: db, dio: dio).sync();

    final rows = await mirrors();
    expect(rows.map((r) => r.id), ['d1', 'd2']);
    expect(rows.map((r) => r.entityType), ['ticket', 'cantiere']);
  });

  test('every render-affecting member survives the round trip', () async {
    respondWith(
      base(
        definitions: [
          definitionJson(
            'd1',
            entityType: 'report',
            fieldType: 'select',
            options: '["Rosso","Verde"]',
            unit: 'kg',
            defaultValue: 'Verde',
            placeholder: 'Scegli…',
            isRequired: true,
            showInCard: true,
            sortOrder: 7,
          ),
        ],
      ),
    );

    await SyncService(db: db, dio: dio).sync();

    final row = (await mirrors()).single;
    expect(row.key, 'key-d1');
    expect(row.label, 'Campo d1');
    expect(row.entityType, 'report');
    expect(row.fieldType, 'select');
    expect(row.options, '["Rosso","Verde"]');
    expect(row.unit, 'kg');
    expect(row.defaultValue, 'Verde');
    expect(row.placeholder, 'Scegli…');
    expect(row.isRequired, isTrue);
    expect(row.showInCard, isTrue);
    expect(row.sortOrder, 7);
  });

  test('a payload that stops listing a definition removes it (wholesale replace)', () async {
    respondWith(base(definitions: [definitionJson('d1'), definitionJson('d2')]));
    await SyncService(db: db, dio: dio).sync();
    expect(await mirrors(), hasLength(2));

    respondWith(base(definitions: [definitionJson('d1')]));
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).map((r) => r.id), ['d1']);
  });

  /// A field the admin deactivated server-side stops being sent at all — it has no change marker, so
  /// an upsert would leave it on the device forever. This is the case the wholesale replace exists
  /// for, and it is the one a delta sync can never signal on its own.
  test('a deactivated field disappears on the next sync', () async {
    respondWith(base(definitions: [definitionJson('d1'), definitionJson('d2')]));
    await SyncService(db: db, dio: dio).sync();

    respondWith(base(definitions: [definitionJson('d2')]));
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).map((r) => r.id), ['d2']);
  });

  test('a payload from an older backend leaves the mirror alone', () async {
    respondWith(base(definitions: [definitionJson('d1')]));
    await SyncService(db: db, dio: dio).sync();

    respondWith(base()); // no 'extensionFieldDefinitions' key at all
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).single.id, 'd1');
  });

  /// The server assigns the collection unconditionally, so an empty list can only mean "this caller
  /// may not read any entity type's definitions" (the per-type gate in SyncController). Pruning on it
  /// would blank the section the moment a technician's permissions changed.
  test('a carried-but-empty list is the no-permission case and does not prune', () async {
    respondWith(base(definitions: [definitionJson('d1')]));
    await SyncService(db: db, dio: dio).sync();

    respondWith(base(definitions: []));
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).single.id, 'd1');
  });

  /// The values path: these were already inside each entity on the wire, but had nowhere to land
  /// before schema 46 — so offline the "Altri campi" section rendered its definitions with every
  /// field blank. The three columns are filled by the same upsert that writes the rest of the entity.
  test('extensionValues land on the ticket, cantiere and report rows', () async {
    respondWith({
      'syncedAt': '2026-10-08T08:00:00Z',
      'since': null,
      'customers': <Object>[],
      'tickets': [
        ticketJson('tk1', extensionValues: '{"zona":"Nord","priorita":3}'),
      ],
      'cantieri': [cantiereJson('ca1', extensionValues: '{"meteo":"pioggia"}')],
      'draftReports': [reportJson('rp1', extensionValues: '{"rif":"A-12"}')],
    });

    await SyncService(db: db, dio: dio).sync();

    expect(
      (await db.select(db.tickets).getSingle()).extensionValues,
      '{"zona":"Nord","priorita":3}',
    );
    expect((await db.select(db.cantieri).getSingle()).extensionValues, '{"meteo":"pioggia"}');
    expect((await db.select(db.draftReports).getSingle()).extensionValues, '{"rif":"A-12"}');
  });

  /// Null must stay null rather than becoming `'{}'`: "this entity has no custom-field values" is
  /// not the same statement as "it has an empty value set", and only the first can be told apart from
  /// "never synced" without a row to compare.
  test('an entity with no values keeps a null column', () async {
    respondWith({
      'syncedAt': '2026-10-08T08:00:00Z',
      'since': null,
      'customers': <Object>[],
      'tickets': [ticketJson('tk1')],
      'cantieri': [cantiereJson('ca1')],
      'draftReports': [reportJson('rp1')],
    });

    await SyncService(db: db, dio: dio).sync();

    expect((await db.select(db.tickets).getSingle()).extensionValues, isNull);
    expect((await db.select(db.cantieri).getSingle()).extensionValues, isNull);
    expect((await db.select(db.draftReports).getSingle()).extensionValues, isNull);
  });
}
