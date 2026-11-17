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

Map<String, dynamic> cantiereJson(String id) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-10-01T09:00:00Z',
  'name': 'Cantiere $id',
};

Map<String, dynamic> crewJson(
  String id,
  String cantiereId,
  String userId, {
  bool isLead = false,
}) => {'id': id, 'cantiereId': cantiereId, 'userId': userId, 'isLead': isLead};

Map<String, dynamic> base({
  List<Map<String, dynamic>> cantieri = const [],
  List<Map<String, dynamic>>? crew,
}) => {
  'syncedAt': '2026-10-21T08:00:00Z',
  'since': null,
  'customers': <Object>[],
  'tickets': <Object>[],
  'cantieri': cantieri,
  // Absent entirely when the caller passes none, which is how an older backend's payload looks.
  'cantiereCrewAssignments': ?crew,
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

  Future<Map<String, CantiereCrewAssignment>> rows() async => {
    for (final r in await db.select(db.cantiereCrewAssignments).get()) r.id: r,
  };

  group('SyncResultDto', () {
    test('reads the crew member and marks the payload as carrying it', () {
      final dto = SyncResultDto.fromJson(base(crew: [crewJson('a1', 'c1', 'u1', isLead: true)]));

      expect(dto.carriesCantiereCrewAssignments, isTrue);
      expect(dto.cantiereCrewAssignments, hasLength(1));
      expect(dto.cantiereCrewAssignments.single.cantiereId, 'c1');
      expect(dto.cantiereCrewAssignments.single.userId, 'u1');
      expect(dto.cantiereCrewAssignments.single.isLead, isTrue);
    });

    test('an older backend that omits the member is distinguishable, not "empty crew"', () {
      final dto = SyncResultDto.fromJson(base());

      expect(dto.carriesCantiereCrewAssignments, isFalse);
      expect(dto.cantiereCrewAssignments, isEmpty);
    });

    test('isLead defaults to false when the wire omits it', () {
      final json = crewJson('a1', 'c1', 'u1')..remove('isLead');
      expect(SyncCantiereCrewAssignmentDto.fromJson(json).isLead, isFalse);
    });
  });

  group('SyncService._replaceCantiereCrewAssignments', () {
    test('fills the mirror for the payload\'s cantieri', () async {
      respondWith(
        base(
          cantieri: [cantiereJson('c1'), cantiereJson('c2')],
          crew: [
            crewJson('a1', 'c1', 'u1', isLead: true),
            crewJson('a2', 'c1', 'u2'),
            crewJson('a3', 'c2', 'u3', isLead: true),
          ],
        ),
      );

      await SyncService(db: db, dio: dio).sync();

      final byId = await rows();
      expect(byId.keys, containsAll(['a1', 'a2', 'a3']));
      expect(byId['a1']!.cantiereId, 'c1');
      expect(byId['a1']!.isLead, isTrue);
      expect(byId['a2']!.isLead, isFalse);
      expect(byId['a3']!.userId, 'u3');
    });

    test('replaces a carried cantiere\'s crew and leaves the other cantieri alone', () async {
      respondWith(
        base(
          cantieri: [cantiereJson('c1'), cantiereJson('c2')],
          crew: [crewJson('a1', 'c1', 'u1', isLead: true), crewJson('a3', 'c2', 'u3')],
        ),
      );
      await SyncService(db: db, dio: dio).sync();

      // Next payload scopes to c1 only. c1's crew changed (u1 lost the lead, u2 removed, a4 added);
      // c2 is not in this payload at all and must keep what it mirrored.
      respondWith(
        base(
          cantieri: [cantiereJson('c1')],
          crew: [crewJson('a1', 'c1', 'u1'), crewJson('a4', 'c1', 'u4', isLead: true)],
        ),
      );
      await SyncService(db: db, dio: dio).sync();

      final byId = await rows();
      expect(
        byId.keys,
        unorderedEquals(['a1', 'a4', 'a3']),
        reason: 'the carried cantiere is replaced; the absent one keeps its rows',
      );
      expect(byId['a1']!.isLead, isFalse, reason: 'a lead demotion must reach the device');
      expect(byId['a4']!.isLead, isTrue);
      expect(byId['a3']!.cantiereId, 'c2', reason: 'nothing prunes a cantiere outside the payload');
    });

    test('a carried cantiere whose crew is now empty has its rows removed', () async {
      respondWith(
        base(cantieri: [cantiereJson('c1')], crew: [crewJson('a1', 'c1', 'u1', isLead: true)]),
      );
      await SyncService(db: db, dio: dio).sync();
      expect(await rows(), hasLength(1));

      respondWith(base(cantieri: [cantiereJson('c1')], crew: const []));
      await SyncService(db: db, dio: dio).sync();

      expect(await rows(), isEmpty, reason: 'the member carried the complete crew: it is empty');
    });

    test('a payload from an older backend leaves the mirrored crews alone', () async {
      respondWith(
        base(cantieri: [cantiereJson('c1')], crew: [crewJson('a1', 'c1', 'u1', isLead: true)]),
      );
      await SyncService(db: db, dio: dio).sync();

      respondWith(base(cantieri: [cantiereJson('c1')])); // no 'cantiereCrewAssignments' key
      await SyncService(db: db, dio: dio).sync();

      final byId = await rows();
      expect(byId.keys, ['a1']);
      expect(byId['a1']!.isLead, isTrue);
    });
  });
}
