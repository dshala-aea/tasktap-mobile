// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 55 -> 56: a ticket status keeps the tenant's "work has started" flag.
///
/// The server has always sent `isInProgress` on a status — the sync serializes the `TicketStatus`
/// entity — but the device dropped it, so the home queue could only tell that a job had begun by
/// finding a running timer. A ticket the office moved to "In corso", or one whose timer had since
/// been stopped, fell back to "da fare" while the work was under way.
///
/// Purely additive, and the `addColumn` is guarded by `PRAGMA table_info` rather than by `from`,
/// like schemas 50, 51 and 55: a re-created table or a half-applied step must not kill the app on
/// `duplicate column name` before it opens. `ticket_statuses` has existed since well before v55, so
/// a real v55 device always has the table itself.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig56_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding the seeded "In corso" status and a ticket on it — the exact
  /// shape a technician's device has the moment before the upgrade.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: const Value(2),
            tenantId: 't1',
            name: 'In corso',
            isInProgress: const Value(true),
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 20),
            title: 'Intervento',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 1,
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v55 database has: the flag does not exist, while the
  /// status row and the ticket on it do.
  NativeDatabase rewindToV55() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE ticket_statuses DROP COLUMN is_in_progress');
      raw.execute('PRAGMA user_version = 55');
    },
  );

  test('a v55 database gains the flag', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV55());
    addTearDown(db.close);
    await db.select(db.ticketStatuses).get();

    expect(await hasColumn(db, 'ticket_statuses', 'is_in_progress'), isTrue);
  });

  test('the status and its ticket survive the upgrade, the flag defaulting to false', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV55());
    addTearDown(db.close);

    final status = await (db.select(
      db.ticketStatuses,
    )..where((s) => s.id.equals(2))).getSingle();
    final ticket = await (db.select(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).getSingle();

    expect(status.name, 'In corso', reason: 'an additive migration drops no row');
    expect(ticket.statusId, 2);
    // False, not a guess: a device upgraded offline does not yet know which of the tenant's
    // statuses carries the flag. The first sync replaces `ticket_statuses` wholesale and fills it,
    // which is why the column can be added without a backfill.
    expect(status.isInProgress, isFalse);
  });

  test('the flag round-trips after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV55());
    addTearDown(db.close);
    await db.select(db.ticketStatuses).get();

    await (db.update(
      db.ticketStatuses,
    )..where((s) => s.id.equals(2))).write(
      const TicketStatusesCompanion(isInProgress: Value(true)),
    );

    final status = await (db.select(
      db.ticketStatuses,
    )..where((s) => s.id.equals(2))).getSingle();
    expect(status.isInProgress, isTrue);
  });

  test('a database that already has the column does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 55 on a schema that already carries the column: the guard must skip
    // the add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 55')),
    );
    addTearDown(db.close);

    final status = await (db.select(
      db.ticketStatuses,
    )..where((s) => s.id.equals(2))).getSingle();
    expect(status.isInProgress, isTrue);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(56));
  });
}
