// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 53 -> 54: the ferie/permessi mirror.
///
/// The list was online-only, so with no signal a technician could not see whether the request they
/// filed last week had been approved — the one question the screen exists to answer, and one whose
/// answer was decided days ago. `absence_requests` is the read mirror, replaced wholesale by every
/// sync that carries the member.
///
/// A NEW table, so `createTable` is additive on its own and needs no `PRAGMA table_info` guard;
/// drift emits `CREATE TABLE IF NOT EXISTS`, which is also what keeps the older-version fixtures
/// working when they rewind a current-schema database.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig54_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$table'",
      ).get()).isNotEmpty;

  /// A current-schema database holding one ticket and one still-owed punch — what a technician
  /// must not lose across the upgrade.
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
    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: 'punch-1',
            eventTime: DateTime.utc(2026, 10, 23, 6),
            eventType: 'ingresso',
            cantiereId: const Value('site-1'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v53 database has: no `absence_requests` table at all.
  NativeDatabase rewindToV53() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('DROP TABLE absence_requests');
      raw.execute('PRAGMA user_version = 53');
    },
  );

  test('a v53 database gains the absence_requests table and its index', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV53());
    addTearDown(db.close);
    await db.select(db.absenceRequests).get();

    expect(await hasTable(db, 'absence_requests'), isTrue);
    final indexes = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'absence_requests'",
    ).get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('absence_requests_owner'),
      reason: 'the list reads one user newest-first; without it that is a full scan every open',
    );
  });

  test('the ticket and the owed punch it already held survive the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV53());
    addTearDown(db.close);

    final ticket = await (db.select(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).getSingle();
    expect(ticket.title, 'Caldaia', reason: 'an additive migration drops no row');

    final punch = await (db.select(
      db.cantierePunches,
    )..where((p) => p.id.equals('punch-1'))).getSingle();
    expect(
      punch.isPendingSync,
      isTrue,
      reason: 'the outbox is the device\'s owed work; the upgrade must not drain it',
    );
  });

  test('a mirrored request written after the migration round-trips its civil dates', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV53());
    addTearDown(db.close);
    await db.select(db.absenceRequests).get();

    await db
        .into(db.absenceRequests)
        .insert(
          AbsenceRequestsCompanion.insert(
            id: 'a1',
            requestedByUserId: 'user-1',
            createdByUserId: 'user-1',
            type: 5,
            startDate: '2026-10-22',
            endDate: '2026-10-24',
            startTime: const Value('09:00:00'),
            endTime: const Value('13:00:00'),
            status: 1,
            decidedByUserId: const Value('office-1'),
            decidedAt: Value(DateTime.utc(2026, 10, 21, 10)),
            createdAt: DateTime.utc(2026, 10, 20, 9),
          ),
        );

    final row = await (db.select(
      db.absenceRequests,
    )..where((a) => a.id.equals('a1'))).getSingle();
    expect(
      row.startDate,
      '2026-10-22',
      reason: 'a civil day in TEXT: a dateTime column would render the previous day west of UTC',
    );
    expect(row.endDate, '2026-10-24');
    expect(row.startTime, '09:00:00');
    expect(row.type, 5);
    expect(row.status, 1);
    expect(row.decidedByUserId, 'office-1');
  });

  test('a database that already has the table does not die on a duplicate create', () async {
    await seedCurrent();

    // user_version rewound to 53 on a schema that already carries the table: `CREATE TABLE IF NOT
    // EXISTS` must skip instead of failing before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 53')),
    );
    addTearDown(db.close);

    expect(await db.select(db.absenceRequests).get(), isEmpty);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(54));
  });
}
