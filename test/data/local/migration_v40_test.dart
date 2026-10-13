// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 39 -> 40: the maintenance-template catalogue (`maintenance_templates`) the create wizard's
/// "Modello checklist" picker reads offline, plus the `pending_tickets.maintenance_template_id`
/// column the wizard's choice is queued into.
///
/// A new table and a new nullable column, both purely additive: the migration must create the table,
/// add the column, and drop nothing. No backfill — a pending row written before the column existed
/// has no template choice, which reads as null ("let the server resolve it from type/contract"), the
/// same as the wizard's own default option.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig40_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final createdAt = DateTime.utc(2026, 10, 1, 9);

  /// A v40 (current) database seeded with a queued ticket that already carries a template choice —
  /// the row shape that must survive the reopen-and-migrate below.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.pendingTickets)
        .insert(
          PendingTicketsCompanion.insert(
            id: 'pt-1',
            createdAt: createdAt,
            title: 'Ticket in coda',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            maintenanceTemplateId: const Value('tpl-1'),
          ),
        );
    await db.close();
  }

  /// Rewind the file to a *v39* database — drop the table and the column v40 adds, stamp
  /// `user_version = 39` — so the real `onUpgrade(39 -> 40)` runs on reopen. Mirrors
  /// `migration_v39_test.dart`'s own `reopenAsV38`.
  Future<AppDatabase> reopenAsV39() async {
    final reopened = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('DROP TABLE IF EXISTS maintenance_templates');
          raw.execute('ALTER TABLE pending_tickets DROP COLUMN maintenance_template_id');
          raw.execute('PRAGMA user_version = 39');
        },
      ),
    );
    addTearDown(reopened.close);
    // Force the open + migration.
    await (reopened.select(reopened.pendingTickets)..limit(1)).get();
    return reopened;
  }

  Future<bool> hasTable(AppDatabase db, String name) async =>
      (await db
              .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
              .get())
          .any((r) => r.read<String>('name') == name);

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .any((r) => r.read<String>('name') == column);

  test('a v39 database gains the catalogue table and the pending column, dropping no row', () async {
    await seedCurrent();

    final db = await reopenAsV39();

    expect(
      await hasTable(db, 'maintenance_templates'),
      isTrue,
      reason: 'the picker reads this table; without it the field can never appear',
    );
    expect(
      await hasColumn(db, 'pending_tickets', 'maintenance_template_id'),
      isTrue,
      reason: 'the wizard choice is queued into this column',
    );

    final rows = await db.select(db.pendingTickets).get();
    expect(rows.length, 1, reason: 'an additive migration must drop no row');
    expect(rows.single.title, 'Ticket in coda');
    expect(
      rows.single.maintenanceTemplateId,
      isNull,
      reason: 'a row written before the column existed carries no template choice',
    );
  });

  test('a v37 database also reaches v40 — step 38 already re-creates the table', () async {
    // The trap this pins has two halves, and only the first one is loud.
    //
    // The loud one: the `from < 38` step re-creates `pending_tickets` from the CURRENT definition, so
    // for a device coming from 37 or older the schema-40 step finds `maintenance_template_id` already
    // present. An unconditional `addColumn` there dies on `duplicate column name` — the app never
    // opens again. It is asked of SQLite instead.
    //
    // The quiet one, which is why the row is read back at the end: that same re-creation copies the
    // old rows with a statement built from the current definition. A column the old table lacks comes
    // out as a bare quoted identifier, and SQLite resolves an unknown double-quoted identifier as a
    // string literal instead of failing — so every queued ticket would silently hold the text
    // "maintenance_template_id" as its template id. Declaring the column in that step's `newColumns`
    // is what makes the copy leave it NULL. `hasColumn` below passes either way.
    await seedCurrent();

    final db = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          // The shape a real v37 database has: neither the v39 column nor the v40 one.
          raw.execute('ALTER TABLE draft_reports DROP COLUMN expected_version');
          raw.execute('ALTER TABLE pending_tickets DROP COLUMN maintenance_template_id');
          raw.execute('DROP TABLE IF EXISTS maintenance_templates');
          raw.execute('PRAGMA user_version = 37');
        },
      ),
    );
    addTearDown(db.close);
    await (db.select(db.pendingTickets)..limit(1)).get();

    expect(await hasColumn(db, 'pending_tickets', 'maintenance_template_id'), isTrue);
    expect(await hasColumn(db, 'draft_reports', 'expected_version'), isTrue);
    expect(await hasTable(db, 'maintenance_templates'), isTrue);

    final rows = await db.select(db.pendingTickets).get();
    expect(rows.length, 1);
    expect(
      rows.single.maintenanceTemplateId,
      isNull,
      reason: 'a device coming from 37 has never chosen a template; reading the column it was '
          'missing back out of the copy would put the literal column name in every queued ticket, '
          'a value the server rejects with a 400 no retry can repair',
    );
  });

  test('the migrated catalogue table accepts a template row', () async {
    await seedCurrent();
    final db = await reopenAsV39();

    await db
        .into(db.maintenanceTemplates)
        .insert(
          MaintenanceTemplatesCompanion.insert(
            id: 'tpl-9',
            origin: 'Tenant',
            name: 'Manutenzione caldaia',
            description: const Value('Annuale'),
            latestPublishedVersion: const Value(3),
          ),
        );

    final row = (await db.select(db.maintenanceTemplates).get()).single;
    expect(row.origin, 'Tenant');
    expect(row.name, 'Manutenzione caldaia');
    expect(row.description, 'Annuale');
    expect(row.isActive, isTrue, reason: 'defaults to active');
    expect(row.latestPublishedVersion, 3);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(40));
    await db.close();
  });

  test('wipeAllData clears the template catalogue too (sign-out must not leak another tenant)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.maintenanceTemplates)
        .insert(
          MaintenanceTemplatesCompanion.insert(
            id: 'tpl-1',
            origin: 'System',
            name: 'M',
          ),
        );

    await db.wipeAllData();

    expect(await db.select(db.maintenanceTemplates).get(), isEmpty);
    await db.close();
  });
}
