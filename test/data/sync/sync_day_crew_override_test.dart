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
/// The server half of this contract (the rewritten occupancy row, `Scope.Schedules`, UpdatedAt
/// advancing on every crew change) is proven by `DayCrewSyncScopeTests` in the api repo; this file
/// proves the device half against a fake that models those server behaviours.
/// Each scenario asserts the row AND its assignee rows in the local database.
class MockDio extends Mock implements Dio {}

const _day = 'occ-2026-11-10';
const _other = 'occ-2026-11-11';
const _a = 'tech-a';
const _b = 'tech-b';
const _c = 'tech-c';
const _d = 'tech-d';

/// One occupancy row as the server holds it: the effective crew and a strictly advancing
/// `updatedAt` (the real server bumps UpdatedAt on every crew rewrite and on ClearDayCrew).
class _Row {
  _Row(this.id, this.day, this.owner, this.crew, this.updatedAt);
  final String id;
  final String day;
  final String owner;
  List<String> crew;
  DateTime updatedAt;
}

/// Fake server with a clock. Two caller kinds, as in the real sync:
/// - technician: sees the rows whose effective crew contains them; every sync returns all of
///   those rows (no cutoff), `scope.schedules` = their ids;
/// - office (full scope): the real server applies WhereAssignedTo to the scope for full-scope
///   callers too, so they see only the rows they are assigned to; full scope only adds the delta
///   cutoff, so a delta (`since` set) returns rows with updatedAt > since. (The fake's office
///   caller is not a technician filter: every seeded row is treated as assigned to it.)
class _Server {
  DateTime _clock = DateTime.utc(2026, 11, 5, 8);
  final rows = <String, _Row>{};
  final _original = <String, List<String>>{};

  DateTime _tick() => _clock = _clock.add(const Duration(minutes: 1));

  void seed(String id, List<String> crew, {String day = '2026-11-10', String? owner}) {
    rows[id] = _Row(id, day, owner ?? crew.first, [...crew], _tick());
    _original[id] = [...crew];
  }

  /// A crew change (remove, replace) advances updatedAt.
  void setCrew(String id, List<String> crew) {
    rows[id]!
      ..crew = [...crew]
      ..updatedAt = _tick();
  }

  /// ClearDayCrew: the block's original crew again, updatedAt advanced.
  void clearOverride(String id) => setCrew(id, _original[id]!);

  Map<String, dynamic> _json(_Row r) => {
    'id': r.id,
    'tenantId': 'tenant-1',
    'createdAt': '2026-11-01T08:00:00Z',
    'updatedAt': r.updatedAt.toIso8601String(),
    'activityDate': '${r.day}T00:00:00Z',
    'timeStart': '08:00:00',
    'timeEnd': '17:00:00',
    'userId': r.owner,
    'statusId': 1,
    'locationId': 'loc-1',
    'allDay': false,
    'title': 'Cantiere',
    'description': '',
    'isBlockOccupied': true,
    'assignees': [
      for (final u in r.crew) {'userId': u, 'isDirect': true, 'isLead': u == r.owner},
    ],
  };

  Map<String, dynamic> respond({String? technician, String? since}) {
    final visible = rows.values.where((r) => technician == null || r.crew.contains(technician));
    final cutoff = since == null ? null : DateTime.parse(since);
    final carried = visible.where(
      (r) => technician != null || cutoff == null || r.updatedAt.isAfter(cutoff),
    );
    return {
      'syncedAt': _clock.toIso8601String(),
      'since': since,
      'scope': {'schedules': [for (final r in visible) r.id]},
      'schedules': [for (final r in carried) _json(r)],
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
  }
}

/// One phone: its own in-memory database, syncing against the shared fake server.
class _Device {
  _Device(this.server, {this.technician}) : db = AppDatabase(NativeDatabase.memory()), dio = MockDio();
  final _Server server;

  /// Null = office (full scope) caller.
  final String? technician;
  final AppDatabase db;
  final MockDio dio;

  /// The query parameters of every request the device really sent.
  final requests = <Map<String, dynamic>>[];

  Future<void> sync() async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((inv) async {
      final q = Map<String, dynamic>.from(
        inv.namedArguments[#queryParameters] as Map? ?? const {},
      );
      requests.add(q);
      return Response(
        data: server.respond(technician: technician, since: q['since'] as String?),
        statusCode: 200,
        requestOptions: RequestOptions(path: '/api/sync/mobile'),
      );
    });
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
  late _Server server;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    server = _Server();
  });
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });

  _Device make({String? technician}) {
    final d = _Device(server, technician: technician);
    devices.add(d);
    return d;
  }

  test('1. technician removed from a day: that day is pruned, other days stay', () async {
    server.seed(_day, [_a, _b]);
    server.seed(_other, [_a, _b], day: '2026-11-11');
    final a = make(technician: _a);
    await a.sync();
    expect(await a.crew(_day), [_a, _b]);

    server.setCrew(_day, [_b, _c]); // A removed, C replaces
    await a.sync();

    expect(await a.scheduleIds(), [_other], reason: 'the day row is gone, not left behind');
    expect(await a.crew(_day), isEmpty, reason: 'its assignees go with it');
    expect(await a.crew(_other), [_a, _b], reason: 'the untouched day keeps its crew');
    expect(await a.orphanAssigneeScheduleIds(), isEmpty);
  });

  test('2. replaced by another: old technician prunes, new technician upserts with the crew',
      () async {
    server.seed(_day, [_a, _b]);
    final oldTech = make(technician: _a);
    final newTech = make(technician: _d);
    await oldTech.sync();
    await newTech.sync();
    expect(await newTech.scheduleIds(), isEmpty);

    server.setCrew(_day, [_d, _b]); // A replaced by D
    await oldTech.sync();
    await newTech.sync();

    expect(await oldTech.scheduleIds(), isEmpty);
    expect(await oldTech.crew(_day), isEmpty);
    expect(await oldTech.orphanAssigneeScheduleIds(), isEmpty);
    expect(await newTech.scheduleIds(), [_day]);
    expect(await newTech.crew(_day), [_b, _d], reason: 'the new technician is on the crew');
    expect(await newTech.orphanAssigneeScheduleIds(), isEmpty);
  });

  test('3. replacement later removed: the replacement device prunes again', () async {
    server.seed(_day, [_a, _b]);
    server.setCrew(_day, [_d, _b]);
    final newTech = make(technician: _d);
    await newTech.sync();
    expect(await newTech.crew(_day), [_b, _d]);

    server.setCrew(_day, [_b]); // D removed in turn
    await newTech.sync();

    expect(await newTech.scheduleIds(), isEmpty);
    expect(await newTech.crew(_day), isEmpty);
    expect(await newTech.orphanAssigneeScheduleIds(), isEmpty);
  });

  test('4. override deleted: a technician AND an office delta get the original crew back',
      () async {
    server.seed(_day, [_a, _b]);
    final tech = make(technician: _a);
    final office = make();
    await tech.sync();
    await office.sync();
    server.setCrew(_day, [_b, _c]); // A removed
    await tech.sync();
    await office.sync();
    expect(await tech.scheduleIds(), isEmpty);
    expect(await office.crew(_day), [_b, _c]);

    server.clearOverride(_day); // updatedAt advances, so a delta carries the row
    await tech.sync();
    await office.sync();

    expect(await tech.scheduleIds(), [_day], reason: 'the row comes back');
    expect(await tech.crew(_day), [_a, _b], reason: 'with the original crew');
    expect(await tech.orphanAssigneeScheduleIds(), isEmpty);
    // The office delta returned the row only because updatedAt advanced past its cursor.
    expect(server.rows[_day]!.updatedAt.isAfter(DateTime.parse(office.requests.last['since'] as String)), isTrue);
    expect(await office.crew(_day), [_a, _b]);
  });

  group('5. offline device', () {
    test('really sends its cursor, and a stale-cursor technician that lost access prunes',
        () async {
      server.seed(_day, [_a, _b]);
      server.seed(_other, [_a, _b], day: '2026-11-11');
      final a = make(technician: _a);
      await a.sync();
      final firstSyncedAt = server.respond(technician: _a)['syncedAt'];

      server.setCrew(_day, [_b, _c]);
      await a.sync();

      expect(a.requests.first.containsKey('since'), isFalse, reason: 'first sync is full');
      expect(a.requests.last['since'], firstSyncedAt, reason: 'the stored cursor is sent');
      expect(await a.scheduleIds(), [_other]);
      expect(await a.crew(_day), isEmpty);
      expect(await a.crew(_other), [_a, _b]);
      expect(await a.orphanAssigneeScheduleIds(), isEmpty);
    });

    test('skipped syncs, final state REMOVED: the stale row and assignees are gone', () async {
      server.seed(_day, [_a, _b, _c]);
      final a = make(technician: _a);
      await a.sync();
      expect(await a.scheduleIds(), [_day], reason: 'precondition: the row was ingested');
      expect(await a.crew(_day), [_a, _b, _c]);

      server.setCrew(_day, [_b, _c]); // A removed
      server.setCrew(_day, [_a, _b, _c]); // restored
      server.setCrew(_day, [_b, _d]); // removed again, D joins
      await a.sync(); // the device saw none of the transitions

      expect(await a.scheduleIds(), isEmpty);
      expect(await a.crew(_day), isEmpty);
      expect(await a.orphanAssigneeScheduleIds(), isEmpty);
    });

    test('skipped syncs, final state REPLACED: the replacement device holds the final crew',
        () async {
      server.seed(_day, [_a, _b, _c]);
      final oldTech = make(technician: _a);
      final newTech = make(technician: _d);
      await oldTech.sync();
      await newTech.sync();
      expect(await oldTech.scheduleIds(), [_day], reason: 'precondition: the row was ingested');
      expect(await oldTech.crew(_day), [_a, _b, _c]);

      server.setCrew(_day, [_b, _c]);
      server.setCrew(_day, [_b, _c, _d]);
      server.setCrew(_day, [_d, _b]); // A replaced by D, C also gone
      await oldTech.sync();
      await newTech.sync();

      expect(await oldTech.scheduleIds(), isEmpty);
      expect(await oldTech.orphanAssigneeScheduleIds(), isEmpty);
      expect(await newTech.scheduleIds(), [_day]);
      expect(await newTech.crew(_day), [_b, _d]);
    });

    test('skipped syncs, final state RESTORED: the row is back with the original crew',
        () async {
      server.seed(_day, [_a, _b, _c]);
      final a = make(technician: _a);
      await a.sync();
      server.setCrew(_day, [_b, _c]);
      await a.sync();
      expect(await a.scheduleIds(), isEmpty);

      server.setCrew(_day, [_b, _c, _d]);
      server.setCrew(_day, [_b]);
      server.clearOverride(_day);
      await a.sync(); // missed three transitions

      expect(await a.scheduleIds(), [_day]);
      expect(await a.crew(_day), [_a, _b, _c]);
      expect(await a.orphanAssigneeScheduleIds(), isEmpty);
    });

    test('an office delta with an EMPTY schedules[] but the row still in scope KEEPS it',
        () async {
      server.seed(_day, [_a, _b]);
      server.seed(_other, [_a, _b], day: '2026-11-11');
      final office = make();
      await office.sync();

      server.setCrew(_other, [_b]); // only _other changed
      await office.sync();
      await office.sync(); // nothing changed since: the delta carries no rows at all

      expect(office.requests.last.containsKey('since'), isTrue);
      expect(await office.scheduleIds(), [_day, _other], reason: 'in scope, so not pruned');
      expect(await office.crew(_day), [_a, _b], reason: 'assignees kept with the kept row');
      expect(await office.crew(_other), [_b]);
      expect(await office.orphanAssigneeScheduleIds(), isEmpty);
    });
  });

  test('same row, different assignees: [A,B,C] becomes exactly [A,C,D], no stale B', () async {
    server.seed(_day, [_a, _b, _c]);
    final a = make(technician: _a);
    await a.sync();
    expect(await a.crew(_day), [_a, _b, _c]);

    server.setCrew(_day, [_a, _c, _d]);
    await a.sync();

    expect(await a.scheduleIds(), [_day]);
    expect(await a.crew(_day), [_a, _c, _d]);
    expect(await a.orphanAssigneeScheduleIds(), isEmpty);
  });
}
