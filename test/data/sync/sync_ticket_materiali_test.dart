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

Map<String, dynamic> ticketJson(String id) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'title': 'Ticket $id',
  'customerId': 'cust-1',
  'locationId': 'loc-1',
  'assignedUserId': 'user-1',
  'statusId': 1,
  'typeId': 1,
};

Map<String, dynamic> materialeJson(String id, String ticketId, {double quantity = 1}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'ticketId': ticketId,
  'materialeId': null,
  'freeTextName': 'Voce $id',
  'quantity': quantity,
  'unitOfMeasure': 'pz',
  'notes': null,
  'isAvailable': false,
};

/// Absent entirely when the caller passes none, which is how an older backend's payload looks.
Map<String, dynamic> base({
  required List<Map<String, dynamic>> tickets,
  List<Map<String, dynamic>>? materiali,
}) => {
  'syncedAt': '2026-10-21T08:00:00Z',
  'since': null,
  'customers': <Object>[],
  'tickets': tickets,
  'ticketMateriali': ?materiali,
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

  Future<List<String>> mirroredIds({String? ticketId}) async {
    final query = db.select(db.ticketMateriali);
    if (ticketId != null) {
      query.where((m) => m.ticketId.equals(ticketId));
    }
    final rows = await query.get();
    return rows.map((r) => r.id).toList()..sort();
  }

  /// The bug this member exists to close: `PUT /api/Tickets/{id}/materiali` deletes every row and
  /// re-inserts, so an edited item comes back with a NEW id. Upserting by id treated the
  /// replacements as additions, and after two office edits the technician saw the list twice over.
  test('an edited fabbisogno replaces the old rows instead of doubling them', () async {
    respondWith(
      base(
        tickets: [ticketJson('ticket-1')],
        materiali: [
          materialeJson('m-old-1', 'ticket-1', quantity: 2),
          materialeJson('m-old-2', 'ticket-1'),
        ],
      ),
    );
    await SyncService(db: db, dio: dio).sync();
    expect(await mirroredIds(), ['m-old-1', 'm-old-2']);

    // The office saved the same two lines again: same content, brand-new server ids.
    respondWith(
      base(
        tickets: [ticketJson('ticket-1')],
        materiali: [
          materialeJson('m-new-1', 'ticket-1', quantity: 3),
          materialeJson('m-new-2', 'ticket-1'),
        ],
      ),
    );
    await SyncService(db: db, dio: dio).sync();

    expect(
      await mirroredIds(),
      ['m-new-1', 'm-new-2'],
      reason: 'the old ids must be gone, or the tab shows every office edit in addition to the last one',
    );
    final rows = await db.select(db.ticketMateriali).get();
    expect(rows.firstWhere((r) => r.id == 'm-new-1').quantity, 3);
  });

  /// A fabbisogno emptied in the office sends no material rows at all. Replacing against the
  /// tickets in the payload — not against the tickets that have rows — is what lets the stale
  /// rows go: there is no incoming row to delete anything by.
  test('a fabbisogno cleared in the office empties the mirror for that ticket', () async {
    respondWith(
      base(
        tickets: [ticketJson('ticket-1')],
        materiali: [materialeJson('m-1', 'ticket-1'), materialeJson('m-2', 'ticket-1')],
      ),
    );
    await SyncService(db: db, dio: dio).sync();
    expect(await mirroredIds(), ['m-1', 'm-2']);

    respondWith(base(tickets: [ticketJson('ticket-1')], materiali: <Map<String, dynamic>>[]));
    await SyncService(db: db, dio: dio).sync();

    expect(await mirroredIds(), isEmpty);
  });

  /// Silence is not a deletion: a ticket the payload does not carry keeps the rows it already has.
  test('a ticket absent from the payload keeps its rows', () async {
    respondWith(
      base(
        tickets: [ticketJson('ticket-1'), ticketJson('ticket-2')],
        materiali: [materialeJson('m-1', 'ticket-1'), materialeJson('m-2', 'ticket-2')],
      ),
    );
    await SyncService(db: db, dio: dio).sync();

    respondWith(
      base(
        tickets: [ticketJson('ticket-1')],
        materiali: [materialeJson('m-1b', 'ticket-1')],
      ),
    );
    await SyncService(db: db, dio: dio).sync();

    expect(await mirroredIds(), ['m-1b', 'm-2']);
    expect(await mirroredIds(ticketId: 'ticket-2'), ['m-2']);
  });

  test('a payload from an older backend leaves the fabbisogno alone', () async {
    respondWith(
      base(
        tickets: [ticketJson('ticket-1')],
        materiali: [materialeJson('m-1', 'ticket-1')],
      ),
    );
    await SyncService(db: db, dio: dio).sync();
    expect(await mirroredIds(), ['m-1']);

    respondWith(base(tickets: [ticketJson('ticket-1')])); // no 'ticketMateriali' key at all
    await SyncService(db: db, dio: dio).sync();

    expect(
      await mirroredIds(),
      ['m-1'],
      reason: 'an older backend must not look like "every fabbisogno was cleared"',
    );
  });
}
