// dart format width=100
// "Today" in both session repositories is the tenant business day, a half-open UTC window from
// BusinessTime.todayRangeUtc(), never the device day. Fixed clocks and literal UTC instants only;
// the suite must pass under any device TZ.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';

class _Case {
  _Case(this.name, this.zone, this.clock, this.before, this.first, this.last, this.after);
  final String name;
  final String zone;
  final String clock;
  final String before; // last instant of yesterday
  final String first; // first instant of today
  final String last; // last instant of today
  final String after; // first instant of tomorrow
}

final _cases = <_Case>[
  _Case('Rome summer', 'Europe/Rome', '2026-07-10T20:00:00Z', '2026-07-09T21:59:59Z',
      '2026-07-09T22:00:00Z', '2026-07-10T21:59:59Z', '2026-07-10T22:00:00Z'),
  _Case('Los Angeles summer', 'America/Los_Angeles', '2026-07-10T20:00:00Z',
      '2026-07-10T06:59:59Z', '2026-07-10T07:00:00Z', '2026-07-11T06:59:59Z',
      '2026-07-11T07:00:00Z'),
  _Case('Rome 23h day', 'Europe/Rome', '2027-03-28T10:00:00Z', '2027-03-27T22:59:59Z',
      '2027-03-27T23:00:00Z', '2027-03-28T21:59:59Z', '2027-03-28T22:00:00Z'),
  _Case('Rome 25h day', 'Europe/Rome', '2026-10-25T10:00:00Z', '2026-10-24T21:59:59Z',
      '2026-10-24T22:00:00Z', '2026-10-25T22:59:59Z', '2026-10-25T23:00:00Z'),
];

void main() {
  late AppDatabase db;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  for (final c in _cases) {
    BusinessTime bt() => BusinessTime(c.zone, clock: () => DateTime.parse(c.clock));

    group('WorkSessionRepository ${c.name}', () {
      late WorkSessionRepository repo;
      setUp(() async {
        repo = WorkSessionRepository(db, businessTime: bt());
        // Inserted out of order to prove time ordering.
        for (final (id, t) in [
          ('after', c.after),
          ('last', c.last),
          ('before', c.before),
          ('first', c.first),
        ]) {
          await repo.addEvent(id: id, eventTime: DateTime.parse(t), eventType: 'ingresso');
        }
      });

      test('get and watch return exactly the business day, in order', () async {
        expect((await repo.getTodaySessions()).map((s) => s.id), ['first', 'last']);
        expect((await repo.watchTodaySessions().first).map((s) => s.id), ['first', 'last']);
      });

      test('clearToday deletes only the business day', () async {
        await repo.clearToday();
        final left = await db.select(db.workSessions).get();
        expect(left.map((s) => s.id).toSet(), {'before', 'after'});
      });
    });

    group('CantiereSessionRepository ${c.name}', () {
      late CantiereSessionRepository repo;
      setUp(() async {
        repo = CantiereSessionRepository(db, businessTime: bt());
        for (final (id, t) in [
          ('after', c.after),
          ('last', c.last),
          ('before', c.before),
          ('first', c.first),
        ]) {
          await repo.addEvent(id: id, eventTime: DateTime.parse(t), eventType: 'ingresso');
        }
      });

      test('get and watch return exactly the business day, in order', () async {
        expect((await repo.getTodayEvents()).map((s) => s.id), ['first', 'last']);
        expect((await repo.watchTodayEvents().first).map((s) => s.id), ['first', 'last']);
      });

      test('clearToday deletes only the business day', () async {
        await repo.clearToday();
        final left = await db.select(db.cantierePunches).get();
        expect(left.map((s) => s.id).toSet(), {'before', 'after'});
      });
    });
  }

  test('default constructor uses the Rome fallback zone', () async {
    final repo = WorkSessionRepository(db);
    // Today in Rome contains "now" by construction.
    await repo.addEvent(id: 'now', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    expect((await repo.getTodaySessions()).map((s) => s.id), ['now']);
  });
}
