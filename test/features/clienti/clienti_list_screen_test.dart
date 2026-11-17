// test/features/clienti/clienti_list_screen_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/clienti/clienti_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildList({
  required AppDatabase db,
  required MockAuthRepository repo,
  Entitlement? cachedEntitlement,
}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
      if (cachedEntitlement != null)
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(cachedEntitlement),
        ),
    ],
    child: const MaterialApp(home: ClientiListScreen()),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    Entitlement? cachedEntitlement,
  }) async {
    await tester.pumpWidget(
      _buildList(db: db, repo: repo, cachedEntitlement: cachedEntitlement),
    );
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedStatuses(AppDatabase db) async {
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
  }

  Future<void> seedCustomers(AppDatabase db) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2021, 1, 1),
            companyName: 'ACME Srl',
            city: const Value(' Milano '),
            taxId: const Value('01234567890'),
          ),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2023, 1, 2),
            companyName: 'Beta SpA',
            city: const Value('Roma'),
          ),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-3',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2020, 1, 2),
            companyName: 'Gamma Snc',
            city: const Value('Milano'),
            isActive: const Value(false),
          ),
        );
  }

  Future<void> seedTickets(AppDatabase db) async {
    await seedStatuses(db);
    Future<void> ticket(String id, String customerId, int statusId) => db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Ticket $id',
            customerId: customerId,
            locationId: 'loc-1',
            statusId: statusId,
            typeId: 1,
          ),
        );
    await ticket('t1', 'cust-1', 1);
    await ticket('t2', 'cust-1', 1);
    await ticket('t3', 'cust-1', 2);
    await ticket('t4', 'cust-2', 1);
    await ticket('t5', 'cust-3', 1);
  }

  Future<void> seedContracts(AppDatabase db) async {
    Future<void> contract(String id, String customerId, bool isActive) => db
        .into(db.contracts)
        .insert(
          ContractsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Contratto $id',
            customerId: customerId,
            startDate: DateTime.utc(2026, 1, 1),
            isActive: Value(isActive),
          ),
        );
    await contract('c1', 'cust-1', true);
    await contract('c2', 'cust-1', true);
    await contract('c3', 'cust-1', false);
    await contract('c4', 'cust-2', true);
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the not-downloaded state before the first sync', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Clienti non ancora scaricati'), findsOneWidget);
    expect(find.text('Nessun cliente'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('after a sync, an empty mirror reads as "no customers"', (
    tester,
  ) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await pump(tester);
    expect(find.text('Nessun cliente'), findsOneWidget);
    expect(find.text('Clienti non ancora scaricati'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a search that matches nothing is "no result", never "no customers"',
    (tester) async {
      await db.setLastSync(DateTime.utc(2026, 10, 1));
      await seedCustomers(db);
      await pump(tester);

      await tester.enterText(find.byType(TextField).first, 'inesistente');
      await tester.pumpAndSettle();

      expect(find.text('Nessun risultato'), findsOneWidget);
      expect(find.text('Nessun cliente'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('renders one document row per active customer by default', (
    tester,
  ) async {
    await seedCustomers(db);
    await pump(tester);

    expect(find.byType(ListDocumentRow), findsNWidgets(2));
    expect(find.text('ACME Srl'), findsOneWidget);
    expect(find.text('Beta SpA'), findsOneWidget);
    expect(find.text('Gamma Snc'), findsNothing);
    expect(find.text('Attivi'), findsOneWidget);
    expect(find.text('Inattivi'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the Tutti chip renders the Attivi and Inattivi groups', (
    tester,
  ) async {
    await seedCustomers(db);
    await pump(tester);

    await tester.tap(find.text('TUTTI'));
    await tester.pumpAndSettle();

    expect(find.byType(ListDocumentRow), findsNWidgets(3));
    expect(find.text('Attivi'), findsOneWidget);
    expect(find.text('Inattivi'), findsOneWidget);
    expect(find.text('Gamma Snc'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the Inattivi chip shows only inactive customers', (
    tester,
  ) async {
    await seedCustomers(db);
    await pump(tester);

    await tester.tap(find.text('INATTIVI'));
    await tester.pumpAndSettle();

    expect(find.byType(ListDocumentRow), findsOneWidget);
    expect(find.text('Gamma Snc'), findsOneWidget);
    expect(find.text('ACME Srl'), findsNothing);
    expect(find.text('Inattivi'), findsOneWidget);
    expect(find.text('Attivi'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('search narrows by company name, city and P.IVA', (tester) async {
    await seedCustomers(db);
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'acme');
    await tester.pumpAndSettle();
    expect(find.text('ACME Srl'), findsOneWidget);
    expect(find.text('Beta SpA'), findsNothing);

    await tester.enterText(find.byType(TextField), 'roma');
    await tester.pumpAndSettle();
    expect(find.text('Beta SpA'), findsOneWidget);
    expect(find.text('ACME Srl'), findsNothing);

    await tester.enterText(find.byType(TextField), '01234567890');
    await tester.pumpAndSettle();
    expect(find.text('ACME Srl'), findsOneWidget);
    expect(find.text('Beta SpA'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('row meta counts open tickets and active contracts', (
    tester,
  ) async {
    await seedCustomers(db);
    await seedTickets(db);
    await seedContracts(db);
    await pump(tester);

    expect(find.text('Milano · 2 ticket aperti · 2 contratti'), findsOneWidget);
    expect(find.text('Cliente dal 2021'), findsOneWidget);
    expect(find.text('ATTIVO'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('inactive rows carry an Inattivo stamp', (tester) async {
    await seedCustomers(db);
    await seedTickets(db);
    await pump(tester);

    await tester.tap(find.text('INATTIVI'));
    await tester.pumpAndSettle();

    expect(find.text('INATTIVO'), findsOneWidget);
    expect(find.text('ATTIVO'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('summary counts the filtered set', (tester) async {
    await seedCustomers(db);
    await pump(tester);

    expect(find.text('2 CLIENTI'), findsOneWidget);
    expect(find.text('2 ATTIVI'), findsOneWidget);

    await tester.tap(find.text('TUTTI'));
    await tester.pumpAndSettle();

    expect(find.text('3 CLIENTI'), findsOneWidget);
    expect(find.text('2 ATTIVI'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the Filtri sheet filters by city', (tester) async {
    await seedCustomers(db);
    await pump(tester);
    await openFilters(tester);

    await tester.tap(find.byKey(const Key('clienti-filter-city')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roma').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clienti-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Beta SpA'), findsOneWidget);
    expect(find.text('ACME Srl'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a city with stray whitespace still matches the city facet', (
    tester,
  ) async {
    await seedCustomers(db);
    await pump(tester);
    await openFilters(tester);

    await tester.tap(find.byKey(const Key('clienti-filter-city')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milano').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clienti-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('ACME Srl'), findsOneWidget);
    expect(find.text('Beta SpA'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the Filtri sheet filters by active contract', (tester) async {
    await seedCustomers(db);
    await seedContracts(db);
    await pump(tester);
    await openFilters(tester);

    await tester.tap(find.byKey(const Key('clienti-filter-contracts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Senza contratto attivo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clienti-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('ACME Srl'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the Filtri sheet can require an open ticket', (tester) async {
    await seedCustomers(db);
    await seedTickets(db);
    await pump(tester);
    await openFilters(tester);

    await tester.tap(find.byKey(const Key('clienti-filter-open-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clienti-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('ACME Srl'), findsOneWidget);
    expect(find.text('Beta SpA'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Azzera clears the sheet and restores the default chip', (
    tester,
  ) async {
    await seedCustomers(db);
    await pump(tester);

    await tester.tap(find.text('TUTTI'));
    await tester.pumpAndSettle();
    expect(find.text('Gamma Snc'), findsOneWidget);

    await openFilters(tester);
    await tester.tap(find.byKey(const Key('clienti-filter-reset')));
    await tester.pumpAndSettle();

    expect(find.text('Gamma Snc'), findsNothing);
    expect(find.text('ACME Srl'), findsOneWidget);
    expect(find.text('2 CLIENTI'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Nuovo is shown when clienti.customer.write is held', (
    tester,
  ) async {
    await pump(
      tester,
      cachedEntitlement: Entitlement(
        features: {},
        capabilities: {'clienti.customer.write'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 23),
      ),
    );
    expect(find.byType(ListHeaderAction), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Nuovo is hidden when clienti.customer.write is denied', (
    tester,
  ) async {
    await pump(
      tester,
      cachedEntitlement: Entitlement(
        features: {},
        capabilities: {'clienti.customer.read'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 23),
      ),
    );
    expect(find.byType(ListHeaderAction), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a status-only filter that matches nothing says no result', (
    tester,
  ) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'only-inactive',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2021, 1, 1),
            companyName: 'Gamma Snc',
            isActive: const Value(false),
          ),
        );
    await pump(tester);

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Nessun cliente'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('renders without overflow at 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedCustomers(db);
    await seedTickets(db);
    await seedContracts(db);
    await pump(tester);

    expect(tester.takeException(), null);
    expect(find.text('ACME Srl'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
