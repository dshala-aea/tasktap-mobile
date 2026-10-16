// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 41 -> 42: `customers` gains a nullable `agent_id` — the customer's one agent, which
/// pre-fills a new ticket's Riferimento.
///
/// Purely additive: a row written before the column existed has no agent, which is null. The step
/// asks SQLite whether the column exists instead of trusting `from`. The sync cursor moves to v10 in
/// the same release (see [AppDatabase.syncCursorGeneration]) so that a device refetches the
/// customers it already holds and fills the column — the value assertions below are about the
/// column, not that refetch.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig42_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one customer that carries an agent, closed again.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'ACME Srl',
            agentId: const Value('ag-1'),
          ),
        );
    await db.close();
  }

  test('a v41 database gains the column; old rows hold null and a new agent round-trips', () async {
    await seedCurrent();

    final db = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          // The shape a real v41 database has: the row exists, the column does not.
          raw.execute('ALTER TABLE customers DROP COLUMN agent_id');
          raw.execute('PRAGMA user_version = 41');
        },
      ),
    );
    addTearDown(db.close);
    await (db.select(db.customers)..limit(1)).get();

    expect(await hasColumn(db, 'customers', 'agent_id'), isTrue);

    final old = await db.select(db.customers).getSingle();
    expect(old.companyName, 'ACME Srl', reason: 'an additive migration drops no row');
    expect(old.agentId, isNull, reason: 'a pre-existing customer has no agent until the next sync');

    // The VALUE round-trips through the migrated table, not just the column's existence.
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Beta Spa',
            agentId: const Value('ag-2'),
          ),
        );
    final row = await (db.select(db.customers)..where((c) => c.id.equals('cust-2'))).getSingle();
    expect(row.agentId, 'ag-2');
  });

  test('a database that already has the column does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 41 on a schema that already carries agent_id: the guard must skip the
    // add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 41')));
    addTearDown(db.close);
    await (db.select(db.customers)..limit(1)).get();

    expect((await db.select(db.customers).getSingle()).agentId, 'ag-1');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(42));
    await db.close();
  });
}
