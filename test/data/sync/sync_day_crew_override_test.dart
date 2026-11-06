import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

/// Device reconciliation gate for day-level crew overrides (release gate).
///
/// A day override never reaches the device as a rule: the server rewrites the occupancy row's
/// assignees (the effective crew) and reports in `scope.schedules` which rows the caller still
/// sees. The device must therefore (a) prune a row it lost access to, with its assignees, (b)
/// upsert the row with exactly the new crew, and (c) get the row back when the override goes.
/// Each scenario asserts the row AND its assignee rows in the local database.
class MockDio extends Mock implements Dio {}

const _day = 'occ-2026-11-10';
const _other = 'occ-2026-11-11';
const _a = 'tech-a';
const _b = 'tech-b';
const _c = 'tech-c';
const _d = 'tech-d';

Map<String, dynamic> _row(String id, List<String> crew, {String day = '2026-11-10'}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-11-01T08:00:00Z',
  'updatedAt': '2026-11-05T08:00:00Z',
  'activityDate': '${day}T00:00:00Z',
  'timeStart': '08:00:00',
  'timeEnd': '17:00:00',
  'userId': crew.isEmpty ? _a : crew.first,
  'statusId': 1,
  'locationId': 'loc-1',
  'allDay': false,
  'title': 'Cantiere',
  'description': '',
  'isBlockOccupied': true,
  'assignees': [
    for (final u in crew) {'userId': u, 'isDirect': true, 'isLead': u == crew.first},
  ],
};

Map<String, dynamic> _payload({
  required List<String> scope,
  List<Map<String, dynamic>> schedules = const [],
}) => {
  'syncedAt': '2026-11-05T09:00:00Z',
  'since': null,
  'scope': {'schedules': scope},
  'schedules': schedules,
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
};

/// One phone: its own in-memory database, its own fake server connection.
class _Device {
  _Device() : db = AppDatabase(NativeDatabase.memory()), dio = MockDio();
  final AppDatabase db;
  final MockDio dio;

  Future<void> sync(Map<String, dynamic> body) async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer(
      (_) async => Response(
        data: body,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/api/sync/mobile'),
      ),
    );
    await SyncService(db: db, dio: dio).sync();
  }

  Future<List<String>> scheduleIds() async =>
      ((await db.select(db.schedules).get()).map((s) => s.id).toList()..sort());

  Future<List<String>> crew(String scheduleId) async =>
      ((await db.select(db.scheduleAssignees).get())
              .where((a) => a.scheduleId == scheduleId)
              .map((a) => a.userId)
              .toList()
            ..sort());

  /// Assignee rows whose schedule is not on the device: must always be empty.
  Future<List<String>> orphanAssigneeScheduleIds() async {
    final held = (await db.select(db.schedules).get()).map((s) => s.id).toSet();
    return (await db.select(db.scheduleAssignees).get())
        .map((a) => a.scheduleId)
        .where((id) => !held.contains(id))
        .toList();
  }

  Future<void> close() => db.close();
}

void main() {
  final devices = <_Device>[];
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });

  _Device make() {
    final d = _Device();
    devices.add(d);
    return d;
  }

  test('1. technician removed from a day: that day is pruned, other days stay', () async {
    final a = make();
    await a.sync(
      _payload(
        scope: [_day, _other],
        schedules: [_row(_day, [_a, _b]), _row(_other, [_a, _b], day: '2026-11-11')],
      ),
    );
    expect(await a.crew(_day), [_a, _b]);

    // Override removes A on _day: the row is no longer in A's scope. Nothing else changed.
    await a.sync(_payload(scope: [_other]));

    expect(await a.scheduleIds(), [_other], reason: 'the day row is gone, not left behind');
    expect(await a.crew(_day), isEmpty, reason: 'its assignees go with it');
    expect(await a.crew(_other), [_a, _b], reason: 'the untouched day keeps its crew');
    expect(await a.orphanAssigneeScheduleIds(), isEmpty);
  });

  test('2. replaced by another: old technician prunes, new technician upserts with the crew',
      () async {
    final oldTech = make();
    final newTech = make();
    await oldTech.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _b])]));
    // The new technician never saw the day.
    await newTech.sync(_payload(scope: const []));
    expect(await newTech.scheduleIds(), isEmpty);

    // A is replaced by D: effective crew [D, B].
    await oldTech.sync(_payload(scope: const []));
    await newTech.sync(_payload(scope: [_day], schedules: [_row(_day, [_d, _b])]));

    expect(await oldTech.scheduleIds(), isEmpty);
    expect(await oldTech.crew(_day), isEmpty);
    expect(await oldTech.orphanAssigneeScheduleIds(), isEmpty);
    expect(await newTech.scheduleIds(), [_day]);
    expect(await newTech.crew(_day), [_b, _d], reason: 'the new technician is on the crew');
    expect(await newTech.orphanAssigneeScheduleIds(), isEmpty);
  });

  test('3. replacement later removed: the replacement device prunes again', () async {
    final newTech = make();
    await newTech.sync(_payload(scope: [_day], schedules: [_row(_day, [_d, _b])]));
    expect(await newTech.crew(_day), [_b, _d]);

    await newTech.sync(_payload(scope: const []));

    expect(await newTech.scheduleIds(), isEmpty);
    expect(await newTech.crew(_day), isEmpty);
    expect(await newTech.orphanAssigneeScheduleIds(), isEmpty);
  });

  test('4. override deleted: the original technician\'s row returns with the original crew',
      () async {
    final a = make();
    await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _b])]));
    await a.sync(_payload(scope: const []));
    expect(await a.scheduleIds(), isEmpty);

    // Override deleted: the day follows the block again; the server re-sends the row (its
    // rewrite bumped updatedAt, so a delta carries it) with the original crew, in scope.
    await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _b])]));

    expect(await a.scheduleIds(), [_day], reason: 'the row comes back');
    expect(await a.crew(_day), [_a, _b], reason: 'with the original crew');
    expect(await a.orphanAssigneeScheduleIds(), isEmpty);
  });

  group('5. offline device that lost access', () {
    test('a device whose cursor predates the change drops the stale row and assignees', () async {
      final a = make();
      await a.sync(
        _payload(
          scope: [_day, _other],
          schedules: [_row(_day, [_a, _b]), _row(_other, [_a, _b], day: '2026-11-11')],
        ),
      );

      // Back online later: the delta carries no row for _day, only a narrower scope.
      await a.sync(_payload(scope: [_other]));

      expect(await a.scheduleIds(), [_other]);
      expect(await a.crew(_day), isEmpty);
      expect(await a.orphanAssigneeScheduleIds(), isEmpty);
    });

    test('a device that missed several syncs (removed, replaced, restored, removed) converges',
        () async {
      final a = make();
      await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _b, _c])]));

      // Every intermediate server state is invisible to the device: only the final answer, a
      // scope without the row, reaches it, and that alone must remove the row.
      await a.sync(_payload(scope: const []));

      expect(await a.scheduleIds(), isEmpty);
      expect(await a.crew(_day), isEmpty);
      expect(await a.orphanAssigneeScheduleIds(), isEmpty);
    });

    test('a device that missed a remove-then-restore sees the restored crew, not the old one',
        () async {
      final a = make();
      await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _b, _c])]));

      // The missed syncs removed and restored A; the state it finally gets has the row in scope
      // with a changed crew.
      await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _c])]));

      expect(await a.scheduleIds(), [_day]);
      expect(await a.crew(_day), [_a, _c]);
      expect(await a.orphanAssigneeScheduleIds(), isEmpty);
    });
  });

  test('same row, different assignees: [A,B,C] becomes exactly [A,C,D], no stale B', () async {
    final a = make();
    await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _b, _c])]));
    expect(await a.crew(_day), [_a, _b, _c]);

    await a.sync(_payload(scope: [_day], schedules: [_row(_day, [_a, _c, _d])]));

    expect(await a.scheduleIds(), [_day]);
    expect(await a.crew(_day), [_a, _c, _d]);
    expect(await a.orphanAssigneeScheduleIds(), isEmpty);
  });
}
