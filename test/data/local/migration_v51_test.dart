// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 50 -> 51: the cantiere clock-in screen's own fields.
///
/// `cantiere_punches` gains `work_order_number`, `equipment_used`, `team_size` and
/// `weather_conditions`. Until now the four travelled only through the online `start` call, so a
/// technician who clocked in with no signal queued a punch carrying none of them — the office lost
/// the work order, the equipment, the crew size and the weather the job is priced from, and
/// nothing on the device ever said so.
///
/// Purely additive, and each `addColumn` is guarded by `PRAGMA table_info` rather than by `from`,
/// like schema 50's step: a device that already carries the columns must not die on `duplicate
/// column name` before the app opens. The guard checks the COLUMN, not the table —
/// `cantiere_punches` has existed since schema 7, so a real v50 device always has it.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig51_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one clock-in, with the clock-out columns too (a v50 device
  /// has those already — schema 50 shipped them).
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: 'punch-in',
            eventTime: DateTime.utc(2026, 10, 22, 7),
            eventType: 'ingresso',
            cantiereId: const Value('cantiere-1'),
            description: const Value('sostituzione quadro'),
            latitude: const Value(45.46),
            longitude: const Value(9.19),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v50 database has: the four new columns do not exist,
  /// while the rows (and schema 50's clock-out columns) do.
  NativeDatabase rewindToV50() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN work_order_number');
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN equipment_used');
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN team_size');
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN weather_conditions');
      raw.execute('PRAGMA user_version = 50');
    },
  );

  test('a v50 database gains all four clock-in columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV50());
    addTearDown(db.close);
    await db.select(db.cantierePunches).get();

    expect(await hasColumn(db, 'cantiere_punches', 'work_order_number'), isTrue);
    expect(await hasColumn(db, 'cantiere_punches', 'equipment_used'), isTrue);
    expect(await hasColumn(db, 'cantiere_punches', 'team_size'), isTrue);
    expect(await hasColumn(db, 'cantiere_punches', 'weather_conditions'), isTrue);
  });

  test('the queued punch survives with its arrival data intact and the new columns null', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV50());
    addTearDown(db.close);

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-in'))).getSingle();

    expect(punch.eventType, 'ingresso', reason: 'an additive migration drops no row');
    expect(punch.cantiereId, 'cantiere-1');
    expect(punch.description, 'sostituzione quadro');
    expect(punch.latitude, 45.46);
    expect(punch.workOrderNumber, isNull);
    expect(punch.teamSize, isNull);
  });

  test('a clock-in written after the migration round-trips through the added columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV50());
    addTearDown(db.close);
    await db.select(db.cantierePunches).get();

    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: 'punch-late',
            eventTime: DateTime.utc(2026, 10, 22, 8),
            eventType: 'ingresso',
            workOrderNumber: const Value('OL-2026-118'),
            equipmentUsed: const Value('piattaforma aerea'),
            teamSize: const Value(3),
            weatherConditions: const Value('pioggia leggera'),
          ),
        );

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-late'))).getSingle();
    expect(punch.workOrderNumber, 'OL-2026-118');
    expect(punch.equipmentUsed, 'piattaforma aerea');
    expect(punch.teamSize, 3);
    expect(punch.weatherConditions, 'pioggia leggera');
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 50 on a schema that already carries every column: each guard must
    // skip its add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 50')),
    );
    addTearDown(db.close);

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-in'))).getSingle();
    expect(punch.eventType, 'ingresso');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(51));
  });
}
