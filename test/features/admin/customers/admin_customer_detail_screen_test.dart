// test/features/admin/customers/admin_customer_detail_screen_test.dart
//
// Cliente detail: the wave-0 SummaryHero shell plus the four sections in prototype order
// (Relazioni → Sintesi → Attività → Documenti). Empty sections are hidden; the hero's facts line
// is not repeated in Sintesi; the hero carries the only primary action (no FAB).
//
// CRITICAL: every test that pumps this screen (it watches several Drift streams) MUST end with
// the `teardown` helper below — mirrors the same documented convention in
// admin_cantiere_detail_screen_test.dart, otherwise Drift's StreamQueryStore leaves a pending
// Timer behind and the test framework fails the *next* test with "A Timer is still pending".
//
// The screen stacks several sections in one scroll view — taller than the default 800×600 test
// surface, so `pumpScreen` uses a tall surface (same convention as the cantiere test file).
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/customers/admin_customer_detail_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

Entitlement _entitlementWith(Set<String> capabilities) => Entitlement(
  features: const {},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 1, 1),
);

const _allWrites = {
  'clienti.customer.write',
  'clienti.location.write',
  'contratti.contract.write',
};

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;
  late Entitlement entitlement;

  setUp(() {
    entitlement = _entitlementWith(_allWrites);
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    // Overview endpoint — the section counts/enrichment read. Not under test here; stubbed just so
    // it does not leave a dangling unstubbed-call error in the log.
    when(
      () => mockDio.get<Map<String, dynamic>>(
        any(that: startsWith('/api/app/clienti/')),
      ),
    ).thenAnswer(
      (i) async => _okResponse({
        'id': 'cust-1',
        'ragioneSociale': 'ACME',
        'sediAttive': 0,
        'contratti': 0,
      }, ''),
    );

    // Contratti/Prodotti default to empty unless a test overrides them.
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/contracts',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _okResponse({'items': <dynamic>[]}, '/api/contracts'),
    );
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async =>
          _okResponse({'items': <dynamic>[]}, '/api/prodottoassistenza'),
    );
  });

  tearDown(() async => db.close());

  Future<void> seedCustomer(
    String id, {
    String name = 'ACME Srl',
    String? city,
    String? address,
  }) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: name,
            city: Value(city),
            address: Value(address),
          ),
        );
  }

  Future<void> seedLocation(
    String id, {
    required String customerId,
    required String name,
  }) async {
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: customerId,
            name: name,
          ),
        );
  }

  Future<void> seedContact(
    String id, {
    required String customerId,
    required String name,
  }) async {
    await db
        .into(db.customerContacts)
        .insert(
          CustomerContactsCompanion.insert(
            id: id,
            customerId: customerId,
            name: name,
            role: const Value('Titolare'),
            phone: const Value('3331234567'),
          ),
        );
  }

  Future<void> seedContract(
    String id, {
    required String customerId,
    required String name,
  }) async {
    await db
        .into(db.contracts)
        .insert(
          ContractsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: name,
            customerId: customerId,
            startDate: DateTime.utc(2026, 1, 1),
          ),
        );
  }

  Future<void> seedTicket(
    String id, {
    required String customerId,
    required String title,
  }) async {
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            title: title,
            customerId: customerId,
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );
  }

  Widget buildScreen(String customerId, {bool online = true}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
      isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith(
        (ref) => Future.value(entitlement),
      ),
    ],
    child: MaterialApp(home: AdminCustomerDetailScreen(customerId: customerId)),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    String customerId = 'cust-1',
    bool online = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    await tester.pumpWidget(buildScreen(customerId, online: online));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('SummaryHero shell', () {
    testWidgets('renders the cliente hero, its facts and no FAB', (
      tester,
    ) async {
      await seedCustomer('cust-1', name: 'Rossi Srl', city: 'Milano');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Milano');
      await seedContract('contr-1', customerId: 'cust-1', name: 'Full service');

      await pumpScreen(tester, online: false);

      expect(find.text('SUMMARY · CLIENTE'), findsOneWidget);
      expect(find.text('Rossi Srl'), findsOneWidget);
      expect(find.text('Milano · 1 sede · 1 contratto'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-hero-card')),
          matching: find.text('ATTIVO'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-hero-card')),
          matching: find.text('Modifica'),
        ),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);

      await teardown(tester);
    });

    testWidgets('header overflow is a 44px glass disc that keeps its menu', (
      tester,
    ) async {
      await seedCustomer('cust-1', name: 'Rossi Srl');

      await pumpScreen(tester);

      expect(
        tester.getSize(find.byKey(const Key('customer-overflow-menu'))),
        const Size(44, 44),
      );

      await tester.tap(find.byTooltip('Aggiungi'));
      await tester.pumpAndSettle();
      expect(find.text('Nuova sede'), findsOneWidget);
      expect(find.text('Aggiungi referente'), findsOneWidget);
      expect(find.text('Nuovo asset'), findsOneWidget);
      expect(find.text('Nuovo contratto'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('sections run Relazioni → Sintesi → Attività → Documenti', (
      tester,
    ) async {
      await seedCustomer('cust-1', city: 'Milano', address: 'Via Roma 1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Milano');
      await seedContact('ct-1', customerId: 'cust-1', name: 'Mario Rossi');
      await seedTicket('t-1', customerId: 'cust-1', title: 'Perdita acqua');
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'contr-1',
              'name': 'Full service',
              'customerId': 'cust-1',
              'isActive': true,
            },
          ],
        }, '/api/contracts'),
      );

      await pumpScreen(tester);

      final relazioni = tester.getTopLeft(find.text('Relazioni')).dy;
      final sintesi = tester.getTopLeft(find.text('Sintesi')).dy;
      final attivita = tester.getTopLeft(find.text('Attività')).dy;
      final documenti = tester.getTopLeft(find.text('Documenti')).dy;

      expect(relazioni, lessThan(sintesi));
      expect(sintesi, lessThan(attivita));
      expect(attivita, lessThan(documenti));

      await teardown(tester);
    });

    testWidgets('lays out without overflow at 320px', (tester) async {
      await seedCustomer('cust-1', city: 'Milano', address: 'Via Roma 1');
      await seedLocation(
        'loc-1',
        customerId: 'cust-1',
        name: 'Sede con un nome piuttosto lungo',
      );
      await seedContact('ct-1', customerId: 'cust-1', name: 'Mario Rossi');
      await seedTicket(
        't-1',
        customerId: 'cust-1',
        title: 'Intervento con un titolo lungo',
      );
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'contr-1',
              'name': 'Manutenzione annuale con un nome lungo',
              'customerId': 'cust-1',
              'isActive': true,
              'price': 1200.0,
            },
          ],
        }, '/api/contracts'),
      );
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'prod-1',
              'name': 'Filtro dismesso con un nome lungo',
              'customerId': 'cust-1',
              'isActive': false,
              'serialNumber': 'SN-123456789',
            },
          ],
        }, '/api/prodottoassistenza'),
      );

      await tester.binding.setSurfaceSize(const Size(320, 2600));
      await tester.pumpWidget(buildScreen('cust-1'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await teardown(tester);
    });

    testWidgets('does not repeat the city in the Sintesi facts grid', (
      tester,
    ) async {
      await seedCustomer('cust-1', city: 'Milano', address: 'Via Roma 1');

      await pumpScreen(tester, online: false);

      expect(find.textContaining('Milano'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-facts-grid')),
          matching: find.text('Milano'),
        ),
        findsNothing,
      );

      await teardown(tester);
    });
  });

  group('Sedi group (Relazioni)', () {
    testWidgets('lists only locations belonging to this customer', (
      tester,
    ) async {
      await seedCustomer('cust-1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');
      await seedLocation('loc-2', customerId: 'cust-1', name: 'Sede Sud');
      await seedLocation(
        'loc-3',
        customerId: 'cust-2',
        name: 'Sede di un altro cliente',
      );

      await pumpScreen(tester);

      expect(find.text('SEDI · 2'), findsOneWidget);
      expect(find.text('Sede Nord'), findsOneWidget);
      expect(find.text('Sede Sud'), findsOneWidget);
      expect(find.text('Sede di un altro cliente'), findsNothing);

      await teardown(tester);
    });

    testWidgets('hides Relazioni when the customer has no related records', (
      tester,
    ) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('Relazioni'), findsNothing);
      expect(find.text('SEDI'), findsNothing);

      await teardown(tester);
    });

    testWidgets('delete asks for confirmation, then calls the API on confirm', (
      tester,
    ) async {
      await seedCustomer('cust-1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');
      when(
        () => mockDio.delete<dynamic>('/api/locations/loc-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/locations/loc-1'));

      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Elimina sede'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminare la sede?'), findsOneWidget);

      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      verify(() => mockDio.delete<dynamic>('/api/locations/loc-1')).called(1);

      await teardown(tester);
    });
  });

  group('Documenti (Contratti)', () {
    testWidgets('lists contracts fetched server-side filtered by customerId', (
      tester,
    ) async {
      await seedCustomer('cust-1');
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'contr-1',
              'name': 'Manutenzione annuale',
              'customerId': 'cust-1',
              'isActive': true,
              'price': 120.0,
            },
          ],
        }, '/api/contracts'),
      );

      await pumpScreen(tester);

      expect(find.text('Documenti'), findsOneWidget);
      expect(find.text('Manutenzione annuale'), findsOneWidget);
      expect(find.text('€120.00'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cliente-contratto-contr-1')),
          matching: find.text('ATTIVO'),
        ),
        findsOneWidget,
      );

      final captured =
          verify(
                () => mockDio.get<Map<String, dynamic>>(
                  '/api/contracts',
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map;
      expect(captured['customerId'], 'cust-1');

      await teardown(tester);
    });

    testWidgets('hides Documenti with no contracts', (tester) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('Documenti'), findsNothing);

      await teardown(tester);
    });

    testWidgets(
      'offline lists this customer\'s mirrored contracts, inactive included',
      (tester) async {
        await seedCustomer('cust-1');
        await seedContract(
          'contr-mirror',
          customerId: 'cust-1',
          name: 'Manutenzione annuale',
        );
        await db
            .into(db.contracts)
            .insert(
              ContractsCompanion.insert(
                id: 'contr-old',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                name: 'Contratto cessato',
                customerId: 'cust-1',
                startDate: DateTime.utc(2025, 1, 1),
                isActive: const Value(false),
              ),
            );
        await seedContract(
          'contr-other',
          customerId: 'cust-2',
          name: 'Contratto di un altro cliente',
        );

        await pumpScreen(tester, online: false);

        expect(find.text('Manutenzione annuale'), findsOneWidget);
        expect(find.text('Contratto cessato'), findsOneWidget);
        expect(find.text('Contratto di un altro cliente'), findsNothing);
        verifyNever(
          () => mockDio.get<Map<String, dynamic>>(
            '/api/contracts',
            queryParameters: any(named: 'queryParameters'),
          ),
        );

        await teardown(tester);
      },
    );

    testWidgets(
      'offline on a never-synced device says the contracts were not downloaded',
      (tester) async {
        await seedCustomer('cust-1');

        await pumpScreen(tester, online: false);

        expect(
          find.textContaining('Contratti non disponibili offline'),
          findsOneWidget,
        );
        expect(find.text('Nessun contratto'), findsNothing);

        await teardown(tester);
      },
    );
  });

  group('Referenti group (Relazioni)', () {
    // Technician reachable: the ticket detail's "Cliente" tap pushes this same screen, so what it
    // does with no signal is a field question. The group reads the Drift mirror the sync fills.
    testWidgets('offline renders the contacts this device already holds', (
      tester,
    ) async {
      await seedCustomer('cust-1');
      await seedContact('ct-1', customerId: 'cust-1', name: 'Mario Rossi');

      await pumpScreen(tester, online: false);

      expect(find.text('REFERENTI · 1'), findsOneWidget);
      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.text('TITOLARE · 3331234567'), findsOneWidget);
      // Nothing was fetched: the cache is the answer, not a fallback.
      verifyNever(
        () => mockDio.get<List<dynamic>>(any(that: contains('/contacts'))),
      );
      // Unqueued writes: offline the edit/delete affordances and the add menu entry disappear.
      expect(find.byTooltip('Modifica referente'), findsNothing);
      expect(find.byTooltip('Elimina referente'), findsNothing);
      await tester.tap(find.byTooltip('Aggiungi'));
      await tester.pumpAndSettle();
      expect(find.text('Aggiungi referente'), findsNothing);

      await teardown(tester);
    });

    testWidgets(
      'online offers adding a referente even when the group is empty',
      (tester) async {
        await seedCustomer('cust-1');

        await pumpScreen(tester);

        expect(find.text('Relazioni'), findsNothing);
        await tester.tap(find.byTooltip('Aggiungi'));
        await tester.pumpAndSettle();
        expect(find.text('Aggiungi referente'), findsOneWidget);

        await teardown(tester);
      },
    );
  });

  group('Asset group (Relazioni)', () {
    testWidgets('lists prodotti fetched server-side filtered by customerId', (
      tester,
    ) async {
      await seedCustomer('cust-1');
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'prod-1',
              'name': 'Caldaia condominio',
              'customerId': 'cust-1',
              'isActive': true,
              'serialNumber': 'SN-42',
            },
            {
              'id': 'prod-2',
              'name': 'Filtro dismesso',
              'customerId': 'cust-1',
              'isActive': false,
              'serialNumber': 'SN-10',
            },
          ],
        }, '/api/prodottoassistenza'),
      );

      await pumpScreen(tester);

      expect(find.text('ASSET · 2'), findsOneWidget);
      expect(find.text('Caldaia condominio'), findsOneWidget);
      expect(find.text('SN-42'), findsOneWidget);
      expect(find.text('Filtro dismesso'), findsOneWidget);
      expect(find.text('INATTIVO'), findsOneWidget);

      final captured =
          verify(
                () => mockDio.get<Map<String, dynamic>>(
                  '/api/prodottoassistenza',
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map;
      expect(captured['customerId'], 'cust-1');

      await teardown(tester);
    });

    testWidgets('hides the Asset group with no prodotti', (tester) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('ASSET'), findsNothing);

      await teardown(tester);
    });

    testWidgets(
      'offline lists this customer\'s mirrored assets, without a request',
      (tester) async {
        await seedCustomer('cust-1');
        await db
            .into(db.prodottiAssistenza)
            .insert(
              ProdottiAssistenzaCompanion.insert(
                id: 'prod-mirror',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                name: 'Caldaia condominio',
                customerId: 'cust-1',
                locationId: 'loc-1',
                serialNumber: const Value('SN-42'),
              ),
            );
        await db
            .into(db.prodottiAssistenza)
            .insert(
              ProdottiAssistenzaCompanion.insert(
                id: 'prod-other',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                name: 'Asset di un altro cliente',
                customerId: 'cust-2',
                locationId: 'loc-2',
              ),
            );

        await pumpScreen(tester, online: false);

        expect(find.text('Caldaia condominio'), findsOneWidget);
        expect(find.text('SN-42'), findsOneWidget);
        expect(find.text('Asset di un altro cliente'), findsNothing);
        verifyNever(
          () => mockDio.get<Map<String, dynamic>>(
            '/api/prodottoassistenza',
            queryParameters: any(named: 'queryParameters'),
          ),
        );

        await teardown(tester);
      },
    );

    testWidgets(
      'offline on a never-synced device says the assets were not downloaded',
      (tester) async {
        await seedCustomer('cust-1');

        await pumpScreen(tester, online: false);

        expect(
          find.textContaining('Asset non disponibili offline'),
          findsOneWidget,
        );
        expect(find.text('Nessun asset'), findsNothing);

        await teardown(tester);
      },
    );
  });

  group('Attività', () {
    testWidgets('lists the cliente\'s interventi and opens the ticket', (
      tester,
    ) async {
      await seedCustomer('cust-1');
      await seedTicket(
        't-1',
        customerId: 'cust-1',
        title: 'Perdita acqua caldaia',
      );

      await pumpScreen(tester);

      expect(find.text('Attività'), findsOneWidget);
      expect(find.text('Perdita acqua caldaia'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('hides Attività when there are no interventi', (tester) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('Attività'), findsNothing);

      await teardown(tester);
    });
  });

  group('capability gates', () {
    testWidgets('a read-only seat sees no header actions, menu or row writes', (
      tester,
    ) async {
      entitlement = _entitlementWith(const {});
      await seedCustomer('cust-1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');
      await seedContact('ct-1', customerId: 'cust-1', name: 'Mario Rossi');

      await pumpScreen(tester);

      expect(
        find.byWidgetPredicate(
          (w) => w is HeaderIconBtn && w.label == 'Elimina cliente',
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('customer-overflow-menu')), findsNothing);
      expect(find.text('Modifica'), findsWidgets);
      expect(
        find.text('Non hai i permessi per questa azione.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Modifica sede'), findsNothing);
      expect(find.byTooltip('Elimina sede'), findsNothing);
      expect(find.byTooltip('Modifica referente'), findsNothing);
      expect(find.byTooltip('Elimina referente'), findsNothing);

      await teardown(tester);
    });

    testWidgets('customer write alone keeps Modifica but hides sede writes', (
      tester,
    ) async {
      entitlement = _entitlementWith({'clienti.customer.write'});
      await seedCustomer('cust-1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');
      await seedContact('ct-1', customerId: 'cust-1', name: 'Mario Rossi');

      await pumpScreen(tester);

      expect(
        find.byWidgetPredicate(
          (w) => w is HeaderIconBtn && w.label == 'Elimina cliente',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Modifica sede'), findsNothing);
      expect(find.byTooltip('Modifica referente'), findsOneWidget);

      await tester.tap(find.byTooltip('Aggiungi'));
      await tester.pumpAndSettle();
      expect(find.text('Aggiungi referente'), findsOneWidget);
      expect(find.text('Nuova sede'), findsNothing);
      expect(find.text('Nuovo asset'), findsNothing);
      expect(find.text('Nuovo contratto'), findsNothing);

      await teardown(tester);
    });

    testWidgets(
      'location write alone shows sede writes but hides the delete client action',
      (tester) async {
        entitlement = _entitlementWith({'clienti.location.write'});
        await seedCustomer('cust-1');
        await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');

        await pumpScreen(tester);

        expect(find.byTooltip('Modifica sede'), findsOneWidget);
        expect(find.byTooltip('Elimina sede'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is HeaderIconBtn && w.label == 'Elimina cliente',
          ),
          findsNothing,
        );

        await tester.tap(find.byTooltip('Aggiungi'));
        await tester.pumpAndSettle();
        expect(find.text('Nuova sede'), findsOneWidget);
        expect(find.text('Nuovo asset'), findsNothing);

        await teardown(tester);
      },
    );

    testWidgets(
      'contract write alone offers Nuovo asset and Nuovo contratto only',
      (tester) async {
        entitlement = _entitlementWith({'contratti.contract.write'});
        await seedCustomer('cust-1');

        await pumpScreen(tester);

        await tester.tap(find.byTooltip('Aggiungi'));
        await tester.pumpAndSettle();
        expect(find.text('Nuovo asset'), findsOneWidget);
        expect(find.text('Nuovo contratto'), findsOneWidget);
        expect(find.text('Nuova sede'), findsNothing);
        expect(find.text('Aggiungi referente'), findsNothing);

        await teardown(tester);
      },
    );
  });
}
