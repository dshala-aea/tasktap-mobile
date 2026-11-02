// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 60 -> 61: `ticket_statuses.office_only`, the "Solo ufficio" flag.
///
/// Only a caller holding `interventi.ticket.configure` may move a ticket into such a status or out
/// of it. The device mirrors the flag so the status sheet does not offer a move the server will
/// reject with a 403 after the tap.
///
/// No cursor bump: `MobileUserSyncService` queries the statuses per tenant with no delta filter (the
/// entity has no `UpdatedAt`), so the next sync rewrites the whole table and carries the new leaf.
///
/// The `addColumn` is guarded by `PRAGMA table_info` rather than by `from`, like schemas 50-60: the
/// older-schema fixtures in test/ rewind `user_version` on the CURRENT schema, which already
/// declares the column, so an unconditional add would die on `duplicate column name` before the app
/// opens.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig61_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding two statuses — the shape a technician's device has the
  /// moment before the upgrade. One of them carries the flag, so the "a pre-existing row reads
  /// false" contract has a `true` it could wrongly have kept.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: const Value(1),
            tenantId: 't1',
            name: 'Aperto',
            isDefault: const Value(true),
          ),
        );
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: const Value(7),
            tenantId: 't1',
            name: 'Da ufficio',
            officeOnly: const Value(true),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v60 database has: the column does not exist.
  NativeDatabase rewindToV60() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE ticket_statuses DROP COLUMN office_only');
      raw.execute('PRAGMA user_version = 60');
    },
  );

  test('a v60 database gains the column', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV60());
    addTearDown(db.close);
    await db.select(db.ticketStatuses).get();

    expect(await hasColumn(db, 'ticket_statuses', 'office_only'), isTrue);
  });

  test('a status written before the column reads false, and its other flags survive', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV60());
    addTearDown(db.close);

    final statuses = await db.select(db.ticketStatuses).get();

    expect(statuses, hasLength(2), reason: 'an additive migration drops no row');

    final byId = {for (final s in statuses) s.id: s};
    expect(byId[1]!.name, 'Aperto');
    expect(byId[1]!.isDefault, isTrue);

    // The values, not just `hasColumn`. The flag was `true` before the drop and cannot come back:
    // the column did not exist, so "no restriction" is the only honest reading — and the next sync
    // is what restores the server's truth.
    expect(byId[1]!.officeOnly, isFalse);
    expect(byId[7]!.name, 'Da ufficio');
    expect(byId[7]!.officeOnly, isFalse);
  });

  test('the flag round-trips after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV60());
    addTearDown(db.close);
    await db.select(db.ticketStatuses).get();

    await (db.update(db.ticketStatuses)..where((s) => s.id.equals(7))).write(
      const TicketStatusesCompanion(officeOnly: Value(true)),
    );

    final statuses = await db.select(db.ticketStatuses).get();
    final byId = {for (final s in statuses) s.id: s};

    expect(byId[7]!.officeOnly, isTrue);
    expect(byId[1]!.officeOnly, isFalse, reason: 'the update is scoped to one row');
  });

  test('a database that already has the column does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 60 on a schema that already carries the column: the guard must skip
    // the add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 60')),
    );
    addTearDown(db.close);

    final statuses = await db.select(db.ticketStatuses).get();
    final byId = {for (final s in statuses) s.id: s};

    expect(statuses, hasLength(2));
    expect(byId[7]!.officeOnly, isTrue, reason: 'the existing value is not reset by the guard path');
  });

  test('schemaVersion has not gone backwards', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(61));
  });
}
