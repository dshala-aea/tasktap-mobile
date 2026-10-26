// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_repository.dart'
    show decodePendingStringList;

/// Schema 57 -> 59: two fields that were on the wire and never mirrored.
///
/// * `tickets.prodotto_assistenza_ids_json` — the units a job covers, as a JSON list. The table
///   already had a singular `prodotto_assistenza_id`; that column stays (legacy, unread) and this
///   migration does NOT backfill it into the plural, because the singular was never filled by the
///   sync either. The next sync writes the list.
/// * `draft_reports.numero` — the rapportino's human number, server-assigned, so null on a draft
///   created on the device and not yet submitted.
///
/// Neither has a default and nothing is backfilled: null is the true statement about a row written
/// before the column existed. Both are filled by the next sync, and that requires
/// `syncCursorGeneration` bumped to `v16` — the task note claiming a rapportino "is carried in full
/// on every sync" is wrong, `MobileUserSyncService` delta-filters drafts on
/// `(UpdatedAt ?? CreatedAt) > cutoff`.
///
/// The `addColumn`s are guarded by `PRAGMA table_info` rather than by `from`, like schemas 50-57:
/// the older-schema fixtures in test/ rewind `user_version` on the CURRENT schema, which already
/// declares both columns, so an unconditional add would die on `duplicate column name` before the
/// app opens. The first two tests below exercise the real add path on a database that lacks them.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig59_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one job — the shape a technician's device has the moment
  /// before the upgrade. The ticket carries the legacy singular asset so the "no backfill" contract
  /// has something to not-copy.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 24),
            title: 'Sostituzione caldaia',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 2,
            prodottoAssistenzaId: const Value('pa-legacy'),
          ),
        );
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'report-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 24),
            title: 'Rapportino caldaia',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v57 database has: neither column exists.
  ///
  /// 57 and not 58: this branch's ladder ends at the 59 step, so a fixture that claims 58 would skip
  /// the very migration under test. When schema 58 (schedules.is_assenza, a separate branch) lands
  /// first, its step runs here too against a fixture that already declares that column and its own
  /// `PRAGMA` guard skips it — which is why every step since 50 is guarded.
  NativeDatabase rewindToV57() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE tickets DROP COLUMN prodotto_assistenza_ids_json');
      raw.execute('ALTER TABLE draft_reports DROP COLUMN numero');
      raw.execute('PRAGMA user_version = 57');
    },
  );

  test('a v57 database gains both columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);
    await db.select(db.tickets).get();

    expect(await hasColumn(db, 'tickets', 'prodotto_assistenza_ids_json'), isTrue);
    expect(await hasColumn(db, 'draft_reports', 'numero'), isTrue);
  });

  test('a row written before the columns reads null, and the legacy singular is untouched', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);

    final tickets = await db.select(db.tickets).get();
    final reports = await db.select(db.draftReports).get();

    expect(tickets, hasLength(1), reason: 'an additive migration drops no row');
    expect(reports, hasLength(1));
    expect(tickets.single.title, 'Sostituzione caldaia');

    // The values, not just `hasColumn`: the whole point of the pair is what the next sync finds in
    // them, and a wrong default would be invisible above.
    expect(tickets.single.prodottoAssistenzaIdsJson, isNull);
    expect(reports.single.numero, isNull);

    // No backfill from the legacy singular column. Copying it would be a guess dressed as data: the
    // singular was never written by the sync, so a null there says nothing about the plural.
    expect(tickets.single.prodottoAssistenzaId, 'pa-legacy');
  });

  test('both columns round-trip after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV57());
    addTearDown(db.close);
    await db.select(db.tickets).get();

    await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
      TicketsCompanion(
        prodottoAssistenzaIdsJson: Value(jsonEncode(['pa-1', 'pa-2'])),
      ),
    );
    await (db.update(db.draftReports)..where((r) => r.id.equals('report-1'))).write(
      const DraftReportsCompanion(numero: Value('RAP-2026-0042')),
    );

    final ticket = await db.select(db.tickets).getSingle();
    final report = await db.select(db.draftReports).getSingle();

    expect(
      decodePendingStringList(ticket.prodottoAssistenzaIdsJson),
      ['pa-1', 'pa-2'],
      reason: 'the list survives as a list, not as a string',
    );
    expect(report.numero, 'RAP-2026-0042');
  });

  test('a database that already has the columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 57 on a schema that already carries both columns: the guards must skip
    // the adds instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 57')),
    );
    addTearDown(db.close);

    final tickets = await db.select(db.tickets).get();
    expect(tickets, hasLength(1));
    expect(tickets.single.prodottoAssistenzaId, 'pa-legacy');
  });

  test('schemaVersion has not gone backwards', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(59));
  });
}
