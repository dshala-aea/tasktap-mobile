// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 51 -> 52: the ticket history (Storico) mirror.
///
/// The timeline existed only on the server, so the Storico tab was online-only — the one screen
/// that says who moved a ticket went blank exactly where the technician stood. `ticket_history` is
/// its mirror: append-only rows, upserted by the sync and pruned with their ticket.
///
/// A NEW table, so `createTable` is additive on its own and needs no `PRAGMA table_info` guard;
/// drift emits `CREATE TABLE IF NOT EXISTS`, which is also what keeps the older-version fixtures
/// working when they rewind a current-schema database.
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

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$table'",
      ).get()).isNotEmpty;

  /// A current-schema database holding one ticket — the row a technician must not lose.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 10),
            title: 'Caldaia',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v51 database has: no `ticket_history` table at all.
  NativeDatabase rewindToV51() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('DROP TABLE ticket_history');
      raw.execute('PRAGMA user_version = 51');
    },
  );

  test('a v51 database gains the ticket_history table and its index', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV51());
    addTearDown(db.close);
    await db.select(db.ticketHistory).get();

    expect(await hasTable(db, 'ticket_history'), isTrue);
    final indexes = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ticket_history'",
    ).get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('ticket_history_ticket'),
      reason: 'the tab reads one ticket at a time; without the index that is a full scan per open',
    );
  });

  test('the ticket it already held survives the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV51());
    addTearDown(db.close);

    final ticket = await (db.select(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).getSingle();
    expect(ticket.title, 'Caldaia', reason: 'an additive migration drops no row');
    expect(ticket.customerId, 'cust-1');
  });

  test('a history row written after the migration round-trips', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV51());
    addTearDown(db.close);
    await db.select(db.ticketHistory).get();

    await db
        .into(db.ticketHistory)
        .insert(
          TicketHistoryCompanion.insert(
            id: 'h1',
            ticketId: 'ticket-1',
            fieldName: 'StatusId',
            oldValue: const Value('1'),
            newValue: const Value('4'),
            changedByUserId: 'user-1',
            changedAt: DateTime.utc(2026, 10, 23, 7, 30),
          ),
        );

    final row = await (db.select(
      db.ticketHistory,
    )..where((h) => h.id.equals('h1'))).getSingle();
    expect(row.fieldName, 'StatusId');
    expect(row.oldValue, '1');
    expect(row.newValue, '4');
    expect(row.changedAt.toUtc(), DateTime.utc(2026, 10, 23, 7, 30));
  });

  test('a database that already has the table does not die on a duplicate create', () async {
    await seedCurrent();

    // user_version rewound to 51 on a schema that already carries the table: `CREATE TABLE IF NOT
    // EXISTS` must skip instead of failing before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 51')),
    );
    addTearDown(db.close);

    expect(await db.select(db.ticketHistory).get(), isEmpty);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(52));
  });
}
