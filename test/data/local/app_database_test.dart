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
}
