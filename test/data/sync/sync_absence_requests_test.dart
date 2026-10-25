// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
Map<String, dynamic> payload({List<Map<String, dynamic>>? absenceRequests}) => {
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
  'absenceRequests': ?absenceRequests,
};

Map<String, dynamic> absenceJson(
  String id, {
  String requestedByUserId = 'user-1',
  String? createdByUserId,
  int type = 0,
  String startDate = '2026-10-22',
  String? endDate,
  String? startTime,
  String? endTime,
  String? reason,
  int status = 0,
  String? decidedByUserId,
  String? decidedAt,
  String? decisionReason,
  String createdAt = '2026-10-20T09:00:00Z',
  String? updatedAt,
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'requestedByUserId': requestedByUserId,
  'createdByUserId': createdByUserId ?? requestedByUserId,
  'type': type,
  'startDate': startDate,
  'endDate': endDate ?? startDate,
  'startTime': startTime,
  'endTime': endTime,
  'reason': reason,
  'status': status,
  'decidedByUserId': decidedByUserId,
  'decidedAt': decidedAt,
  'decisionReason': decisionReason,
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

  Future<List<AbsenceRequestRow>> rows() => db.select(db.absenceRequests).get();

  group('SyncAbsenceRequestDto', () {
    test('reads the member, marks the payload as carrying it, and keeps the raw values', () {
      final dto = SyncResultDto.fromJson(
        payload(
          absenceRequests: [
            absenceJson(
              'a1',
              type: 5,
              startDate: '2026-10-22',
              endDate: '2026-10-24',
              startTime: '09:00:00',
              endTime: '13:00:00',
              status: 1,
              decidedByUserId: 'office-1',
              decidedAt: '2026-10-21T10:00:00Z',
              decisionReason: 'Ok',
            ),
          ],
        ),
      );

      expect(dto.carriesAbsenceRequests, isTrue);
      final row = dto.absenceRequests.single;
      expect(row.type, 5);
      expect(row.startDate, DateTime.utc(2026, 10, 22));
      expect(row.endDate, DateTime.utc(2026, 10, 24));
      expect(row.startTime, '09:00:00', reason: 'a Rome wall clock, not an instant');
      expect(row.endTime, '13:00:00');
      expect(row.status, 1);
      expect(row.decidedByUserId, 'office-1');
      expect(row.decidedAt, DateTime.utc(2026, 10, 21, 10));
      expect(row.decisionReason, 'Ok');
    });

    test('an older backend that omits the member is distinguishable, not "no requests"', () {
      final dto = SyncResultDto.fromJson(payload());

      expect(dto.carriesAbsenceRequests, isFalse);
      expect(dto.absenceRequests, isEmpty);
    });

    test('a whole-day request keeps both times absent', () {
      final dto = SyncResultDto.fromJson(payload(absenceRequests: [absenceJson('a1')]));

      final row = dto.absenceRequests.single;
      expect(row.startTime, isNull);
      expect(row.endTime, isNull);
    });
  });

  group('SyncService._applyAbsenceRequests', () {
    test('mirrors the request, with its civil dates as yyyy-MM-dd text', () async {
      respondWith(
        payload(
          absenceRequests: [
            absenceJson('a1', type: 3, startDate: '2026-11-02', endDate: '2026-11-03'),
            absenceJson('a2', type: 9, reason: 'Assistenza familiare', status: 2),
          ],
        ),
      );

      await svc.sync();

      final byId = {for (final r in await rows()) r.id: r};
      expect(byId.keys, unorderedEquals(['a1', 'a2']));
      expect(
        byId['a1']!.startDate,
        '2026-11-02',
        reason: 'a civil day in TEXT — a dateTime column would render the day before west of UTC',
      );
      expect(byId['a1']!.endDate, '2026-11-03');
      expect(byId['a1']!.type, 3);
      expect(byId['a2']!.reason, 'Assistenza familiare');
      expect(byId['a2']!.status, 2);
    });

    test('a second sync upserts rather than duplicating', () async {
      respondWith(payload(absenceRequests: [absenceJson('a1', status: 0)]));
      await svc.sync();

      respondWith(payload(absenceRequests: [absenceJson('a1', status: 1)]));
      await svc.sync();

      final all = await rows();
      expect(all, hasLength(1), reason: 'a re-sent request is not a second request');
      expect(all.single.status, 1, reason: 'the office decision must reach the device');
    });

    test('a request the server no longer lists is pruned, because the list IS the scope', () async {
      respondWith(payload(absenceRequests: [absenceJson('a-old'), absenceJson('a-kept')]));
      await svc.sync();
      expect(await rows(), hasLength(2));

      respondWith(payload(absenceRequests: [absenceJson('a-kept')]));
      await svc.sync();

      expect((await rows()).map((r) => r.id), ['a-kept']);
    });

    test('an empty carried list empties the device — it is a fact, not a missing download', () async {
      respondWith(payload(absenceRequests: [absenceJson('a1')]));
      await svc.sync();
      expect(await rows(), hasLength(1));

      respondWith(payload(absenceRequests: const []));
      await svc.sync();

      expect(await rows(), isEmpty);
    });

    test('a payload from an older backend leaves the mirrored requests alone', () async {
      respondWith(payload(absenceRequests: [absenceJson('a1')]));
      await svc.sync();

      respondWith(payload()); // no 'absenceRequests' key at all
      await svc.sync();

      expect((await rows()).single.id, 'a1');
    });
  });
}
