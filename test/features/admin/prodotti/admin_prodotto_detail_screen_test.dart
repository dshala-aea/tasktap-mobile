// dart format width=100
// test/features/admin/prodotti/admin_prodotto_detail_screen_test.dart

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/auth/access.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/extension_fields/extension_fields_api_client.dart';
// Hides the Drift row class of the same name: `Entitlement` below is the entitlement repository's.
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_detail_screen.dart';

class MockDio extends Mock implements Dio {}

class _FakeExtensionFieldsApiClient implements ExtensionFieldsApiClient {
  _FakeExtensionFieldsApiClient({required this.defs, required this.values});

  final List<ExtensionFieldDefinitionDto> defs;
  final Map<String, String> values;

  String? definitionsEntityType;
  (String, String)? valuesKey;
  (String, String, Map<String, String>)? saved;

  @override
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) async {
    definitionsEntityType = entityType;
    return defs;
  }

  @override
  Future<Map<String, String>> fetchValues(String entityType, String entityId) async {
    valuesKey = (entityType, entityId);
    return values;
  }

  @override
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) async {
    saved = (entityType, entityId, values);
    this.values
      ..clear()
      ..addAll(values);
  }
}

Response<T> _ok<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

Entitlement _entitlementWith(Set<String> capabilities) => Entitlement(
  features: const {},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 9, 23),
);

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;
  late _FakeExtensionFieldsApiClient extensionFields;

  const prodotto = {
    'id': 'prod-1',
    'name': 'Caldaia',
    'customerId': 'cust-1',
    'locationId': 'loc-1',
    'isActive': true,
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();
    extensionFields = _FakeExtensionFieldsApiClient(
      defs: [
        const ExtensionFieldDefinitionDto(
          id: 'def-1',
          key: 'codice_impianto',
          label: 'Codice impianto',
          entityType: 'prodottoassistenza',
          fieldType: 'text',
          isRequired: false,
          showInCard: false,
          sortOrder: 0,
        ),
      ],
      values: {'codice_impianto': 'IMP-9'},
    );

    when(() => mockDio.get<List<dynamic>>('/api/prodottoassistenza/prod-1/matricole')).thenAnswer(
      (_) async => _ok([
        {'id': 'm1', 'numero': 'SN-001', 'note': null},
      ], '/api/prodottoassistenza/prod-1/matricole'),
    );

    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/prodottoassistenza/prod-1/matricole',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok({'id': 'm2'}, '/api/prodottoassistenza/prod-1/matricole'));

    when(
      () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1/matricole/m1'),
    ).thenAnswer((_) async => _ok(null, '/api/prodottoassistenza/prod-1/matricole/m1'));

    when(
      () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1'),
    ).thenAnswer((_) async => _ok(null, '/api/prodottoassistenza/prod-1'));
  });

  tearDown(() async => db.close());

  // Edit and delete are contract-write operations; the tests below act as someone who holds it.
  var entitlement = _entitlementWith({'contratti.contract.write'});
  setUp(() => entitlement = _entitlementWith({'contratti.contract.write'}));

  Widget buildHarness({Map<String, dynamic> data = prodotto}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Apri dettaglio'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => AdminProdottoDetailScreen(prodotto: data),
        ),
      ],
    );

    return ProviderScope(retry: (_, _) => null, 
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(true),
        extensionFieldsApiClientProvider.overrideWithValue(extensionFields),
        cachedEntitlementProvider.overrideWith((ref) => Future.value(entitlement)),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 5, 12)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> seedCustomer() async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2021, 4, 12),
            companyName: 'Rossi Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2022, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );
  }

  Future<void> seedTicket({
    String id = 't1',
    String title = 'Manutenzione caldaia',
    String? numero = 'INT-2026-0412',
    bool closed = false,
  }) async {
    await db
        .into(db.ticketStatuses)
        .insertOnConflictUpdate(
          TicketStatusesCompanion.insert(
            id: const Value(1),
            tenantId: 'tenant-1',
            name: closed ? 'Chiuso' : 'Aperto',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 10, 3, 9),
            title: title,
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            numero: Value(numero),
            prodottoAssistenzaIdsJson: const Value('["prod-1"]'),
            closedAt: Value(closed ? DateTime.utc(2026, 10, 4) : null),
          ),
        );
  }

  /// [size] is taller than a phone for the tests that assert on content below the fold (the
  /// extension-fields section) — a `CustomScrollView` only builds the slivers in view.
  Future<void> openDetail(
    WidgetTester tester, {
    Size size = const Size(800, 1600),
    Map<String, dynamic> data = prodotto,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(buildHarness(data: data));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri dettaglio'));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('redesigned summary shell', () {
    testWidgets('renders the hero, Modifica and no FAB', (tester) async {
      await seedCustomer();
      await openDetail(tester);

      expect(find.byKey(const Key('detail-hero-card')), findsOneWidget);
      expect(find.text('Caldaia'), findsOneWidget);
      expect(find.text('Modifica'), findsWidgets);
      expect(find.byType(FloatingActionButton), findsNothing);
      await teardown(tester);
    });

    testWidgets('hero facts carry cliente, serial and last maintenance', (tester) async {
      await seedCustomer();
      await openDetail(
        tester,
        data: const {
          'id': 'prod-1',
          'name': 'Caldaia Vaillant',
          'customerId': 'cust-1',
          'locationId': 'loc-1',
          'isActive': true,
          'serialNumber': 'SN-9',
          'ultimaManutenzione': '2026-10-03T00:00:00Z',
        },
      );

      expect(find.text('Rossi Srl · SN-9 · ultima 03/10'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('warranty status is derived from the expiry date', (tester) async {
      await openDetail(
        tester,
        data: const {
          'id': 'prod-1',
          'name': 'Caldaia',
          'customerId': 'cust-1',
          'locationId': 'loc-1',
          'isActive': true,
          'warrantyExpiryDate': '2027-06-01T00:00:00Z',
        },
      );

      expect(find.text('IN GARANZIA'), findsWidgets);
      await teardown(tester);
    });

    testWidgets('sections run Attività → Sintesi → Relazioni and Documenti is hidden', (
      tester,
    ) async {
      await seedCustomer();
      await seedTicket();
      await openDetail(tester);

      final attivita = tester.getTopLeft(find.text('Attività')).dy;
      final sintesi = tester.getTopLeft(find.text('Sintesi')).dy;
      final relazioni = tester.getTopLeft(find.text('Relazioni')).dy;
      expect(attivita, lessThan(sintesi));
      expect(sintesi, lessThan(relazioni));
      expect(find.text('Documenti'), findsNothing);
      await teardown(tester);
    });

    testWidgets('empty sections are hidden', (tester) async {
      await openDetail(tester, data: const {'id': 'prod-1', 'name': 'Caldaia', 'isActive': true});

      expect(find.text('Attività'), findsNothing);
      expect(find.text('Relazioni'), findsNothing);
      expect(find.text('Documenti'), findsNothing);
      await teardown(tester);
    });

    testWidgets('320px does not overflow with long real strings', (tester) async {
      await seedCustomer();
      await seedTicket(title: 'Sostituzione valvola e controllo fumi');
      await openDetail(
        tester,
        size: const Size(320, 900),
        data: const {
          'id': 'prod-1',
          'name': 'Caldaia a condensazione Vaillant EcoTEC Plus',
          'customerId': 'cust-1',
          'locationId': 'loc-1',
          'isActive': true,
          'codice': 'CAL-VAILLANT-ECOTEC-PLUS-2024',
          'serialNumber': 'SN-000000009',
          'marchio': 'Vaillant',
          'modello': 'EcoTEC Plus VU IT 246/5-5',
          'tipo': 'Caldaia a condensazione',
          'categoria': 'Caldaie e scaldabagni',
          'um': 'pezzo',
          'warrantyExpiryDate': '2027-06-01T00:00:00Z',
          'ultimaManutenzione': '2026-10-03T00:00:00Z',
          'prossimaManutenzione': '2026-12-03T00:00:00Z',
          'dataInstallazione': '2024-05-10T00:00:00Z',
          'externalId': 'EXT-PRODOTTO-ASSISTENZA-0001',
          'description': 'Caldaia a condensazione installata in centrale termica.',
          'notes': 'Accesso dalla scala interna.',
        },
      );

      expect(tester.takeException(), isNull);
      await teardown(tester);
    });
  });

  group('Matricole (Gap 3)', () {
    testWidgets('lists matricole from the live GET fetch', (tester) async {
      await openDetail(tester);

      expect(find.text('SN-001'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('adding a matricola posts numero and refreshes the list', (tester) async {
      await openDetail(tester);

      await tester.tap(find.byTooltip('Aggiungi matricola'));
      await tester.pumpAndSettle();

      final sheetFields = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(sheetFields.first, 'SN-002');
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Salva')));
      await tester.pumpAndSettle();

      final captured =
          verify(
                () => mockDio.post<Map<String, dynamic>>(
                  '/api/prodottoassistenza/prod-1/matricole',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map;
      expect(captured['numero'], 'SN-002');
      await teardown(tester);
    });

    testWidgets('removing a matricola confirms then DELETEs', (tester) async {
      await openDetail(tester);

      await tester.tap(find.byTooltip('Rimuovi matricola'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi').last);
      await tester.pumpAndSettle();

      verify(
        () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1/matricole/m1'),
      ).called(1);
      await teardown(tester);
    });
  });

  group('delete prodotto (Gap 5)', () {
    testWidgets('confirms then DELETEs and pops', (tester) async {
      await openDetail(tester);

      await tester.tap(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina asset'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina').last);
      await tester.pumpAndSettle();

      verify(() => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1')).called(1);
      expect(find.text('Apri dettaglio'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a user without contract-write is not offered edit or delete', (tester) async {
      entitlement = _entitlementWith({'contratti.contract.read'});
      await openDetail(tester, size: const Size(800, 2800));

      expect(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina asset'),
        findsNothing,
      );
      // The hero's primary action stays visible but disabled and explains why, instead of the
      // whole action disappearing.
      expect(find.text('Modifica'), findsWidgets);
      expect(find.text(noPermissionReason), findsOneWidget);
      // Matricole are a contract-write sub-resource: no add/remove, and the extension fields are
      // read-only rather than offering a save the server would refuse.
      expect(find.byTooltip('Aggiungi matricola'), findsNothing);
      expect(find.byTooltip('Rimuovi matricola'), findsNothing);
      expect(find.text('Salva'), findsNothing);
      expect(
        find.text('Sola lettura: non hai i permessi per modificare questi campi.'),
        findsOneWidget,
      );
      await teardown(tester);
    });
  });

  group('campi aggiuntivi (asset extension fields)', () {
    testWidgets('reads the asset\'s fields under the backend\'s prodottoassistenza key', (
      tester,
    ) async {
      await openDetail(tester, size: const Size(800, 2800));
      await tester.dragUntilVisible(
        find.text('IMP-9'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );

      expect(extensionFields.definitionsEntityType, 'prodottoassistenza');
      expect(extensionFields.valuesKey, ('prodottoassistenza', 'prod-1'));
      expect(find.text('CODICE IMPIANTO', findRichText: true), findsOneWidget);
      expect(find.text('IMP-9'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('saves what the technician typed against that same key', (tester) async {
      await openDetail(tester, size: const Size(800, 2800));

      await tester.dragUntilVisible(
        find.byType(TextFormField),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.enterText(find.byType(TextFormField), 'IMP-10');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva').last);
      await tester.pumpAndSettle();

      expect(extensionFields.saved, isNotNull);
      expect(
        (extensionFields.saved!.$1, extensionFields.saved!.$2),
        ('prodottoassistenza', 'prod-1'),
      );
      expect(extensionFields.saved!.$3, {'codice_impianto': 'IMP-10'});
      await teardown(tester);
    });
  });
}
