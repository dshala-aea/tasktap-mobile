// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 47 -> 48: the customer's fiscal identity and mobile number.
///
/// Five additive columns on `customers` — `cellulare`, `fiscal_code`, `sdi_code`, `pec`, `province`.
/// Every one of them was already on the wire inside the customer entity the mobile sync returns;
/// the mirror simply never stored them, so the customer card could show P.IVA and nothing else.
///
/// Purely additive: a row written before the columns existed keeps null until the next sync
/// re-sends it, which is why `syncCursorGeneration` moved to v13 in the same release — the office
/// branch delta-filters customers, so an unedited customer would otherwise stay null forever.
///
/// Each `addColumn` is guarded by `PRAGMA table_info` rather than by `from`, so a device that
/// already carries the columns must not die on `duplicate column name` before the app opens.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig48_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one customer that carries every new field, closed again.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Rossi Impianti',
            taxId: const Value('01234567890'),
            cellulare: const Value('3331234567'),
            fiscalCode: const Value('RSSMRA80A01H501U'),
            sdiCode: const Value('0000000'),
            pec: const Value('rossi@pec.it'),
            province: const Value('RM'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v47 database has: none of the five columns exists, while
  /// the row itself — and its pre-existing fields — do.
  NativeDatabase rewindToV47() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE customers DROP COLUMN cellulare');
      raw.execute('ALTER TABLE customers DROP COLUMN fiscal_code');
      raw.execute('ALTER TABLE customers DROP COLUMN sdi_code');
      raw.execute('ALTER TABLE customers DROP COLUMN pec');
      raw.execute('ALTER TABLE customers DROP COLUMN province');
      raw.execute('PRAGMA user_version = 47');
    },
  );

  test('a v47 database gains all five customer columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV47());
    addTearDown(db.close);
    await db.select(db.customers).get();

    expect(await hasColumn(db, 'customers', 'cellulare'), isTrue);
    expect(await hasColumn(db, 'customers', 'fiscal_code'), isTrue);
    expect(await hasColumn(db, 'customers', 'sdi_code'), isTrue);
    expect(await hasColumn(db, 'customers', 'pec'), isTrue);
    expect(await hasColumn(db, 'customers', 'province'), isTrue);
  });

  test('the pre-existing row survives and holds null until the next sync', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV47());
    addTearDown(db.close);

    final customer = await (db.select(db.customers)..where((c) => c.id.equals('cust-1'))).getSingle();
    expect(customer.companyName, 'Rossi Impianti', reason: 'an additive migration drops no row');
    expect(customer.taxId, '01234567890', reason: 'a column v47 already had must keep its value');
    expect(customer.fiscalCode, isNull, reason: 'the dropped values are refetched, never invented');
    expect(customer.pec, isNull);
  });

  test('a value written after the migration round-trips, null included', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV47());
    addTearDown(db.close);
    await db.select(db.customers).get();

    await (db.update(db.customers)..where((c) => c.id.equals('cust-1'))).write(
      const CustomersCompanion(
        fiscalCode: Value('VRDLGU75B02F205X'),
        // The sync writes every one of these even when null: the server's value is authoritative,
        // so clearing the PEC in the office has to clear it here too.
        pec: Value(null),
      ),
    );

    final customer = await (db.select(db.customers)..where((c) => c.id.equals('cust-1'))).getSingle();
    expect(customer.fiscalCode, 'VRDLGU75B02F205X');
    expect(customer.pec, isNull);
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 47 on a schema that already carries every column: each guard must
    // skip its add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 47')),
    );
    addTearDown(db.close);

    final customer = await (db.select(db.customers)..where((c) => c.id.equals('cust-1'))).getSingle();
    expect(customer.pec, 'rossi@pec.it');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(48));
    await db.close();
  });
}
