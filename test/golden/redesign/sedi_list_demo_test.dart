// test/golden/redesign/sedi_list_demo_test.dart
//
// Review artifact for the redesigned Sedi list. Seeds the local Drift mirror with the prototype's
// customers, sedi and open/closed tickets, then writes `build/redesign/sedi_list.png`. Nothing
// here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/sedi_list_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/locations/admin_location_list_screen.dart';

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
  Future<void> customer(String id, String name) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: name,
        ),
      );
  await customer('cust-rossi', 'Rossi Srl');
  await customer('cust-bianchi', 'Bianchi Srl');

  Future<void> location(
    String id,
    String customerId,
    String name,
    String address,
    String city,
  ) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2022, 1, 1),
          customerId: customerId,
          name: name,
          address: Value(address),
          city: Value(city),
        ),
      );
  await location(
    'loc-milano',
    'cust-rossi',
    'Sede Milano',
    'Via Roma 1',
    'Milano',
  );
  await location(
    'loc-monza',
    'cust-rossi',
    'Sede Monza',
    'Via Manzoni 4',
    'Monza',
  );
  await location(
    'loc-sesto',
    'cust-bianchi',
    'Sede Sesto',
    'Via Verdi 8',
    'Sesto',
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

  Future<void> ticket(
    String id,
    String customerId,
    String locationId,
    int statusId,
  ) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 1),
          title: 'Ticket $id',
          customerId: customerId,
          locationId: locationId,
          statusId: statusId,
          typeId: 1,
        ),
      );
  await ticket('t1', 'cust-rossi', 'loc-milano', 1);
  await ticket('t2', 'cust-rossi', 'loc-milano', 1);
  await ticket('t3', 'cust-rossi', 'loc-milano', 2);
  await ticket('t4', 'cust-bianchi', 'loc-sesto', 1);
  await ticket('t5', 'cust-rossi', 'loc-monza', 2);
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Sedi list — writes build/redesign/sedi_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'sedi_list',
      child: const AdminLocationListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'clienti.location.write'},
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
