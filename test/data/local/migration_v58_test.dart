// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 57 -> 58: a schedule row records whether it exists because an absence was approved.
///
/// One non-null column with a default on `schedules`, no backfill: every existing row reads "not an
/// absence", which is the true statement about a row written before the column existed and the
/// behaviour of every build before this one. The flag is filled by the next sync, because a
/// technician's schedules are re-sent in full rather than delta-filtered.
///
/// The `addColumn` is guarded by `PRAGMA table_info` rather than by `from`, like schemas 50-57: the
/// older-schema fixtures in test/ rewind `user_version` on the CURRENT schema, which already
/// declares the column, so an unconditional add would die on `duplicate column name` before the app
/// opens. The first test below exercises the real add path on a database that genuinely lacks it.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig58_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one job and one approved absence — the shape a technician's
  /// device has the moment before the upgrade, once an absence has already been materialised.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'schedule-job',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 24),
            activityDate: DateTime.utc(2026, 10, 24),
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
            id: 'schedule-ferie',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 24),
            activityDate: DateTime.utc(2026, 10, 25),
            timeStartMinutes: 0,
            timeEndMinutes: 0,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'ferie',
            description: '',
            isAssenza: const Value(true),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v57 database has: the column does not exist.
  NativeDatabase rewindToV57() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE schedules DROP COLUMN is_assenza');
      raw.execute('PRAGMA user_version = 57');
    },
  );

  test('a v57 database gains schedules.is_assenza', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);
    await db.select(db.schedules).get();

    expect(await hasColumn(db, 'schedules', 'is_assenza'), isTrue);
  });

  test('a row written before the column reads as "not an absence", not null', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);

    final rows = await db.select(db.schedules).get();
    final job = rows.firstWhere((s) => s.id == 'schedule-job');

    expect(rows, hasLength(2), reason: 'an additive migration drops no row');
    expect(job.title, 'Sostituzione caldaia');
    // The default, read back as a value: `hasColumn` alone would pass even if every existing row
    // had landed on the wrong side of the flag, and the whole point of the column is which rows it
    // marks.
    expect(job.isAssenza, isFalse);
  });

  test('the flag round-trips after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);
    await db.select(db.schedules).get();

    await (db.update(db.schedules)..where((s) => s.id.equals('schedule-ferie'))).write(
      const SchedulesCompanion(isAssenza: Value(true)),
    );
    await (db.update(db.schedules)..where((s) => s.id.equals('schedule-job'))).write(
      const SchedulesCompanion(isAssenza: Value(false)),
    );

    final rows = await db.select(db.schedules).get();
    expect(rows.firstWhere((s) => s.id == 'schedule-ferie').isAssenza, isTrue);
    expect(rows.firstWhere((s) => s.id == 'schedule-job').isAssenza, isFalse);
  });

  test('a database that already has the column does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 57 on a schema that already carries the column: the guard must skip
    // the add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 57')),
    );
    addTearDown(db.close);

    final rows = await db.select(db.schedules).get();
    expect(rows, hasLength(2));
    expect(rows.firstWhere((s) => s.id == 'schedule-ferie').isAssenza, isTrue);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(58));
  });
}
