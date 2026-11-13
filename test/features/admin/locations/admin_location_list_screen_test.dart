// dart format width=100
// test/features/admin/locations/admin_location_list_screen_test.dart

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/time/business_time.dart' show BusinessTime, formatWorkDate;
import 'package:tasktap_mobile/core/time/business_time_providers.dart' show businessTimeProvider;
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/locations/admin_location_list_screen.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _buildScreen(AppDatabase db, {Entitlement? entitlement}) => ProviderScope(retry: (_, _) => null, 
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
    if (entitlement != null)
      cachedEntitlementProvider.overrideWith((ref) => Future.value(entitlement)),
  ],
  child: const MaterialApp(home: AdminLocationListScreen()),
);

Future<void> _seedCustomers(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-rossi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Rossi Srl',
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
        ),
      );
}

Future<void> _seedStatuses(AppDatabase db) async {
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
          name: 'Chiuso',
          isClosed: const Value(true),
        ),
      );
}

Future<void> _seedLocations(AppDatabase db) async {
  Future<void> location(
    String id,
    String customerId,
    String name,
    String address,
    String city, {
    bool isActive = true,
  }) => db
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
          isActive: Value(isActive),
        ),
      );

  await location('loc-milano', 'cust-rossi', 'Sede Milano', 'Via Roma 1', 'Milano');
  await location('loc-monza', 'cust-rossi', 'Sede Monza', 'Via Manzoni 4', 'Monza');
  await location('loc-sesto', 'cust-bianchi', 'Sede Sesto', 'Via Verdi 8', 'Sesto');
}

Future<void> _seedTickets(AppDatabase db) async {
  await _seedStatuses(db);
  Future<void> ticket(String id, String locationId, int statusId) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 1),
          title: 'Ticket $id',
          customerId: locationId == 'loc-sesto' ? 'cust-bianchi' : 'cust-rossi',
          locationId: locationId,
          statusId: statusId,
          typeId: 1,
        ),
      );

  await ticket('t1', 'loc-milano', 1);
  await ticket('t2', 'loc-milano', 1);
  await ticket('t3', 'loc-milano', 2);
  await ticket('t4', 'loc-sesto', 1);
  await ticket('t5', 'loc-monza', 2);
}

Future<void> _deactivateCustomer(AppDatabase db, String id) => (db.update(
  db.customers,
)..where((c) => c.id.equals(id))).write(const CustomersCompanion(isActive: Value(false)));

Future<void> _setTicketActivity(AppDatabase db, String id, DateTime at) => (db.update(
  db.tickets,
)..where((t) => t.id.equals(id))).write(TicketsCompanion(updatedAt: Value(at)));

Future<void> _pump(WidgetTester tester, AppDatabase db, {Entitlement? entitlement}) async {
  await tester.pumpWidget(_buildScreen(db, entitlement: entitlement));
  await tester.pumpAndSettle();
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.text('FILTRI'));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('never-synced empty mirror says the sedi were not downloaded', (tester) async {
    await _pump(tester, db);

    expect(find.text('Sedi non ancora scaricate'), findsOneWidget);
    expect(find.text('Nessuna sede'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('a synced, genuinely empty list offers the create action', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await _pump(tester, db);

    expect(find.text('Nessuna sede'), findsOneWidget);
    expect(find.text('Sedi non ancora scaricate'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('a search with no match says no result, not "not downloaded"', (tester) async {
    await _pump(tester, db);

    await tester.enterText(find.byType(TextField), 'sede inesistente');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Sedi non ancora scaricate'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('groups sedi by customer with the prototype row anatomy', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    await _pump(tester, db);

    expect(find.text('Bianchi Srl'), findsOneWidget);
    expect(find.text('Rossi Srl'), findsOneWidget);
    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);

    expect(find.text('Via Roma 1 · 2 ticket aperti'), findsOneWidget);
    expect(find.text('Via Manzoni 4 · 0 ticket'), findsOneWidget);
    expect(find.text('Via Verdi 8 · 1 ticket aperto'), findsOneWidget);
    expect(find.text('ATTIVA'), findsNWidgets(3));

    expect(find.text('3 SEDI'), findsOneWidget);
    expect(find.text('2 CON TICKET'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('group counts follow the filtered set', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    await _pump(tester, db);

    await tester.tap(find.text('CON TICKET'));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Sede Monza'), findsNothing);
    expect(find.text('2 SEDI'), findsOneWidget);
    expect(find.text('2 CON TICKET'), findsOneWidget);

    await tester.tap(find.text('SENZA TICKET'));
    await tester.pumpAndSettle();

    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Milano'), findsNothing);
    expect(find.text('1 SEDE'), findsOneWidget);
    expect(find.text('0 CON TICKET'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('Con ticket and Solo con ticket aperti share one predicate', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterOpenOnly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Sede Monza'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('requiring an open ticket under Senza ticket selects Con ticket', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    await _pump(tester, db);

    await tester.tap(find.text('SENZA TICKET'));
    await tester.pumpAndSettle();
    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterOpenOnly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Sede Monza'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('the Filtri sheet filters by customer and city', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterCliente')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rossi Srl').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsNothing);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterCitta')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monza').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Milano'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('Azzera clears every facet', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _pump(tester, db);

    await tester.tap(find.text('CON TICKET'));
    await tester.pumpAndSettle();
    expect(find.text('Sede Monza'), findsNothing);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterReset')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('search covers sede, cliente, indirizzo and città', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _pump(tester, db);

    await tester.enterText(find.byType(TextField), 'manzoni');
    await tester.pumpAndSettle();
    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Milano'), findsNothing);

    await tester.enterText(find.byType(TextField), 'bianchi');
    await tester.pumpAndSettle();
    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Sede Milano'), findsNothing);

    await tester.enterText(find.byType(TextField), 'sesto');
    await tester.pumpAndSettle();
    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Sede Monza'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('inactive sedi carry an Inattiva stamp', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await (db.update(db.locations)..where((l) => l.id.equals('loc-monza'))).write(
      const LocationsCompanion(isActive: Value(false)),
    );
    await _pump(tester, db);

    expect(find.text('INATTIVA'), findsOneWidget);
    expect(find.text('ATTIVA'), findsNWidgets(2));

    await _dispose(tester);
  });

  testWidgets('a sede without a known customer groups under Senza cliente', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-orfana',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2022, 1, 1),
            customerId: 'missing-customer',
            name: 'Sede Orfana',
            address: const Value('Via Ignota 9'),
          ),
        );
    await _pump(tester, db);

    expect(find.text('Senza cliente'), findsOneWidget);
    expect(find.text('Sede Orfana'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a sede whose customer is inactive keeps the customer name', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _deactivateCustomer(db, 'cust-rossi');
    await _pump(tester, db);

    expect(find.text('Rossi Srl'), findsOneWidget);
    expect(find.text('Senza cliente'), findsNothing);
    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Monza'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the row shows the latest ticket activity or no recent activity', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    final activityAt = DateTime.utc(2026, 11, 12, 12);
    await _setTicketActivity(db, 't1', activityAt);
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-vuota',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2022, 1, 1),
            customerId: 'cust-rossi',
            name: 'Sede Vuota',
            address: const Value('Via Nulla 2'),
          ),
        );
    await _pump(tester, db);

    final label = formatWorkDate(BusinessTime('Europe/Rome').businessDateOf(activityAt), 'dd/MM');
    expect(find.text('Ultima attività $label'), findsOneWidget);
    expect(find.text('Nessuna attività recente'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a deactivated customer filter is dropped, not asserted or hidden', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterCliente')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rossi Srl').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();
    expect(find.text('Sede Sesto'), findsNothing);

    await _deactivateCustomer(db, 'cust-rossi');
    await tester.pumpAndSettle();

    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Rossi Srl'), findsOneWidget);
    await _openFilters(tester);
    expect(tester.takeException(), null);

    await _dispose(tester);
  });

  testWidgets('a vanished city filter is dropped, not asserted or hidden', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterCitta')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milano').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();
    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Monza'), findsNothing);

    await (db.delete(db.locations)..where((l) => l.id.equals('loc-milano'))).go();
    await tester.pumpAndSettle();

    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);
    await _openFilters(tester);
    expect(tester.takeException(), null);

    await _dispose(tester);
  });

  testWidgets('the Filtri sheet status chips filter the list', (tester) async {
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterStatus-conTicket')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Sede Sesto'), findsOneWidget);
    expect(find.text('Sede Monza'), findsNothing);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('sediFilterStatus-senzaTicket')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sediFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Sede Monza'), findsOneWidget);
    expect(find.text('Sede Milano'), findsNothing);
    expect(find.text('Sede Sesto'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('Nuovo is shown only with clienti.location.write', (tester) async {
    await _pump(
      tester,
      db,
      entitlement: Entitlement(
        features: const {},
        capabilities: const {'clienti.location.write'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 23),
      ),
    );
    expect(find.byType(ListHeaderAction), findsOneWidget);

    await _dispose(tester);

    await _pump(
      tester,
      db,
      entitlement: Entitlement(
        features: const {},
        capabilities: const {'clienti.location.read'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 23),
      ),
    );
    expect(find.byType(ListHeaderAction), findsNothing);

    await _dispose(tester);
  });

  testWidgets('renders without overflow at 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _seedCustomers(db);
    await _seedLocations(db);
    await _seedTickets(db);
    await _pump(tester, db);

    expect(tester.takeException(), null);
    expect(find.text('Sede Milano'), findsOneWidget);

    await _dispose(tester);
  });
}
