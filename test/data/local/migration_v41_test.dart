// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 40 -> 41: `report_strumenti` gains two nullable free-text columns, `usage_description`
/// (how the instrument was used) and `outcome` (esito).
///
/// Purely additive and backfill-free: a row written before the columns existed has no note, which
/// is null. The step asks SQLite whether each column exists instead of trusting `from`, because the
/// `from < 36` step creates `report_strumenti` from the CURRENT definition, which already declares
/// both: an unconditional `addColumn` would die on `duplicate column name` for a device coming from
/// 35 or older.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig41_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one instrument row that carries both notes, closed again.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.reportStrumenti)
        .insert(
          ReportStrumentiCompanion.insert(
            id: 'str-1',
            reportId: 'r-1',
            strumentoId: const Value('s-1'),
            name: 'Multimetro',
            matricola: 'M-1',
            usageDescription: const Value('Misura isolamento'),
            outcome: const Value('Conforme'),
          ),
        );
    await db.close();
  }

  test('a v40 database gains both columns; old rows hold null and new notes round-trip', () async {
    await seedCurrent();

    final db = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          // The shape a real v40 database has: the row exists, the two columns do not.
          raw.execute('ALTER TABLE report_strumenti DROP COLUMN usage_description');
          raw.execute('ALTER TABLE report_strumenti DROP COLUMN outcome');
          raw.execute('PRAGMA user_version = 40');
        },
      ),
    );
    addTearDown(db.close);
    await (db.select(db.reportStrumenti)..limit(1)).get();

    expect(await hasColumn(db, 'report_strumenti', 'usage_description'), isTrue);
    expect(await hasColumn(db, 'report_strumenti', 'outcome'), isTrue);

    final old = await db.select(db.reportStrumenti).getSingle();
    expect(old.name, 'Multimetro', reason: 'an additive migration drops no row');
    expect(old.usageDescription, isNull, reason: 'a pre-existing row has no note');
    expect(old.outcome, isNull);

    // The VALUE round-trips through the migrated table, not just the column's existence.
    await db
        .into(db.reportStrumenti)
        .insert(
          ReportStrumentiCompanion.insert(
            id: 'str-2',
            reportId: 'r-1',
            strumentoId: const Value('s-2'),
            name: 'Termocamera',
            matricola: 'T-1',
            usageDescription: const Value('Ispezione quadro\nriga due'),
            outcome: const Value('Punto caldo su L2'),
          ),
        );
    final row = await (db.select(db.reportStrumenti)..where((s) => s.id.equals('str-2')))
        .getSingle();
    expect(row.usageDescription, 'Ispezione quadro\nriga due');
    expect(row.outcome, 'Punto caldo su L2');
  });

  test('a v35 database (table created from the current definition) does not die on a duplicate '
      'column', () async {
    await seedCurrent();

    final db = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          // A real v35 database has no report_strumenti at all; step 36 re-creates it from the
          // CURRENT definition, which already has the notes columns.
          for (final t in [
            'report_strumenti',
            'control_groups',
            'ticket_controls',
            'ticket_assets',
            'assets',
            'strumenti',
            'checklist_omitted_tickets',
            'contracts',
            'commesse',
            'prodotti_assistenza',
            'agents',
          ]) {
            raw.execute('DROP TABLE IF EXISTS $t');
          }
          raw.execute('ALTER TABLE report_controlli DROP COLUMN note');
          raw.execute('ALTER TABLE draft_reports DROP COLUMN strumenti_prefilled');
          raw.execute('ALTER TABLE draft_reports DROP COLUMN submission_problem_json');
          for (final c in [
            'contract_id',
            'commessa_id',
            'cantiere_id',
            'prodotto_assistenza_ids_json',
            'repairable_field',
          ]) {
            raw.execute('ALTER TABLE pending_tickets DROP COLUMN $c');
          }
          raw.execute('ALTER TABLE draft_reports DROP COLUMN expected_version');
          raw.execute('ALTER TABLE pending_tickets DROP COLUMN maintenance_template_id');
          raw.execute('PRAGMA user_version = 35');
        },
      ),
    );
    addTearDown(db.close);
    await (db.select(db.reportStrumenti)..limit(1)).get();

    expect(await hasColumn(db, 'report_strumenti', 'usage_description'), isTrue);
    expect(await hasColumn(db, 'report_strumenti', 'outcome'), isTrue);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(41));
    await db.close();
  });
}
