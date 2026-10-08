import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 36 -> 37: the reference mirror the ticket wizard needs offline (contracts, commesse,
/// prodotti assistenza, agents) and the queue columns that let a created ticket carry them.
///
/// Same technique as migration_v36_test.dart: build the current schema, remove exactly what the
/// step adds, rewind user_version, reopen so Drift runs the real onUpgrade(36 -> 37) against a
/// database that really lacks the objects, with pre-existing rows.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig37_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const newTables = ['contracts', 'commesse', 'prodotti_assistenza', 'agents'];

  Future<List<String>> master(AppDatabase db, String type) async =>
      (await db.customSelect("SELECT name FROM sqlite_master WHERE type = '$type'").get())
          .map((r) => r.read<String>('name'))
          .toList();

  Future<List<String>> columnsOf(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((r) => r.read<String>('name'))
          .toList();

  /// A v36 database: everything the step adds is undone, then user_version is rewound so the
  /// real onUpgrade runs on reopen.
  Future<AppDatabase> reopenAsV36() async {
    final reopened = AppDatabase(
      NativeDatabase(file, setup: (raw) {
        for (final t in newTables) {
          raw.execute('DROP TABLE IF EXISTS $t');
        }
        for (final c in ['contract_id', 'commessa_id', 'cantiere_id',
                         'prodotto_assistenza_ids_json', 'repairable_field']) {
          raw.execute('ALTER TABLE pending_tickets DROP COLUMN $c');
        }
        raw.execute('PRAGMA user_version = 36');
      }),
    );
    addTearDown(reopened.close);
    // Force the open + migration.
    await (reopened.select(reopened.customers)..limit(1)).get();
    return reopened;
  }

  test('a v36 database upgraded to 37 gains the four reference tables and their indexes', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    await db.close();

    final reopened = await reopenAsV36();

    expect(await master(reopened, 'table'), containsAll(newTables));
    // The reference pickers read "the rows for this customer" — the indexes must be created on
    // the upgrade path too, not only on a fresh install.
    expect(
      await master(reopened, 'index'),
      containsAll(['contracts_customer', 'commesse_customer', 'prodotti_assistenza_customer']),
    );
  });

  test('the queue columns are added to an existing pending ticket, null for a row that predates '
      'them', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.into(db.pendingTickets).insert(
          PendingTicketsCompanion.insert(
            id: 'queued-1', title: 'Caldaia', customerId: 'cu', locationId: 'l',
            statusId: 1, typeId: 1, createdAt: DateTime.now().toUtc(),
          ),
        );
    await db.close();

    final reopened = await reopenAsV36();

    expect(await columnsOf(reopened, 'pending_tickets'), containsAll(
        ['contract_id', 'commessa_id', 'cantiere_id', 'prodotto_assistenza_ids_json',
         'repairable_field']));
    final row = (await reopened.select(reopened.pendingTickets).get()).single;
    expect(row.id, 'queued-1', reason: 'spec 11.3: a schema bump must not touch queued work');
    expect(row.contractId, isNull);
  });

  /// The release deliberately does not reset every device's delta cursor - the reference queries
  /// carry no delta, so there is nothing a reset would fetch. This test is the guard on that
  /// decision, not a formality.
  test('the sync cursor generation is deliberately not bumped', () {
    expect(AppDatabase.syncCursorGeneration, 'v9');
  });
}
