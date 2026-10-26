// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 57 -> 58: a schedule says whether an approved absence owns it.
///
/// The backend writes an approved Ferie/Permesso/Malattia as a completely ordinary `Schedule` row
/// — same shape, same assignment writer as a real appointment — and tags it with
/// `OwnedByAbsenceRequestId`. `SyncScheduleDto.isAssenza` is the only thing that tells the device
/// which is which; without it the dashboard counted a week of leave in "interventi oggi" and
/// queued it as the next job to start.
///
/// Purely additive, and the `addColumn` is guarded by `PRAGMA table_info` rather than by `from`,
/// like schemas 50, 51, 55, 56 and 57: a re-created table or a half-applied step must not kill the
/// app on `duplicate column name` before it opens. `schedules` has existed since well before v57,
/// so a real v57 device always has the table itself.
///
/// Numbered 58 because `ticket_statuses.isInProgress` (schema 56) and the field-parity columns
/// (schema 57) landed on main while this branch was open — those steps have their own tests.
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

  /// A current-schema database holding the two rows a technician's device has the moment before
  /// the upgrade: a real job and an approved absence, both ordinary schedules.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-job',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 20),
            activityDate: DateTime.utc(2026, 10, 27),
            timeStartMinutes: 540,
            timeEndMinutes: 660,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Caldaia',
            description: '',
          ),
        );
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-ferie',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 20),
            activityDate: DateTime.utc(2026, 10, 27),
            timeStartMinutes: 0,
            timeEndMinutes: 1439,
            userId: 'user-1',
            statusId: 1,
            locationId: '00000000-0000-0000-0000-000000000000',
            allDay: const Value(true),
            title: 'Ferie',
            description: 'Vacanza',
            isAssenza: const Value(true),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v57 database has: the flag does not exist, while both
  /// schedules do.
  NativeDatabase rewindToV57() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE schedules DROP COLUMN is_assenza');
      raw.execute('PRAGMA user_version = 57');
    },
  );

  test('a v57 database gains the flag', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);
    await db.select(db.schedules).get();

    expect(await hasColumn(db, 'schedules', 'is_assenza'), isTrue);
  });

  test('both schedules survive the upgrade, the flag defaulting to false', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);

    final job = await (db.select(db.schedules)..where((s) => s.id.equals('sched-job'))).getSingle();
    final ferie = await (db.select(
      db.schedules,
    )..where((s) => s.id.equals('sched-ferie'))).getSingle();

    expect(job.title, 'Caldaia', reason: 'an additive migration drops no row');
    expect(ferie.title, 'Ferie');
    // False, not a guess: a device upgraded offline cannot know which of its stored schedules an
    // absence owns. `syncCursorGeneration` is bumped to v17 alongside this step so the first sync
    // is a full one — a delta only re-sends changed rows, and an absence is precisely a row nobody
    // edits — and every absence is re-read with its true flag.
    expect(job.isAssenza, isFalse);
    expect(ferie.isAssenza, isFalse);
  });

  test('the flag round-trips after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);
    await db.select(db.schedules).get();

    await (db.update(
      db.schedules,
    )..where((s) => s.id.equals('sched-ferie'))).write(
      const SchedulesCompanion(isAssenza: Value(true)),
    );

    final ferie = await (db.select(
      db.schedules,
    )..where((s) => s.id.equals('sched-ferie'))).getSingle();
    expect(ferie.isAssenza, isTrue);
  });

  test('a database that already has the column does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 57 on a schema that already carries the column: the guard must skip
    // the add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 57')),
    );
    addTearDown(db.close);

    final ferie = await (db.select(
      db.schedules,
    )..where((s) => s.id.equals('sched-ferie'))).getSingle();
    expect(ferie.isAssenza, isTrue);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(58));
  });
}
