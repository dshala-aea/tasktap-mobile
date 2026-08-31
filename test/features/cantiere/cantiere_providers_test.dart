// Tests for the Cantieri tab's read-only providers.
//
// Uses an in-memory Drift DB — no network, no file system.
// Verifies:
//   - cantiereByIdProvider: returns the matching cantiere, or null when none matches
//   - ticketsForCantiereProvider: returns only tickets whose cantiereId matches

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('cantiereByIdProvider', () {
    test('returns the matching cantiere', () async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Test',
            ),
          );

      final result = await container.read(cantiereByIdProvider('c1').future);

      expect(result?.name, 'Cantiere Test');
    });

    test('returns null when no cantiere matches', () async {
      final result = await container.read(
        cantiereByIdProvider('missing').future,
      );

      expect(result, isNull);
    });
  });

  group('ticketsForCantiereProvider', () {
    test('returns only tickets linked to that cantiere', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Linked',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              cantiereId: const Value('cantiere-1'),
            ),
          );
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Unlinked',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final result = await container.read(
        ticketsForCantiereProvider('cantiere-1').future,
      );

      expect(result.map((t) => t.id), ['t1']);
    });
  });
}
