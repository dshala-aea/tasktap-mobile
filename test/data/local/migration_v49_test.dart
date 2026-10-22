// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 48 -> 49: the customer's labeled contacts.
///
/// A new table — `customer_contacts` — because the customer screen's *Contatti* section was the last
/// list on it still fetched live: it called `GET /api/customers/{id}/contacts` on every open and
/// painted an error card when the radio was gone, on the one screen a technician reaches straight
/// from a ticket while standing in front of the machine.
///
/// A brand-new table, so there is nothing to backfill; the rows arrive on the next sync. That sync
/// has to be a full one, which is why `syncCursorGeneration` moved to v14 in the same release: on the
/// office branch customers are delta-filtered, so a cursor already past a customer would never
/// receive its contacts until something else edited that customer.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig49_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<List<String>> master(AppDatabase db, String type) async =>
      (await db.customSelect("SELECT name FROM sqlite_master WHERE type = '$type'").get())
          .map((r) => r.read<String>('name'))
          .toList();

  /// A current-schema database holding one customer and one of its contacts, closed again.
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
          ),
        );
    await db
        .into(db.customerContacts)
        .insert(
          CustomerContactsCompanion.insert(
            id: 'contact-1',
            customerId: 'cust-1',
            name: 'Mario Rossi',
            role: const Value('Titolare'),
            phone: const Value('3331234567'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v48 database has: no `customer_contacts` table and no
  /// index, while the customer row and its pre-existing fields do.
  NativeDatabase rewindToV48() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('DROP INDEX IF EXISTS customer_contacts_customer');
      raw.execute('DROP TABLE IF EXISTS customer_contacts');
      raw.execute('PRAGMA user_version = 48');
    },
  );

  test('a v48 database gains the customer_contacts table and its index', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV48());
    addTearDown(db.close);
    await db.select(db.customers).get();

    expect(await master(db, 'table'), contains('customer_contacts'));
    expect(
      await master(db, 'index'),
      contains('customer_contacts_customer'),
      reason: 'the Contatti section is read per customer, on every open of that screen',
    );
  });

  test('the pre-existing customer survives and starts with no contacts', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV48());
    addTearDown(db.close);

    final customer = await (db.select(db.customers)..where((c) => c.id.equals('cust-1'))).getSingle();
    expect(customer.companyName, 'Rossi Impianti', reason: 'a table-creating migration drops no row');
    expect(customer.taxId, '01234567890');
    expect(
      await db.select(db.customerContacts).get(),
      isEmpty,
      reason: 'the old rows went with the table and are refetched, never invented',
    );
  });

  test('a contact written after the migration round-trips, nulls included', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV48());
    addTearDown(db.close);
    await db.select(db.customers).get();

    await db
        .into(db.customerContacts)
        .insertOnConflictUpdate(
          // Written the way the sync writes it: every column comes from the payload, so clearing a
          // contact's email in the office has to clear it here too.
          const CustomerContactsCompanion(
            id: Value('contact-2'),
            customerId: Value('cust-1'),
            name: Value('Anna Bianchi'),
            role: Value(null),
            phone: Value('021234567'),
            email: Value(null),
            notes: Value('solo ufficio'),
          ),
        );

    final row = await (db.select(db.customerContacts)..where((c) => c.id.equals('contact-2'))).getSingle();
    expect(row.name, 'Anna Bianchi');
    expect(row.email, isNull);
    expect(row.notes, 'solo ufficio');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(49));
    await db.close();
  });
}
