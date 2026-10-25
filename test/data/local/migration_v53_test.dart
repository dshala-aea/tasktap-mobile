// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 52 -> 53: the cantiere site-hours mirror.
///
/// Site time was readable only while online: the device's only local trace was `cantiere_punches`,
/// an outbox that empties as it drains, so a technician with no signal could not look back at the
/// shift they worked yesterday. `cantiere_work_logs` is the read mirror — upserted by the sync from
/// the server's own rows and pruned from its manifest. It is deliberately NOT the outbox.
///
/// A NEW table, so `createTable` is additive on its own and needs no `PRAGMA table_info` guard;
/// drift emits `CREATE TABLE IF NOT EXISTS`, which is also what keeps the older-version fixtures
/// working when they rewind a current-schema database.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig53_');
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

  /// Rewinds the file to the shape a real v52 database has: no `cantiere_work_logs` table at all.
  NativeDatabase rewindToV52() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('DROP TABLE cantiere_work_logs');
      raw.execute('PRAGMA user_version = 52');
    },
  );

  test('a v52 database gains the cantiere_work_logs table and its index', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV52());
    addTearDown(db.close);
    await db.select(db.cantiereWorkLogs).get();

    expect(await hasTable(db, 'cantiere_work_logs'), isTrue);
    final indexes = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'cantiere_work_logs'",
    ).get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('cantiere_work_logs_site'),
      reason: 'the detail screen reads one site, newest first; without it that is a full scan',
    );
  });

  test('the ticket and the owed punch it already held survive the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV52());
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

  test('a mirrored shift written after the migration round-trips', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV52());
    addTearDown(db.close);
    await db.select(db.cantiereWorkLogs).get();

    await db
        .into(db.cantiereWorkLogs)
        .insert(
          CantiereWorkLogsCompanion.insert(
            id: 'w1',
            cantiereId: 'site-1',
            userId: 'user-1',
            workDate: DateTime.utc(2026, 10, 22),
            startSeconds: 8 * 3600,
            endSeconds: const Value((12 * 3600) + (30 * 60)),
            startUtc: Value(DateTime.utc(2026, 10, 22, 6)),
            endUtc: Value(DateTime.utc(2026, 10, 22, 10, 30)),
            approvalStatus: const Value(2),
            clientId: const Value('device-key-1'),
            createdAt: DateTime.utc(2026, 10, 22, 6),
          ),
        );

    final row = await (db.select(
      db.cantiereWorkLogs,
    )..where((w) => w.id.equals('w1'))).getSingle();
    expect(row.startSeconds, 8 * 3600);
    expect(row.endSeconds, (12 * 3600) + (30 * 60));
    expect(row.approvalStatus, 2);
    expect(row.clientId, 'device-key-1');
    expect(row.startUtc!.toUtc(), DateTime.utc(2026, 10, 22, 6));
    expect(row.workLogType, 0, reason: 'the default is Site, never a null enum');
  });

  test('a database that already has the table does not die on a duplicate create', () async {
    await seedCurrent();

    // user_version rewound to 52 on a schema that already carries the table: `CREATE TABLE IF NOT
    // EXISTS` must skip instead of failing before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 52')),
    );
    addTearDown(db.close);

    expect(await db.select(db.cantiereWorkLogs).get(), isEmpty);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(53));
  });
}
