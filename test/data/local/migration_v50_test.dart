// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 49 -> 50, both halves: who holds each instrument, and the cantiere clock-out fields.
///
/// `strumenti` gains `holder_user_id` and `holder_name`. Before them the rapportino's instrument
/// picker could only say "nel tuo kit" about the technician's own tools: a colleague's instrument
/// was a bare name, and the phone had no way to work out whose it was. The colleague mirror carries
/// ACTIVE users only, while an instrument stays with someone who has since been deactivated until
/// the office reassigns it — so the name has to travel with the instrument.
///
/// `cantiere_punches` gains `safety_notes`, `departure_latitude` and `departure_longitude`. Until
/// now those three travelled only through the online `end` call, so a technician clocking out with
/// no signal lost the note and the departure fix entirely — the batch upsert the offline queue
/// drains through had nowhere to put them.
///
/// Both are purely additive, and every `addColumn` is guarded by `PRAGMA table_info` rather than by
/// `from`, so a device that already carries the columns must not die on `duplicate column name`
/// before the app opens. `cantiere_punches` has existed since schema 7, so a real v49 device always
/// has it — the guard still checks the COLUMN, not the table.
///
/// No cursor bump for either: `strumenti` is one of the members the sync sends whole
/// (`replaceStrumenti` deletes and re-inserts), and a queued punch is local work the next drain
/// owns. That is the opposite of the v48 customer case, whose rows are delta-filtered.
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

  /// A current-schema database holding one instrument that carries a holder and one clock-in,
  /// closed again.
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
    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: 'punch-in',
            eventTime: DateTime.utc(2026, 10, 20, 7),
            eventType: 'ingresso',
            cantiereId: const Value('cantiere-1'),
            latitude: const Value(45.46),
            longitude: const Value(9.19),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v49 database has: none of the five columns exist, while
  /// the rows themselves — and their pre-existing fields — do.
  NativeDatabase rewindToV49() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE strumenti DROP COLUMN holder_user_id');
      raw.execute('ALTER TABLE strumenti DROP COLUMN holder_name');
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN safety_notes');
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN departure_latitude');
      raw.execute('ALTER TABLE cantiere_punches DROP COLUMN departure_longitude');
      raw.execute('PRAGMA user_version = 49');
    },
  );

  test('a v49 database gains all five columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV49());
    addTearDown(db.close);
    await db.select(db.strumenti).get();
    await db.select(db.cantierePunches).get();

    expect(await hasColumn(db, 'strumenti', 'holder_user_id'), isTrue);
    expect(await hasColumn(db, 'strumenti', 'holder_name'), isTrue);
    expect(await hasColumn(db, 'cantiere_punches', 'safety_notes'), isTrue);
    expect(await hasColumn(db, 'cantiere_punches', 'departure_latitude'), isTrue);
    expect(await hasColumn(db, 'cantiere_punches', 'departure_longitude'), isTrue);
  });

  test('the pre-existing rows survive, new columns null until the next sync or clock-out', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV49());
    addTearDown(db.close);

    final instrument = await (db.select(db.strumenti)..where((s) => s.id.equals('str-1'))).getSingle();
    expect(instrument.name, 'Multimetro', reason: 'an additive migration drops no row');
    expect(instrument.matricola, 'M1');
    expect(instrument.calibrationExpiry, '2027-03-31');
    expect(instrument.holderUserId, isNull, reason: 'the dropped values are refetched, never invented');
    expect(instrument.holderName, isNull);

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-in'))).getSingle();
    expect(punch.eventType, 'ingresso', reason: 'an additive migration drops no row');
    expect(punch.cantiereId, 'cantiere-1');
    expect(punch.latitude, 45.46, reason: 'the arrival fix is not overwritten by the new columns');
    expect(punch.safetyNotes, isNull);
    expect(punch.departureLatitude, isNull);
  });

  test('values written after the migration round-trip through the added columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV49());
    addTearDown(db.close);
    await db.select(db.strumenti).get();
    await db.select(db.cantierePunches).get();

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
    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: 'punch-out',
            eventTime: DateTime.utc(2026, 10, 20, 16),
            eventType: 'uscita',
            safetyNotes: const Value('Cintura allacciata'),
            departureLatitude: const Value(45.47),
            departureLongitude: const Value(9.18),
          ),
        );

    final assigned = await (db.select(db.strumenti)..where((s) => s.id.equals('str-1'))).getSingle();
    expect(assigned.holderUserId, 'user-mario');
    expect(assigned.holderName, 'Mario Rossi');
    final unassigned = await (db.select(db.strumenti)..where((s) => s.id.equals('str-2'))).getSingle();
    expect(unassigned.holderUserId, isNull);
    expect(unassigned.holderName, isNull);

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-out'))).getSingle();
    expect(punch.safetyNotes, 'Cintura allacciata');
    expect(punch.departureLatitude, 45.47);
    expect(punch.departureLongitude, 9.18);
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 49 on a schema that already carries every column: each guard must
    // skip its add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 49')),
    );
    addTearDown(db.close);

    final instrument = await (db.select(db.strumenti)..where((s) => s.id.equals('str-1'))).getSingle();
    expect(instrument.holderName, 'Anna Neri', reason: 'the guard kept the value the file already had');

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-in'))).getSingle();
    expect(punch.eventType, 'ingresso');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(50));
  });
}
