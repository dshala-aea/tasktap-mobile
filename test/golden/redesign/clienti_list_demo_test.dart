// test/golden/redesign/clienti_list_demo_test.dart
//
// Review artifact for the redesigned Clienti list. Seeds the local Drift mirror with the
// prototype's three customers and writes `build/redesign/clienti_list.png`; nothing here compares
// images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/clienti_list_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/clienti/clienti_list_screen.dart';

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-rossi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Rossi Srl',
          city: const Value('Milano'),
        ),
      );
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-bianchi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2023, 2, 8),
          companyName: 'Bianchi Srl',
          city: const Value('Sesto'),
        ),
      );
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-neri',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2019, 6, 3),
          companyName: 'Neri Srl',
          city: const Value('Milano'),
          isActive: const Value(false),
        ),
      );

  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(1),
          tenantId: 'tenant-1',
          name: 'Aperto',
        ),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(2),
          tenantId: 'tenant-1',
          name: 'Chiuso',
          isClosed: const Value(true),
        ),
      );

  Future<void> ticket(String id, String customerId, int statusId) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 1),
          title: 'Ticket $id',
          customerId: customerId,
          locationId: 'loc-1',
          statusId: statusId,
          typeId: 1,
        ),
      );
  await ticket('t1', 'cust-rossi', 1);
  await ticket('t2', 'cust-rossi', 1);
  await ticket('t3', 'cust-rossi', 1);
  await ticket('t4', 'cust-rossi', 2);
  await ticket('t5', 'cust-bianchi', 1);

  Future<void> contract(String id, String customerId, int index) => db
      .into(db.contracts)
      .insert(
        ContractsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Contratto $index',
          customerId: customerId,
          startDate: DateTime.utc(2026, 1, 1),
        ),
      );
  await contract('c1', 'cust-rossi', 1);
  await contract('c2', 'cust-rossi', 2);
  await contract('c3', 'cust-rossi', 3);
  await contract('c4', 'cust-rossi', 4);
  await contract('c5', 'cust-bianchi', 5);
  await contract('c6', 'cust-bianchi', 6);
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Clienti list — writes build/redesign/clienti_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'clienti_list',
      child: const ClientiListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'clienti.customer.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 9, 23),
            ),
          ),
        ),
      ],
    );

    await db.close();
  });
}
