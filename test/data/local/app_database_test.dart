import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// `CREATE TABLE` statements for [tables] exactly as the current schema defines them, read back out
/// of a throwaway in-memory database.
///
/// A hand-written minimal fixture stops being enough the moment a migration step *rewrites* a table
/// instead of adding a column to it. Schema 38 is the first such step: Drift's `alterTable`
/// re-creates `tickets`/`pending_tickets` from their current definition and copies the rows across,
/// selecting **every** current column out of the old table — so an old table missing one fails with
/// `no such column`, whatever the step under test was actually migrating. Taking today's DDL keeps
/// such a fixture working without a hand-copied column list that rots at the next schema change; the
/// caller is responsible for rewinding whatever the version under test did not have yet.
Future<Map<String, String>> _currentTableDdl(List<String> tables) async {
  final schema = AppDatabase(NativeDatabase.memory());
  try {
    // Interpolated rather than bound: every caller passes literal table names.
    final names = tables.map((t) => "'$t'").join(', ');
    final rows = await schema
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name IN ($names)",
        )
        .get();
    return {for (final row in rows) row.read<String>('name'): row.read<String>('sql')};
  } finally {
    await schema.close();
  }
}

/// The `pending_tickets` columns schema 37 adds — i.e. the ones a v33 database does not have yet.
/// A fixture built from today's DDL starts with them, so they have to be taken back off: schema 37
/// runs on the way from 33 to 38, and its `addColumn`s cannot run against a table that already
/// carries them.
const _pendingTicketsColumnsAddedIn37 = [
  'contract_id',
  'commessa_id',
  'cantiere_id',
  'prodotto_assistenza_ids_json',
  'repairable_field',
];

void main() {
  group('Tickets.cantiereId', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('round-trips through insert and select', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Test ticket',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              cantiereId: const Value('cantiere-1'),
            ),
          );

      final row = await (db.select(
        db.tickets,
      )..where((t) => t.id.equals('t1'))).getSingle();

      expect(row.cantiereId, 'cantiere-1');
    });

    test('defaults to null when not set', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Test ticket 2',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final row = await (db.select(
        db.tickets,
      )..where((t) => t.id.equals('t2'))).getSingle();

      expect(row.cantiereId, isNull);
    });
  });

  group('TicketMateriali', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('round-trips through insert and select', () async {
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              ticketId: 'ticket1',
              materialeId: const Value('mat1'),
              quantity: 3,
              unitOfMeasure: const Value('pz'),
              isAvailable: const Value(true),
            ),
          );

      final row = await (db.select(
        db.ticketMateriali,
      )..where((m) => m.id.equals('tm1'))).getSingle();

      expect(row.ticketId, 'ticket1');
      expect(row.materialeId, 'mat1');
      expect(row.quantity, 3);
      expect(row.unitOfMeasure, 'pz');
      expect(row.isAvailable, isTrue);
    });

    test('a free-text item has no materialeId', () async {
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm2',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              ticketId: 'ticket1',
              freeTextName: const Value('Vite generica'),
              quantity: 5,
            ),
          );

      final row = await (db.select(
        db.ticketMateriali,
      )..where((m) => m.id.equals('tm2'))).getSingle();

      expect(row.materialeId, isNull);
      expect(row.freeTextName, 'Vite generica');
      expect(row.isAvailable, isFalse, reason: 'defaults to false, not yet warehouse-confirmed');
    });
  });
  group('schema 34 — DraftReports submissionAttempts/submissionErrorTransient', () {
    late Map<String, String> realTableDdl;

    setUpAll(() async {
      realTableDdl = await _currentTableDdl(['tickets', 'pending_tickets']);
    });

    test('upgrading from 33 adds both columns with defaults and keeps existing rows', () async {
      // A v33 database as far as this migration step is concerned: just a draft_reports table
      // without the two new columns, holding one pre-existing row. `setup` runs on the raw
      // sqlite handle before drift reads user_version and picks the upgrade path.
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('PRAGMA user_version = 33;');
            raw.execute(
              'CREATE TABLE draft_reports (id TEXT NOT NULL PRIMARY KEY, '
              "submission_state TEXT NOT NULL DEFAULT 'draft');",
            );
            raw.execute('CREATE TABLE report_controlli (id TEXT NOT NULL PRIMARY KEY);');
            // `tickets` and `pending_tickets` at their real shape: the chain continues past this
            // step, and schema 38's `alterTable` copies every current column out of both (see
            // [_currentTableDdl]). `pending_tickets` is then rewound to what v33 held — schema 37 is
            // what adds those five columns, and it runs before 38 does.
            for (final sql in realTableDdl.values) {
              raw.execute(sql);
            }
            for (final column in _pendingTicketsColumnsAddedIn37) {
              raw.execute('ALTER TABLE pending_tickets DROP COLUMN $column');
            }
            raw.execute("INSERT INTO draft_reports (id, submission_state) VALUES ('old', 'failed');");
            raw.execute(
              "INSERT INTO draft_reports (id, submission_state) VALUES ('ok', 'readyToSubmit');",
            );
          },
        ),
      );
      addTearDown(db.close);

      final cols = await db
          .customSelect('PRAGMA table_info(draft_reports)')
          .map((r) => r.read<String>('name'))
          .get();
      expect(cols, containsAll(['submission_attempts', 'submission_error_transient']));

      final row = await db
          .customSelect(
            'SELECT submission_state, submission_attempts, submission_error_transient '
            "FROM draft_reports WHERE id = 'old'",
          )
          .getSingle();
      expect(row.read<String>('submission_state'), 'failed'); // untouched
      expect(row.read<int>('submission_attempts'), 0);
      // A row stuck `failed` by the old firma-* 404 bug is flagged transient so the next
      // startup flush retries it (bounded by the queue's retry cap).
      expect(row.read<int>('submission_error_transient'), 1);

      final other = await db
          .customSelect(
            'SELECT submission_error_transient FROM draft_reports '
            "WHERE id = 'ok'",
          )
          .getSingle();
      expect(other.read<int>('submission_error_transient'), 0);
    });

    test('a fresh database has the columns with defaults', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'd1',
              tenantId: 't',
              createdAt: DateTime.utc(2026, 9, 30),
              title: 'x',
              insertedUserId: 'u',
              locationId: 'l',
            ),
          );
      final row = await (db.select(db.draftReports)..where((r) => r.id.equals('d1'))).getSingle();
      expect(row.submissionAttempts, 0);
      expect(row.submissionErrorTransient, isFalse);
    });
  });
}
