// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 49 -> 50: who holds each instrument.
///
/// Two additive columns on `strumenti` — `holder_user_id` and `holder_name`. Before them the
/// rapportino's instrument picker could only say "nel tuo kit" about the technician's own tools: a
/// colleague's instrument was a bare name, and the phone had no way to work out whose it was. The
/// colleague mirror carries ACTIVE users only, while an instrument stays with someone who has since
/// been deactivated until the office reassigns it — so the name has to travel with the instrument.
///
/// Purely additive, and no cursor bump: `strumenti` is one of the members the sync sends whole
/// (`replaceStrumenti` deletes and re-inserts), so the next sync fills both columns whatever its
/// cursor. That is the opposite of the v48 customer case, whose rows are delta-filtered.
///
/// Each `addColumn` is guarded by `PRAGMA table_info` rather than by `from`, so a device that
/// already carries the columns must not die on `duplicate column name` before the app opens.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig50_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one instrument that carries a holder, closed again.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.strumenti)
        .insert(
          StrumentiCompanion.insert(
            id: 'str-1',
            name: 'Multimetro',
            matricola: 'M1',
            calibrationExpiry: const Value('2027-03-31'),
            holderUserId: const Value('user-anna'),
            holderName: const Value('Anna Neri'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v49 database has: neither column exists, while the row
  /// itself — and its pre-existing fields — do.
  NativeDatabase rewindToV49() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE strumenti DROP COLUMN holder_user_id');
      raw.execute('ALTER TABLE strumenti DROP COLUMN holder_name');
      raw.execute('PRAGMA user_version = 49');
    },
  );

  test('a v49 database gains both holder columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV49());
    addTearDown(db.close);
    await db.select(db.strumenti).get();

    expect(await hasColumn(db, 'strumenti', 'holder_user_id'), isTrue);
    expect(await hasColumn(db, 'strumenti', 'holder_name'), isTrue);
  });

  test('the pre-existing instrument survives and holds no holder until the next sync', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV49());
    addTearDown(db.close);

    final instrument = await (db.select(db.strumenti)..where((s) => s.id.equals('str-1'))).getSingle();
    expect(instrument.name, 'Multimetro', reason: 'an additive migration drops no row');
    expect(instrument.matricola, 'M1');
    expect(instrument.calibrationExpiry, '2027-03-31');
    expect(instrument.holderUserId, isNull, reason: 'the dropped values are refetched, never invented');
    expect(instrument.holderName, isNull);
  });

  test('a value written after the migration round-trips, null included', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV49());
    addTearDown(db.close);
    await db.select(db.strumenti).get();

    await (db.update(db.strumenti)..where((s) => s.id.equals('str-1'))).write(
      const StrumentiCompanion(
        holderUserId: Value('user-mario'),
        // The sync writes every column from the payload: reassigning the instrument in the office
        // has to move it here too.
        holderName: Value('Mario Rossi'),
      ),
    );
    await db
        .into(db.strumenti)
        .insert(
          StrumentiCompanion.insert(
            id: 'str-2',
            name: 'Pinza',
            matricola: 'P1',
            // On the shelf: no id and no name, never an empty string for the picker to render.
            holderUserId: const Value(null),
            holderName: const Value(null),
          ),
        );

    final assigned = await (db.select(db.strumenti)..where((s) => s.id.equals('str-1'))).getSingle();
    expect(assigned.holderUserId, 'user-mario');
    expect(assigned.holderName, 'Mario Rossi');
    final unassigned = await (db.select(db.strumenti)..where((s) => s.id.equals('str-2'))).getSingle();
    expect(unassigned.holderUserId, isNull);
    expect(unassigned.holderName, isNull);
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 49 on a schema that already carries both columns: each guard must
    // skip its add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 49')),
    );
    addTearDown(db.close);

    final instrument = await (db.select(db.strumenti)..where((s) => s.id.equals('str-1'))).getSingle();
    expect(instrument.holderName, 'Anna Neri', reason: 'the guard kept the value the file already had');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(50));
    await db.close();
  });
}
