// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 45 -> 46: the tenant's extension fields ("campi aggiuntivi").
///
/// The step creates `extension_field_definitions` and adds `extension_values` to `tickets`,
/// `cantieri` and `draft_reports`. Purely additive: a row written before the column existed holds
/// null until the next sync re-sends it (which is why `syncCursorGeneration` moved forward in the
/// same release — a delta would otherwise never revisit an unedited row).
///
/// Each `addColumn` is guarded by `PRAGMA table_info` rather than by `from`, so a device that
/// already carries the columns must not die on `duplicate column name` before the app opens. The
/// guard checks the COLUMN, not the table: a fixture missing one of the three tables fails with
/// `no such table` — which is a fixture gap, not a device shape (every v45 device has all three).
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig46_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$table'",
              )
              .get())
          .isNotEmpty;

  /// A current-schema database holding one ticket and one cantiere that both carry an extension
  /// value, closed again.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            title: 'Caldaia',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            extensionValues: const Value('{"piano":"3"}'),
          ),
        );
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'cantiere-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Cantiere Nord',
            extensionValues: const Value('{"cf":"01234567890"}'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v45 database has: neither the definitions table nor any
  /// `extension_values` column exists, while the rows themselves do.
  NativeDatabase rewindToV45() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE tickets DROP COLUMN extension_values');
      raw.execute('ALTER TABLE cantieri DROP COLUMN extension_values');
      raw.execute('ALTER TABLE draft_reports DROP COLUMN extension_values');
      raw.execute('DROP TABLE extension_field_definitions');
      raw.execute('PRAGMA user_version = 45');
    },
  );

  test('a v45 database gains the definitions table and all three columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV45());
    addTearDown(db.close);
    await db.select(db.tickets).get();

    expect(await hasTable(db, 'extension_field_definitions'), isTrue);
    expect(await hasColumn(db, 'tickets', 'extension_values'), isTrue);
    expect(await hasColumn(db, 'cantieri', 'extension_values'), isTrue);
    expect(await hasColumn(db, 'draft_reports', 'extension_values'), isTrue);
  });

  test('the pre-existing rows survive the migration and hold null until the next sync', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV45());
    addTearDown(db.close);

    final ticket = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
    expect(ticket.title, 'Caldaia', reason: 'an additive migration drops no row');
    expect(ticket.extensionValues, isNull, reason: 'the dropped value is refetched, never invented');

    final cantiere = await (db.select(db.cantieri)
          ..where((c) => c.id.equals('cantiere-1')))
        .getSingle();
    expect(cantiere.name, 'Cantiere Nord');
    expect(cantiere.extensionValues, isNull);
  });

  test('a value written after the migration round-trips through the added column', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV45());
    addTearDown(db.close);
    await db.select(db.tickets).get();

    await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
      const TicketsCompanion(extensionValues: Value('{"piano":"5"}')),
    );
    await db.update(db.cantieri).write(
      const CantieriCompanion(extensionValues: Value('{"cf":"999"}')),
    );

    final ticket = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
    expect(ticket.extensionValues, '{"piano":"5"}');
    final cantiere = await (db.select(db.cantieri)
          ..where((c) => c.id.equals('cantiere-1')))
        .getSingle();
    expect(cantiere.extensionValues, '{"cf":"999"}');
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 45 on a schema that already carries every column: each guard must
    // skip its add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 45')));
    addTearDown(db.close);

    final ticket = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
    expect(ticket.extensionValues, '{"piano":"3"}');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(46));
    await db.close();
  });
}
