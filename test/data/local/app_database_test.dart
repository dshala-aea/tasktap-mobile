import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

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
            raw.execute("INSERT INTO draft_reports (id, submission_state) VALUES ('old', 'failed');");
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
      expect(row.read<int>('submission_error_transient'), 0);
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
