// test/golden/redesign/ticket_list_demo_test.dart
//
// Review artifact for the wave-1 Ticket list redesign: renders the real screen with a realistic
// local fixture and writes `build/redesign/ticket_list.png`. Nothing here compares images, so the
// test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/ticket_list_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/time/business_time.dart' show BusinessTime, formatDateOnly;
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/ticket/ticket_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

import 'redesign_harness.dart';

class _FakeConnectivity extends ConnectivityNotifier {
  @override
  Future<bool> build() async => true;
}

Future<void> _seed(AppDatabase db) async {
  final today = BusinessTime.fallback().businessToday();
  String date(int offsetDays) => formatDateOnly(today.add(Duration(days: offsetDays)))!;

  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Aperto'),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(2),
          tenantId: 'tenant-1',
          name: 'In corso',
          isInProgress: const Value(true),
        ),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(id: const Value(3), tenantId: 'tenant-1', name: 'In attesa'),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(4),
          tenantId: 'tenant-1',
          name: 'Completato',
          isClosed: const Value(true),
        ),
      );

  Future<void> customer(String id, String name, String city) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: name,
          city: Value(city),
        ),
      );
  Future<void> location(String id, String customerId, String name, String city) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: customerId,
          name: name,
          city: Value(city),
        ),
      );

  await customer('cust-1', 'Rossi Srl', 'Milano');
  await customer('cust-2', 'Bianchi Srl', 'Sesto');
  await customer('cust-3', 'Verdi Spa', 'Monza');
  await customer('cust-4', 'Neri Srl', 'Milano');
  await location('loc-1', 'cust-1', 'Sede Milano', 'Milano');
  await location('loc-2', 'cust-2', 'Sede Sesto', 'Sesto');
  await location('loc-3', 'cust-3', 'Sede Monza', 'Monza');
  await location('loc-4', 'cust-4', 'Sede Milano', 'Milano');

  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Daniel Shala'));
  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'u2', displayName: 'Marco Rossi'));
  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'u3', displayName: 'Luca Bianchi'));

  Future<void> ticket({
    required String id,
    required String title,
    required String customerId,
    required String locationId,
    required int statusId,
    required String technicianId,
    required String dueDate,
    required String priority,
    required DateTime createdAt,
  }) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: createdAt,
          title: title,
          customerId: customerId,
          locationId: locationId,
          statusId: statusId,
          typeId: 1,
          dueDate: Value(dueDate),
          priority: Value(priority),
          assignedUserId: Value(technicianId),
        ),
      );

  await ticket(
    id: 't1',
    title: 'Perdita acqua sotto il lavello',
    customerId: 'cust-1',
    locationId: 'loc-1',
    statusId: 2,
    technicianId: 'u1',
    dueDate: date(0),
    priority: 'Alta',
    createdAt: DateTime.utc(2026, 11, 1),
  );
  await ticket(
    id: 't2',
    title: 'Caldaia non parte',
    customerId: 'cust-2',
    locationId: 'loc-2',
    statusId: 1,
    technicianId: 'u2',
    dueDate: date(0),
    priority: 'Media',
    createdAt: DateTime.utc(2026, 11, 1, 9),
  );
  await ticket(
    id: 't3',
    title: 'Sostituzione sifone',
    customerId: 'cust-3',
    locationId: 'loc-3',
    statusId: 1,
    technicianId: 'u3',
    dueDate: date(1),
    priority: 'Bassa',
    createdAt: DateTime.utc(2026, 11, 2),
  );
  await ticket(
    id: 't4',
    title: 'Controllo impianto',
    customerId: 'cust-4',
    locationId: 'loc-4',
    statusId: 3,
    technicianId: 'u1',
    dueDate: date(3),
    priority: 'Alta',
    createdAt: DateTime.utc(2026, 11, 3),
  );

  await db.setLastSync(DateTime.utc(2026, 11, 5, 7, 30));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
    await loadRedesignFonts();
  });

  testWidgets('Ticket list — writes build/redesign/ticket_list.png', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'ticket_list',
      child: const TicketListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWith(_FakeConnectivity.new),
        internalUserIdProvider.overrideWith((ref) async => 'u1'),
        cachedEntitlementProvider.overrideWith(
          (ref) async => Entitlement(
            features: const {'interventi'},
            capabilities: const {'interventi.ticket.write'},
            seatType: 'field',
            fetchedAt: DateTime.utc(2026, 11, 2),
          ),
        ),
      ],
    );

    await db.close();
  });
}
