// A ticket timer's unsent change must survive a sync that still reports the session open.
//
// The failure this pins: the technician taps "Ferma" on a ticket. `TicketTimerRepository.stop`
// writes `endUtc` and marks the row pending; the server's copy stays open until the push lands.
// The delta sync runs on a 60 s foreground poll independent of that push, and the next payload
// carries the server's still-running row — same id, `endUtc: null`. The old apply path took it
// verbatim: `endUtc` back to null, `isPendingSync` back to false — which also removed the row from
// the push sweep, so the stop was lost for good. For a session born on this phone it was worse:
// the pending row was deleted before the server's open copy was inserted.
//
// The rule now: a row with an unsent change is never overwritten by the server's version of the
// same session. The push retries on reconnect, `markSynced` adopts the server's id and clears the
// flag, and the server's copy wins on the next sync once nothing is unsent — which is the last
// test here.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_repository.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> _ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

Map<String, dynamic> _workLogJson(
  String id, {
  String? clientId,
  String? endUtc,
  String ticketId = 'ticket-1',
}) => {
  'id': id,
  'tenantId': 'ten1',
  'ticketId': ticketId,
  'userId': 'user-1',
  'workDate': '2026-10-08',
  'startTime': '08:00:00',
  'endTime': endUtc == null ? null : '10:00:00',
  'startUtc': '2026-10-08T06:00:00Z',
  'endUtc': endUtc,
  'approvalStatus': 0,
  'description': null,
  'isManualEntry': false,
  'clientId': clientId,
  'createdAt': '2026-10-08T06:00:00Z',
  'updatedAt': '2026-10-08T06:00:00Z',
};

Map<String, dynamic> _base({List<Map<String, dynamic>>? ticketWorkLogs}) => {
  'syncedAt': '2026-10-08T09:00:00Z',
  'since': '2026-10-08T08:00:00Z',
  'customers': <Object>[],
  'tickets': <Object>[],
  'ticketWorkLogs': ?ticketWorkLogs,
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
    ).thenAnswer((_) async => _ok(body));
  }

  Future<List<TicketTimer>> rows() => db.select(db.ticketTimers).get();

  test('a stop queued on the phone is not reverted by a sync that still sees it open', () async {
    // The session was started online: the mirror holds the server's row, confirmed.
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'srv-1',
            ticketId: 'ticket-1',
            userId: const Value('user-1'),
            workDate: Value(DateTime.utc(2026, 10, 8)),
            startSeconds: const Value(28800),
            startUtc: Value(DateTime.utc(2026, 10, 8, 6)),
          ),
        );

    // Offline, the technician stops it: endUtc set, row pending.
    final stopped = await TicketTimerRepository(db).stop('ticket-1');
    expect(stopped, isNotNull);
    expect(stopped!.endUtc, isNotNull);

    // A sync overtakes the push and the server's copy is still running.
    respondWith(
      _base(
        ticketWorkLogs: [_workLogJson('srv-1')],
      ),
    );
    await SyncService(db: db, dio: dio).sync();

    final row = (await rows()).single;
    expect(
      row.endUtc,
      isNotNull,
      reason: 'the server row would have overwritten the unsent stop with null',
    );
    expect(
      row.isPendingSync,
      isTrue,
      reason: 'clearing the flag drops the row out of the push sweep, losing the stop',
    );
  });

  test('a phone-born session is not duplicated or deleted while its start is unsent', () async {
    final started = await TicketTimerRepository(db).start(
      ticketId: 'ticket-1',
      userId: 'user-1',
    );

    // The server acknowledged the start (so it knows the clientId) but the push has not come back
    // yet; the mirror still holds only the local uuid row, marked pending.
    respondWith(
      _base(
        ticketWorkLogs: [_workLogJson('srv-1', clientId: started.id)],
      ),
    );
    await SyncService(db: db, dio: dio).sync();

    final all = await rows();
    expect(all, hasLength(1), reason: 'one session, not a local copy plus a server copy');
    expect(all.single.id, started.id);
    expect(all.single.isPendingSync, isTrue);
  });

  test('once nothing is unsent the server copy wins, end included', () async {
    // `markSynced` has run: confirmed row, same id the server uses.
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'srv-1',
            clientId: const Value('srv-1'),
            ticketId: 'ticket-1',
            userId: const Value('user-1'),
            workDate: Value(DateTime.utc(2026, 10, 8)),
            startSeconds: const Value(28800),
            startUtc: Value(DateTime.utc(2026, 10, 8, 6)),
          ),
        );

    respondWith(
      _base(
        ticketWorkLogs: [_workLogJson('srv-1', clientId: 'srv-1', endUtc: '2026-10-08T08:00:00Z')],
      ),
    );
    await SyncService(db: db, dio: dio).sync();

    final row = (await rows()).single;
    expect(row.endUtc?.toUtc(), DateTime.utc(2026, 10, 8, 8));
    expect(row.isPendingSync, isFalse);
  });
}
