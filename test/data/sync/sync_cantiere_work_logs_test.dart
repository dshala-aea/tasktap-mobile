// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
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
  List<Map<String, dynamic>>? workLogs,
  Map<String, Object?>? scope,
}) => {
  'syncedAt': '2026-10-23T08:00:00Z',
  'since': null,
  'schedules': <Object>[],
  'draftReports': <Object>[],
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
  // Absent entirely when the caller passes none, which is how an older backend's payload looks.
  'cantiereWorkLogs': ?workLogs,
  'scope': ?scope,
};

Map<String, dynamic> workLogJson(
  String id, {
  String cantiereId = 'site-1',
  String userId = 'user-1',
  String? ticketId,
  String workDate = '2026-10-22',
  String? startTime = '08:00:00',
  String? endTime = '12:30:00',
  String? startUtc = '2026-10-22T06:00:00Z',
  String? endUtc = '2026-10-22T10:30:00Z',
  int workLogType = 0,
  int approvalStatus = 2,
  String? description,
  String? clientId,
  String createdAt = '2026-10-22T06:00:00Z',
  String? updatedAt,
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'cantiereId': cantiereId,
  'userId': userId,
  'ticketId': ticketId,
  'workDate': workDate,
  'startTime': startTime,
  'endTime': endTime,
  'startUtc': startUtc,
  'endUtc': endUtc,
  'workLogType': workLogType,
  'approvalStatus': approvalStatus,
  'description': description,
  'clientId': clientId,
  'createdAt': createdAt,
  'updatedAt': updatedAt,
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

  Future<List<CantiereWorkLog>> rows() => db.select(db.cantiereWorkLogs).get();

  group('SyncCantiereWorkLogDto', () {
    test('reads the member, marks the payload as carrying it, and keeps the raw values', () {
      final dto = SyncResultDto.fromJson(
        payload(
          workLogs: [
            workLogJson(
              'w1',
              ticketId: 't1',
              workLogType: 1,
              approvalStatus: 3,
              description: 'Viaggio andata',
              clientId: 'device-key-1',
            ),
          ],
        ),
      );

      expect(dto.carriesCantiereWorkLogs, isTrue);
      final row = dto.cantiereWorkLogs.single;
      expect(row.cantiereId, 'site-1');
      expect(row.userId, 'user-1');
      expect(row.ticketId, 't1');
      expect(row.workDate, DateTime.utc(2026, 10, 22));
      expect(row.startTime, const Duration(hours: 8));
      expect(row.endTime, const Duration(hours: 12, minutes: 30));
      expect(row.startUtc, DateTime.utc(2026, 10, 22, 6));
      expect(row.endUtc, DateTime.utc(2026, 10, 22, 10, 30));
      expect(row.workLogType, 1);
      expect(row.approvalStatus, 3);
      expect(row.clientId, 'device-key-1');
    });

    test('an older backend that omits the member is distinguishable, not "no shifts"', () {
      final dto = SyncResultDto.fromJson(payload());

      expect(dto.carriesCantiereWorkLogs, isFalse);
      expect(dto.cantiereWorkLogs, isEmpty);
    });

    test('a legacy row with no instants and no clock-out keeps both as absent', () {
      final dto = SyncResultDto.fromJson(
        payload(
          workLogs: [workLogJson('w1', endTime: null, startUtc: null, endUtc: null)],
        ),
      );

      final row = dto.cantiereWorkLogs.single;
      expect(row.endTime, isNull, reason: 'still open, not zero-length');
      expect(row.startUtc, isNull);
      expect(row.endUtc, isNull);
    });
  });

  group('SyncService._applyCantiereWorkLogs', () {
    test('mirrors the server row, seconds and all', () async {
      respondWith(
        payload(
          workLogs: [
            workLogJson('w1', description: 'Getto', clientId: 'device-key-1'),
            workLogJson(
              'w2',
              workDate: '2026-10-23',
              startTime: '13:00:00',
              endTime: null,
              startUtc: '2026-10-23T11:00:00Z',
              endUtc: null,
            ),
          ],
          scope: {
            'cantiereWorkLogs': ['w1', 'w2'],
          },
        ),
      );

      await svc.sync();

      final byId = {for (final r in await rows()) r.id: r};
      expect(byId.keys, unorderedEquals(['w1', 'w2']));
      expect(byId['w1']!.startSeconds, 8 * 3600);
      expect(byId['w1']!.endSeconds, (12 * 3600) + (30 * 60));
      expect(byId['w1']!.approvalStatus, 2);
      expect(byId['w1']!.clientId, 'device-key-1');
      expect(byId['w1']!.startUtc!.toUtc(), DateTime.utc(2026, 10, 22, 6));
      expect(byId['w2']!.endSeconds, isNull, reason: 'an open shift is not a closed one');
      expect(byId['w2']!.endUtc, isNull);
    });

    test('a second sync upserts rather than duplicating', () async {
      respondWith(
        payload(
          workLogs: [workLogJson('w1')],
          scope: {
            'cantiereWorkLogs': ['w1'],
          },
        ),
      );
      await svc.sync();

      // The mirror is re-sent in full every sync, so this is the normal case, not an overlap.
      respondWith(
        payload(
          workLogs: [workLogJson('w1', approvalStatus: 1)],
          scope: {
            'cantiereWorkLogs': ['w1'],
          },
        ),
      );
      await svc.sync();

      final all = await rows();
      expect(all, hasLength(1), reason: 'a re-sent row is not a second row');
      expect(all.single.approvalStatus, 1);
    });

    test('a payload from an older backend leaves the mirrored shifts alone', () async {
      respondWith(
        payload(
          workLogs: [workLogJson('w1')],
          scope: {
            'cantiereWorkLogs': ['w1'],
          },
        ),
      );
      await svc.sync();

      respondWith(payload()); // no 'cantiereWorkLogs' key and no manifest entry
      await svc.sync();

      expect((await rows()).single.id, 'w1');
    });

    test('a shift that leaves the manifest is pruned; a still-open one stays', () async {
      respondWith(
        payload(
          workLogs: [
            workLogJson('w-old'),
            workLogJson('w-open', endTime: null, endUtc: null),
          ],
          scope: {
            'cantiereWorkLogs': ['w-old', 'w-open'],
          },
        ),
      );
      await svc.sync();
      expect(await rows(), hasLength(2));

      // w-old aged past the window; the open shift is always re-sent regardless of its date.
      respondWith(
        payload(
          workLogs: [workLogJson('w-open', endTime: null, endUtc: null)],
          scope: {
            'cantiereWorkLogs': ['w-open'],
          },
        ),
      );
      await svc.sync();

      expect((await rows()).map((r) => r.id), ['w-open']);
    });

    test('never writes into, or reads from, the cantiere_punches outbox', () async {
      // A punch this device still owes the server, in the outbox only.
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'device-key-local',
              eventTime: DateTime.utc(2026, 10, 23, 6),
              eventType: 'ingresso',
              isPendingSync: const Value(true),
              cantiereId: const Value('site-1'),
            ),
          );

      respondWith(
        payload(
          workLogs: [workLogJson('w1', clientId: 'device-key-local')],
          scope: {
            'cantiereWorkLogs': ['w1'],
          },
        ),
      );
      await svc.sync();

      expect((await rows()).single.id, 'w1');
      final punch = await db.select(db.cantierePunches).getSingle();
      expect(
        punch.id,
        'device-key-local',
        reason: 'the mirror is the server\'s; the outbox is the device\'s owed work',
      );
      expect(punch.isPendingSync, isTrue, reason: 'a sync must not mark an unsent punch sent');
    });
  });
}
