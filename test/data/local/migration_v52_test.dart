// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 51 -> 52: a recorded answer keeps the name and asset it was recorded against.
///
/// Until now a report's Controlli answers carried only `control_id`, and every surface that showed
/// them resolved that id against the ticket's checklist. On a device that never received that
/// checklist — another technician's phone, a ticket re-templated since, a checklist the sync simply
/// had not delivered — the sent report printed raw GUIDs instead of the control's name, and nothing
/// could group the findings under the asset they belonged to. The snapshot makes the answer
/// self-describing.
///
/// Purely additive, and each `addColumn` is guarded by `PRAGMA table_info` rather than by `from`,
/// like schemas 50 and 51: a device that already carries the columns must not die on `duplicate
/// column name` before the app opens. `report_controlli` has existed since schema 22, so a real v51
/// device always has the table itself.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig52_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one already-written answer.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.reportControlli)
        .insert(
          ReportControlliCompanion.insert(
            id: 'ctrl-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 22, 9),
            reportId: 'report-1',
            controlId: 'control-1',
            boolValue: const Value(true),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v51 database has: the two snapshot columns do not exist,
  /// while the row does.
  NativeDatabase rewindToV51() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE report_controlli DROP COLUMN control_label');
      raw.execute('ALTER TABLE report_controlli DROP COLUMN asset_id');
      raw.execute('PRAGMA user_version = 51');
    },
  );

  test('a v51 database gains both snapshot columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV51());
    addTearDown(db.close);
    await db.select(db.reportControlli).get();

    expect(await hasColumn(db, 'report_controlli', 'control_label'), isTrue);
    expect(await hasColumn(db, 'report_controlli', 'asset_id'), isTrue);
  });

  test('the answer survives with its recorded value intact and the new columns null', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV51());
    addTearDown(db.close);

    final answer = await (db.select(
      db.reportControlli,
    )..where((c) => c.id.equals('ctrl-1'))).getSingle();

    expect(answer.boolValue, isTrue, reason: 'an additive migration drops no row');
    expect(answer.controlId, 'control-1');
    expect(answer.reportId, 'report-1');
    // Null, not a guess: an answer recorded before schema 52 has no snapshot, and the view falls
    // back to the ticket checklist exactly as it did before.
    expect(answer.controlLabel, isNull);
    expect(answer.assetId, isNull);
  });

  test('an answer written after the migration round-trips through the added columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV51());
    addTearDown(db.close);
    await db.select(db.reportControlli).get();

    await db
        .into(db.reportControlli)
        .insert(
          ReportControlliCompanion.insert(
            id: 'ctrl-2',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 22, 10),
            reportId: 'report-1',
            controlId: 'control-2',
            numberValue: const Value(7.0),
            controlLabel: const Value('Pressione impianto'),
            assetId: const Value('asset-1'),
          ),
        );

    final answer = await (db.select(
      db.reportControlli,
    )..where((c) => c.id.equals('ctrl-2'))).getSingle();
    expect(answer.controlLabel, 'Pressione impianto');
    expect(answer.assetId, 'asset-1');
    expect(answer.numberValue, 7.0);
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 51 on a schema that already carries every column: each guard must
    // skip its add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 51')),
    );
    addTearDown(db.close);

    final answer = await (db.select(
      db.reportControlli,
    )..where((c) => c.id.equals('ctrl-1'))).getSingle();
    expect(answer.controlId, 'control-1');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(52));
  });
}
