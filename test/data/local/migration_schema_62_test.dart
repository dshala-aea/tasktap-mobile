// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 61 -> 62: the two leaves a multi-day plan puts on a schedule.
///
/// `isBlockOccupied` marks a day a multi-day plan reserves instead of one booked on its own, so
/// the admin screens stop offering writes the server refuses — the same treatment `isAssenza`
/// already gets. `absenceRequestId` is the absence request a materialised absence came from.
///
/// `syncCursorGeneration` is bumped to v18 alongside this: office/admin callers sync `fullScope`,
/// where the backend DOES delta-filter schedules, so an unedited day of a multi-day block would
/// otherwise keep both column defaults forever on the role that edits plans.
///
/// Both `addColumn`s are guarded by `PRAGMA table_info` rather than by `from`, like schemas 50-61:
/// the older-schema fixtures in test/ rewind `user_version` on the CURRENT schema, which already
/// declares the columns, so an unconditional add would die on `duplicate column name` before the
/// app opens. The first test below exercises the real add path on a database that genuinely lacks
/// them.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig62_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding an ordinary job, a day reserved by a multi-day plan and an
  /// absence-owned row — the shape a technician's device has the moment before the upgrade.
  ///
  /// The two new columns are seeded with the truth the migration must not invent: the occupied day
  /// reads `true` and the absence carries its request id, so "a pre-existing row reads false/null"
  /// has values it could wrongly have kept.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'schedule-job',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 11, 3),
            activityDate: DateTime.utc(2026, 11, 3),
            timeStartMinutes: 480,
            timeEndMinutes: 1020,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Sostituzione caldaia',
            description: '',
          ),
        );
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'schedule-block',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 11, 3),
            activityDate: DateTime.utc(2026, 11, 4),
            timeStartMinutes: 480,
            timeEndMinutes: 1020,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Cantiere settimana',
            description: '',
            isBlockOccupied: const Value(true),
          ),
        );
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'schedule-ferie',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 11, 3),
            activityDate: DateTime.utc(2026, 11, 5),
            timeStartMinutes: 0,
            timeEndMinutes: 0,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'ferie',
            description: '',
            isAssenza: const Value(true),
            absenceRequestId: const Value('req-1'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v61 database has: neither column exists.
  NativeDatabase rewindToV61() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE schedules DROP COLUMN is_block_occupied');
      raw.execute('ALTER TABLE schedules DROP COLUMN absence_request_id');
      raw.execute('PRAGMA user_version = 61');
    },
  );

  test('a v61 database gains both schedule columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV61());
    addTearDown(db.close);
    await db.select(db.schedules).get();

    expect(await hasColumn(db, 'schedules', 'is_block_occupied'), isTrue);
    expect(await hasColumn(db, 'schedules', 'absence_request_id'), isTrue);
  });

  test('rows written before the columns read false/null, and their other values survive', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV61());
    addTearDown(db.close);

    final rows = await db.select(db.schedules).get();
    expect(rows, hasLength(3), reason: 'an additive migration drops no row');

    final byId = {for (final s in rows) s.id: s};

    // The values, not just `hasColumn`. The columns did not exist, so "not occupied, no absence
    // request" is the only honest reading — and the next sync is what restores the server's truth.
    expect(byId['schedule-job']!.title, 'Sostituzione caldaia');
    expect(byId['schedule-job']!.timeStartMinutes, 480);
    expect(byId['schedule-job']!.timeEndMinutes, 1020);
    expect(byId['schedule-job']!.isBlockOccupied, isFalse);
    expect(byId['schedule-job']!.absenceRequestId, isNull);

    // The pre-existing `isAssenza` column is untouched by this step, and the occupied day and the
    // absent request both read the defaults the rewind erased — not their seeded values.
    expect(byId['schedule-block']!.title, 'Cantiere settimana');
    expect(byId['schedule-block']!.isBlockOccupied, isFalse);
    expect(byId['schedule-block']!.absenceRequestId, isNull);

    expect(byId['schedule-ferie']!.isAssenza, isTrue, reason: 'an earlier column keeps its value');
    expect(byId['schedule-ferie']!.isBlockOccupied, isFalse);
    expect(byId['schedule-ferie']!.absenceRequestId, isNull);
  });

  test('both columns round-trip after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV61());
    addTearDown(db.close);
    await db.select(db.schedules).get();

    await (db.update(db.schedules)..where((s) => s.id.equals('schedule-block'))).write(
      const SchedulesCompanion(isBlockOccupied: Value(true)),
    );
    await (db.update(db.schedules)..where((s) => s.id.equals('schedule-ferie'))).write(
      const SchedulesCompanion(absenceRequestId: Value('req-1')),
    );

    final rows = await db.select(db.schedules).get();
    final byId = {for (final s in rows) s.id: s};

    expect(byId['schedule-block']!.isBlockOccupied, isTrue);
    expect(byId['schedule-ferie']!.absenceRequestId, 'req-1');
    expect(byId['schedule-job']!.isBlockOccupied, isFalse, reason: 'the update is scoped');
    expect(byId['schedule-job']!.absenceRequestId, isNull, reason: 'the update is scoped');
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 61 on a schema that already carries both columns: the guards must
    // skip the adds instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 61')),
    );
    addTearDown(db.close);

    final rows = await db.select(db.schedules).get();
    expect(rows, hasLength(3));

    final byId = {for (final s in rows) s.id: s};
    expect(byId['schedule-block']!.isBlockOccupied, isTrue, reason: 'the value is not reset');
    expect(byId['schedule-ferie']!.absenceRequestId, 'req-1', reason: 'the value is not reset');
  });

  test('schemaVersion has not gone backwards', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(62));
  });
}
