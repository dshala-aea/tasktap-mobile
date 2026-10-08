import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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

Map<String, dynamic> base() => {
  'syncedAt': '2026-10-07T08:00:00Z',
  'since': null,
  'tickets': [
    {
      'id': 't1', 'tenantId': 'x', 'createdAt': '2026-10-01T00:00:00Z', 'title': 'Caldaie',
      'customerId': 'c', 'locationId': 'l', 'statusId': 1, 'typeId': 1,
    },
  ],
};

Map<String, dynamic> checklist() => {
  'controlGroups': [
    {'id': 'g1', 'parentGroupId': null, 'maintenanceTemplateVersionId': 'v1', 'name': 'Sicurezza', 'sortOrder': 0},
  ],
  'ticketControls': [
    {
      'id': 'c1', 'ticketId': 't1', 'prodottoAssistenzaId': 'a1', 'templateControlId': 'tc1',
      'controlLineageId': 'l1', 'groupId': 'g1', 'label': 'Valvola chiusa', 'description': null,
      'type': 'Checkbox', 'isRequired': true, 'options': null, 'sortOrder': 0, 'status': 'Pending',
      'stringValue': null, 'boolValue': null, 'dateValue': null, 'numberValue': null, 'note': null,
    },
  ],
  'ticketAssets': [
    {'ticketId': 't1', 'prodottoAssistenzaId': 'a1', 'controllato': false, 'note': null, 'maintenanceTemplateVersionId': 'v1'},
  ],
  'assets': [
    {'id': 'a1', 'name': 'Caldaia Nord', 'serialNumber': null, 'matricola': 'M-77', 'librettoIds': <String>[]},
  ],
  'strumenti': [
    {'id': 's1', 'name': 'Multimetro', 'matricola': 'M1', 'calibrationExpiry': '2026-12-31', 'certificateReference': null, 'isMine': true},
  ],
  'reportStrumenti': <Object>[],
  'checklistTruncated': false,
  'checklistOmittedTicketIds': <String>[],
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
    when(() => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok(body));
  }

  test('a payload with the checklist members fills the local mirror in the same sync', () async {
    respondWith({...base(), ...checklist()});
    await SyncService(db: db, dio: dio).sync();

    expect((await db.select(db.ticketControls).get()).single.label, 'Valvola chiusa');
    expect((await db.select(db.assets).get()).single.matricola, 'M-77');
    expect((await db.select(db.strumenti).get()).single.isMine, isTrue);
  });

  test('the cursor generation is v9, so every device does one full sync after this upgrade', () {
    expect(AppDatabase.syncCursorGeneration, 'v9');
  });

  /// An older backend omits the new members entirely. That must NOT read as "every checklist is
  /// empty": a reconcile would wipe the cache of a device that is simply talking to a server that
  /// has not been upgraded (or an old reverse-proxy cache).
  test('a payload from an older backend leaves every cached row alone', () async {
    respondWith({...base(), ...checklist()});
    await SyncService(db: db, dio: dio).sync();

    respondWith(base()); // no ticketControls / strumenti keys at all
    await SyncService(db: db, dio: dio).sync();

    expect(await db.select(db.ticketControls).get(), hasLength(1));
    expect(await db.select(db.ticketAssets).get(), hasLength(1));
    expect(await db.select(db.strumenti).get(), hasLength(1));
  });

  test('omitted ticket ids are remembered and the ticket row still lands', () async {
    respondWith({
      ...base(),
      'controlGroups': <Object>[],
      'ticketControls': <Object>[],
      'ticketAssets': <Object>[],
      'assets': <Object>[],
      'strumenti': <Object>[],
      'reportStrumenti': <Object>[],
      'checklistTruncated': true,
      'checklistOmittedTicketIds': ['t1'],
    });
    await SyncService(db: db, dio: dio).sync();

    expect((await db.select(db.tickets).get()).map((t) => t.id), ['t1']);
    expect((await db.select(db.checklistOmittedTickets).get()).map((o) => o.ticketId), ['t1']);
  });
}
