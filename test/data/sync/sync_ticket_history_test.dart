// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

/// A sync payload with every member the applier reads present and empty.
Map<String, dynamic> payload({
  List<Map<String, dynamic>> tickets = const [],
  List<Map<String, dynamic>>? history,
  Map<String, Object?>? scope,
}) => {
  'syncedAt': '2026-10-23T08:00:00Z',
  'since': null,
  'schedules': <Object>[],
  'draftReports': <Object>[],
  'submittedReports': <Object>[],
  'customers': <Object>[],
  'locations': <Object>[],
  'tickets': tickets,
  'ticketMateriali': <Object>[],
  'materiali': <Object>[],
  'materialiBarcodes': <Object>[],
  'cantieri': <Object>[],
  'ticketStatuses': <Object>[],
  'ticketTypes': <Object>[],
  'colleagues': <Object>[],
  // Absent entirely when the caller passes none, which is how an older backend's payload looks.
  'ticketHistory': ?history,
  if (scope != null) 'scope': scope,
};

Map<String, dynamic> ticketJson(String id) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-10-01T09:00:00Z',
  'title': 'Ticket $id',
  'customerId': 'cust-1',
  'locationId': 'loc-1',
  'statusId': 1,
  'typeId': 1,
};

Map<String, dynamic> historyJson(
  String id,
  String ticketId, {
  String field = 'StatusId',
  String? oldValue = '1',
  String? newValue = '4',
  String changedByUserId = 'user-1',
  String changedAt = '2026-10-23T07:30:00Z',
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'ticketId': ticketId,
  'fieldName': field,
  'oldValue': oldValue,
  'newValue': newValue,
  'changedByUserId': changedByUserId,
  'changedAt': changedAt,
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

  void respondWith(Map<String, dynamic> body) {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => ok(body));
  }

  Future<List<TicketHistoryData>> rows() => db.select(db.ticketHistory).get();

  Future<void> seedTicket(String id) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10),
          title: 'Ticket $id',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
        ),
      );

  group('SyncResultDto', () {
    test('reads the history member and marks the payload as carrying it', () {
      final dto = SyncResultDto.fromJson(
        payload(tickets: [ticketJson('t1')], history: [historyJson('h1', 't1')]),
      );

      expect(dto.carriesTicketHistory, isTrue);
      expect(dto.ticketHistory, hasLength(1));
      final row = dto.ticketHistory.single;
      expect(row.ticketId, 't1');
      expect(row.fieldName, 'StatusId');
      expect(row.oldValue, '1');
      expect(row.newValue, '4');
      expect(row.changedAt, DateTime.utc(2026, 10, 23, 7, 30));
    });

    test('an older backend that omits the member is distinguishable, not "no history"', () {
      final dto = SyncResultDto.fromJson(payload());

      expect(dto.carriesTicketHistory, isFalse);
      expect(dto.ticketHistory, isEmpty);
    });

    test('a system change keeps its empty actor rather than inventing one', () {
      final dto = SyncResultDto.fromJson(
        payload(
          tickets: [ticketJson('t1')],
          history: [historyJson('h1', 't1', changedByUserId: '')],
        ),
      );

      expect(dto.ticketHistory.single.changedByUserId, isEmpty);
    });
  });

  group('SyncService._applyTicketHistory', () {
    test('mirrors the rows raw, so the screen resolves them against its own maps', () async {
      respondWith(
        payload(
          tickets: [ticketJson('t1')],
          history: [
            historyJson('h1', 't1'),
            historyJson(
              'h2',
              't1',
              field: 'AssignedUserId',
              oldValue: null,
              newValue: '00000000-0000-0000-0000-000000000002',
              changedAt: '2026-10-23T07:45:00Z',
            ),
          ],
        ),
      );

      await svc.sync();

      final byId = {for (final r in await rows()) r.id: r};
      expect(byId.keys, unorderedEquals(['h1', 'h2']));
      expect(byId['h1']!.fieldName, 'StatusId');
      expect(byId['h1']!.oldValue, '1');
      expect(byId['h1']!.newValue, '4');
      expect(byId['h2']!.oldValue, isNull, reason: 'an assignment came from nothing');
      expect(
        byId['h2']!.newValue,
        '00000000-0000-0000-0000-000000000002',
        reason: 'a GUID stays the server\'s raw form; the screen names whoever it points at',
      );
    });

    test('a second sync upserts rather than duplicating, and carries what was appended', () async {
      respondWith(
        payload(tickets: [ticketJson('t1')], history: [historyJson('h1', 't1')]),
      );
      await svc.sync();

      // Same row again (the two-minute cursor overlap does this every time) plus one new change.
      respondWith(
        payload(
          tickets: [ticketJson('t1')],
          history: [historyJson('h1', 't1'), historyJson('h2', 't1', newValue: '5')],
        ),
      );
      await svc.sync();

      final all = await rows();
      expect(all, hasLength(2), reason: 'a re-sent row is not a second row');
      expect(all.map((r) => r.id), unorderedEquals(['h1', 'h2']));
    });

    test('a payload from an older backend leaves the mirrored timeline alone', () async {
      respondWith(
        payload(tickets: [ticketJson('t1')], history: [historyJson('h1', 't1')]),
      );
      await svc.sync();

      respondWith(payload(tickets: [ticketJson('t1')])); // no 'ticketHistory' key
      await svc.sync();

      expect((await rows()).single.id, 'h1');
    });

    test('a ticket that leaves scope takes its timeline with it', () async {
      await seedTicket('t1');
      await seedTicket('t2');
      respondWith(
        payload(
          tickets: [ticketJson('t1'), ticketJson('t2')],
          history: [historyJson('h1', 't1'), historyJson('h2', 't2')],
          scope: {'tickets': ['t1', 't2']},
        ),
      );
      await svc.sync();
      expect(await rows(), hasLength(2));

      // t2 is reassigned away: the manifest no longer lists it.
      respondWith(
        payload(
          tickets: [ticketJson('t1')],
          history: <Map<String, dynamic>>[],
          scope: {'tickets': ['t1']},
        ),
      );
      await svc.sync();

      expect(
        (await rows()).map((r) => r.id),
        ['h1'],
        reason: 'history follows the ticket manifest — it has no manifest of its own',
      );
    });

    test('a row for a ticket the mirror never held is swept rather than orphaned', () async {
      await seedTicket('t1');
      respondWith(
        payload(
          tickets: [ticketJson('t1')],
          history: [historyJson('h1', 't1'), historyJson('h-stray', 't-unknown')],
          scope: {'tickets': ['t1']},
        ),
      );

      await svc.sync();

      expect((await rows()).map((r) => r.id), ['h1']);
    });
  });

  group('the offline reader', () {
    test('returns this ticket\'s rows only', () async {
      await seedTicket('t1');
      await seedTicket('t2');
      respondWith(
        payload(
          tickets: [ticketJson('t1'), ticketJson('t2')],
          history: [historyJson('h1', 't1'), historyJson('h2', 't2')],
          scope: {'tickets': ['t1', 't2']},
        ),
      );
      await svc.sync();

      final read = await ReferenceCacheRepository(db).ticketHistoryFor('t1');
      expect(read.map((r) => r.id), ['h1']);
    });

    test('an untouched ticket reads empty, which the caller must not report as "no changes"',
        () async {
      await seedTicket('t1');
      respondWith(payload(tickets: [ticketJson('t1')], history: <Map<String, dynamic>>[]));
      await svc.sync();

      expect(await ReferenceCacheRepository(db).ticketHistoryFor('t1'), isEmpty);
    });
  });
}
