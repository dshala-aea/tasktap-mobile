// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 55 -> 56: two fields the payload already carried reach the mirror.
///
///   * `tickets.prodottoAssistenzaIdsJson` — the units a job covers. The server sends the plural
///     list; the client read a singular `prodottoAssistenzaId` that the server never sends, so the
///     Prodotti compartment could name them only by asking the live detail endpoint.
///   * `draft_reports.numero` — the rapportino's human number, the handle the office and the
///     customer quote at each other.
///
/// Purely additive, and both `addColumn`s are guarded by `PRAGMA table_info` rather than by `from`,
/// like schemas 50, 51 and 55: a re-created table or a half-applied step must not kill the app on
/// `duplicate column name` before it opens. Both tables predate v55, so a real v55 device has them.
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

  /// A current-schema database holding the two rows a technician's device has the moment before
  /// the upgrade: a job covering two units, and a rapportino with a number.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 20),
            title: 'Manutenzione caldaia',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            numero: const Value('1042'),
            prodottoAssistenzaIdsJson: const Value('["prod-a","prod-b"]'),
          ),
        );
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'report-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 20),
            title: 'Rapporto di lavoro',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            numero: const Value('778'),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v55 database has: neither new column exists, while both
  /// rows do.
  NativeDatabase rewindToV55() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE tickets DROP COLUMN prodotto_assistenza_ids_json');
      raw.execute('ALTER TABLE draft_reports DROP COLUMN numero');
      raw.execute('PRAGMA user_version = 55');
    },
  );

  test('a v55 database gains both columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV55());
    addTearDown(db.close);
    await db.select(db.tickets).get();

    expect(await hasColumn(db, 'tickets', 'prodotto_assistenza_ids_json'), isTrue);
    expect(await hasColumn(db, 'draft_reports', 'numero'), isTrue);
  });

  test('both rows survive the upgrade, the new columns starting empty', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV55());
    addTearDown(db.close);

    final ticket = await (db.select(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).getSingle();
    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('report-1'))).getSingle();

    expect(ticket.title, 'Manutenzione caldaia', reason: 'an additive migration drops no row');
    expect(report.title, 'Rapporto di lavoro');
    // Null, not a guess: this device has never been told either value, and an empty list would be
    // a claim ("this job covers nothing") the mirror cannot make. `syncCursorGeneration` is bumped
    // to v16 alongside this step because tickets are delta-filtered — an untouched ticket would
    // otherwise keep its empty coverage forever — while the rapportini payload re-sends every Bozza
    // in full, so the number arrives on the next sync either way.
    expect(ticket.numero, '1042', reason: 'the number was already a column before v56');
    expect(ticket.prodottoAssistenzaIdsJson, isNull);
    expect(report.numero, isNull);
  });

  test('both columns round-trip after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV55());
    addTearDown(db.close);
    await db.select(db.tickets).get();

    await (db.update(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).write(
      const TicketsCompanion(prodottoAssistenzaIdsJson: Value('["prod-c"]')),
    );
    await (db.update(
      db.draftReports,
    )..where((r) => r.id.equals('report-1'))).write(const DraftReportsCompanion(numero: Value('779')));

    final ticket = await (db.select(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).getSingle();
    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('report-1'))).getSingle();
    expect(ticket.prodottoAssistenzaIdsJson, '["prod-c"]');
    expect(report.numero, '779');
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 55 on a schema that already carries both columns: the guard must skip
    // the adds instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 55')),
    );
    addTearDown(db.close);

    final ticket = await (db.select(
      db.tickets,
    )..where((t) => t.id.equals('ticket-1'))).getSingle();
    expect(ticket.prodottoAssistenzaIdsJson, '["prod-a","prod-b"]');
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(56));
  });
}
