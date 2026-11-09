// dart format width=100
// test/features/admin/prodotti/admin_prodotto_list_screen_test.dart
//
// The Asset list answers offline from the synced `prodotti_assistenza` mirror and online from
// `GET /api/prodottoassistenza`. These tests pin what each answer may and may not claim:
//   • mirror rows carry the "potrebbero mancare …" line (the sync payload is scoped);
//   • the search box still filters offline — over name, codice, categoria, seriale and customer;
//   • a never-synced device says the assets are unavailable, not that there are none;
//   • a server answer is never labelled as mirrored;
//   • the prototype's title, subtitle, chips, groups, maintenance line and stamp are rendered;
//   • warranty and maintenance predicates have one source (chips = groups = summary).
//
// CRITICAL: every test that pumps a screen watching a Drift stream MUST end with:
//   await tester.pumpWidget(const SizedBox.shrink());
//   await tester.pumpAndSettle();
// to avoid "A Timer is still pending" hangs from Drift's StreamQueryStore.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_list_screen.dart';

/// Fixed "today" for the warranty / maintenance predicates: 5 November 2026 in the business zone.
final _fixedNow = DateTime.utc(2026, 11, 5, 12);

Entitlement _entitlementWith(Set<String> capabilities) => Entitlement(
  features: const {},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 1, 1),
);

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({this.prodotti = const [], this.byQuery = const {}, this.error})
    : super(Dio());

  final List<Map<String, dynamic>> prodotti;

  /// Per-search-term answers, so a test can change what the server returns when the term changes.
  final Map<String, List<Map<String, dynamic>>> byQuery;
  final Object? error;

  int fetchCount = 0;
  String? lastQuery;

  @override
  Future<List<Map<String, dynamic>>> fetchProdottiAssistenza({
    String? customerId,
    String? q,
  }) async {
    fetchCount++;
    lastQuery = q;
    if (error != null) throw error!;
    return byQuery[q ?? ''] ?? prodotti;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Widget _buildScreen({
  required AppDatabase db,
  required AdminApiClient api,
  required bool isOnline,
  String query = '',
  Entitlement? entitlement,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      adminApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(isOnline),
      clockProvider.overrideWithValue(() => _fixedNow),
      cachedEntitlementProvider.overrideWith(
        (ref) => Future.value(entitlement ?? _entitlementWith({'contratti.contract.write'})),
      ),
      // The search box lives in a real StateProvider; this test sets it up-front instead of
      // typing, because the 350ms debounce is not what is under test.
      adminProdottiQueryProvider.overrideWith((ref) => query),
    ],
    child: const MaterialApp(home: AdminProdottoListScreen()),
  );
}

Future<void> _seedCustomer(
  AppDatabase db, {
  String id = 'cust-1',
  String name = 'Rossi Impianti',
}) => db
    .into(db.customers)
    .insert(
      CustomersCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        companyName: name,
      ),
    );

Future<void> _seedLocation(
  AppDatabase db, {
  String id = 'loc-1',
  String customerId = 'cust-1',
  String name = 'Sede Milano',
  String city = 'Milano',
}) => db
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

Future<void> _seedProdotto(
  AppDatabase db, {
  required String id,
  required String name,
  String customerId = 'cust-1',
  String locationId = 'loc-1',
  String? codice,
  String? categoria,
  String? serialNumber,
  bool isActive = true,
}) => db
    .into(db.prodottiAssistenza)
    .insert(
      ProdottiAssistenzaCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        name: name,
        customerId: customerId,
        locationId: locationId,
        isActive: Value(isActive),
        codice: Value(codice),
        categoria: Value(categoria),
        serialNumber: Value(serialNumber),
      ),
    );

Map<String, dynamic> _serverRow({
  required String id,
  required String name,
  String customerId = 'cust-1',
  String customerName = 'Rossi Srl',
  String locationId = 'loc-1',
  bool isActive = true,
  String? serialNumber,
  String? categoria,
  String? warrantyExpiryDate,
  String? prossimaManutenzione,
  String? ultimaManutenzione,
}) => {
  'id': id,
  'name': name,
  'customerId': customerId,
  'customerName': customerName,
  'locationId': locationId,
  'isActive': isActive,
  'serialNumber': serialNumber,
  'categoria': categoria,
  'warrantyExpiryDate': warrantyExpiryDate,
  'prossimaManutenzione': prossimaManutenzione,
  'ultimaManutenzione': ultimaManutenzione,
};

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  group('offline (mirror)', () {
    testWidgets(
      'shows the mirrored assets, resolves customer names, and says the list may be partial',
      (tester) async {
        final db = _makeDb();
        await _seedCustomer(db);
        await _seedProdotto(
          db,
          id: 'p1',
          name: 'Caldaia Rossi',
          codice: 'C-001',
          serialNumber: 'SN-1',
        );
        await db.setLastSync(DateTime.utc(2026, 10, 1));

        await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
        await tester.pumpAndSettle();

        expect(find.text('Caldaia Rossi'), findsOneWidget);
        // Resolved from the customers mirror — an id alone would render as '—'.
        expect(find.text('Rossi Impianti · SN-1'), findsOneWidget);
        expect(find.text('Prodotti in assistenza'), findsOneWidget);
        expect(
          find.text('Dati salvati sul dispositivo: potrebbero mancare asset non ancora scaricati.'),
          findsOneWidget,
        );

        await _disposeScreen(tester);
      },
    );

    testWidgets(
      'the search box filters the mirror by codice, name, categoria, seriale or customer',
      (tester) async {
        final db = _makeDb();
        await _seedCustomer(db, name: 'Alfa Impianti');
        await _seedCustomer(db, id: 'cust-2', name: 'Bianchi Service');
        await _seedProdotto(db, id: 'p1', name: 'Caldaia Rossi', codice: 'C-001');
        await _seedProdotto(db, id: 'p2', name: 'Bruciatore Bianchi', codice: 'C-002');
        await _seedProdotto(db, id: 'p3', name: 'Gruppo Termico', categoria: 'Climatizzazione');
        await _seedProdotto(db, id: 'p4', name: 'Pompa', serialNumber: 'SN-777');
        await _seedProdotto(db, id: 'p5', name: 'Filtro', customerId: 'cust-2');
        await db.setLastSync(DateTime.utc(2026, 10, 1));

        for (final (query, expected, absent) in [
          ('c-002', 'Bruciatore Bianchi', 'Caldaia Rossi'), // codice, case-insensitive
          ('rossi', 'Caldaia Rossi', 'Bruciatore Bianchi'), // name
          ('climatizz', 'Gruppo Termico', 'Caldaia Rossi'), // categoria
          ('sn-777', 'Pompa', 'Caldaia Rossi'), // seriale
          ('bianchi service', 'Filtro', 'Caldaia Rossi'), // customer name
        ]) {
          await tester.pumpWidget(
            _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false, query: query),
          );
          await tester.pumpAndSettle();

          expect(find.textContaining(expected), findsOneWidget, reason: 'query: $query');
          expect(find.textContaining(absent), findsNothing, reason: 'query: $query');

          // Unmount between iterations: re-pumping the same element types keeps the ProviderScope
          // alive, so the screen's state — including the search text — survives into the next pump
          // and every iteration would silently re-run the first query.
          await _disposeScreen(tester);
        }
      },
    );

    testWidgets(
      'a never-synced device says the assets are not available, not that there are none',
      (tester) async {
        final db = _makeDb();

        await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
        await tester.pumpAndSettle();

        expect(find.text('Asset non disponibili offline'), findsOneWidget);
        expect(find.text('Nessun prodotto'), findsNothing);

        await _disposeScreen(tester);
      },
    );

    testWidgets('pulling to refresh the unavailable state surfaces no uncaught error', (
      tester,
    ) async {
      final db = _makeDb();

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();
      expect(find.text('Asset non disponibili offline'), findsOneWidget);

      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<Null>());
      expect(find.text('Asset non disponibili offline'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('a synced-but-empty mirror is a genuine empty list', (tester) async {
      final db = _makeDb();
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Nessun prodotto'), findsOneWidget);
      expect(find.text('Asset non disponibili offline'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('offline, the maintenance toggle is disabled and says why', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedProdotto(db, id: 'p1', name: 'Caldaia Rossi', serialNumber: 'SN-1');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();

      expect(find.text('Non disponibile sui dati salvati sul dispositivo'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isA<Null>());

      await _disposeScreen(tester);
    });

    testWidgets('mirrored rows carry no warranty claim and no maintenance date', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedProdotto(db, id: 'p1', name: 'Caldaia Rossi', serialNumber: 'SN-1');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      // The sync DTO has no warranty/maintenance date: the row falls back to the active stamp and
      // the group has to say the warranty is not registered, not invent one.
      expect(find.text('Senza garanzia registrata'), findsOneWidget);
      expect(find.text('ATTIVO'), findsOneWidget);
      expect(find.textContaining('Prossima manutenzione'), findsNothing);
      expect(find.textContaining('Ultima manutenzione'), findsNothing);

      await _disposeScreen(tester);
    });
  });

  group('online', () {
    testWidgets('the server answer is used as-is, with no mirror notice', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedProdotto(db, id: 'p1', name: 'Asset Vecchio');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(
            id: 'p-server',
            name: 'Asset Nuovo',
            customerName: 'Verdi Service',
            serialNumber: 'SN-9',
          ),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true, query: 'nuovo'));
      await tester.pumpAndSettle();

      expect(find.text('Asset Nuovo'), findsOneWidget);
      expect(find.text('Asset Vecchio'), findsNothing);
      expect(find.textContaining('potrebbero mancare'), findsNothing);
      // The term still goes to the server as `q` — offline fallback must not turn server-side
      // search into a client-side filter over the first page.
      expect(api.lastQuery, 'nuovo');

      await _disposeScreen(tester);
    });

    testWidgets('a request that never arrived falls back to the mirror', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedProdotto(db, id: 'p1', name: 'Caldaia Rossi');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/prodottoassistenza'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Caldaia Rossi'), findsOneWidget);
      expect(find.textContaining('potrebbero mancare'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('renders the prototype title, subtitle, search hint and chips', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [_serverRow(id: 'p1', name: 'Caldaia')],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Prodotti in assistenza'), findsOneWidget);
      expect(find.text('Gli asset del cliente e la loro prossima manutenzione.'), findsOneWidget);
      expect(find.text('Cerca prodotto, seriale, cliente…'), findsOneWidget);
      expect(find.text('TUTTI'), findsOneWidget);
      expect(find.text('IN GARANZIA'), findsOneWidget);
      expect(find.text('GARANZIA SCADUTA'), findsOneWidget);
      expect(find.text('INATTIVI'), findsOneWidget);
      expect(find.text('FILTRI'), findsOneWidget);
      expect(find.text('NUOVO'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('warranty groups and row stamps share one predicate', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(id: 'p1', name: 'Caldaia Vaillant', warrantyExpiryDate: '2027-06-01'),
          _serverRow(id: 'p2', name: 'Caldaia Baxi', warrantyExpiryDate: '2025-01-01'),
          _serverRow(id: 'p3', name: 'Pompa senza garanzia'),
          _serverRow(
            id: 'p4',
            name: 'Bruciatore dismesso',
            isActive: false,
            warrantyExpiryDate: '2027-06-01',
          ),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('In garanzia'), findsOneWidget);
      expect(find.text('Garanzia scaduta'), findsOneWidget);
      expect(find.text('Senza garanzia registrata'), findsOneWidget);
      expect(find.text('Inattivi'), findsOneWidget);

      // One chip label and one row stamp.
      expect(find.text('IN GARANZIA'), findsNWidgets(2));
      expect(find.text('SCADUTA'), findsOneWidget);
      expect(find.text('ATTIVO'), findsOneWidget);
      expect(find.text('INATTIVO'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('the chips filter by the same warranty predicates as the groups', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(id: 'p1', name: 'Caldaia Vaillant', warrantyExpiryDate: '2027-06-01'),
          _serverRow(id: 'p2', name: 'Caldaia Baxi', warrantyExpiryDate: '2025-01-01'),
          _serverRow(id: 'p3', name: 'Bruciatore dismesso', isActive: false),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('IN GARANZIA').first);
      await tester.pumpAndSettle();
      expect(find.text('Caldaia Vaillant'), findsOneWidget);
      expect(find.text('Caldaia Baxi'), findsNothing);
      expect(find.text('Bruciatore dismesso'), findsNothing);

      await tester.tap(find.text('GARANZIA SCADUTA').first);
      await tester.pumpAndSettle();
      expect(find.text('Caldaia Baxi'), findsOneWidget);
      expect(find.text('Caldaia Vaillant'), findsNothing);

      await tester.tap(find.text('INATTIVI').first);
      await tester.pumpAndSettle();
      expect(find.text('Bruciatore dismesso'), findsOneWidget);
      expect(find.text('Caldaia Baxi'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('the row shows cliente · seriale and the next/ultima manutenzione line', (
      tester,
    ) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(
            id: 'p1',
            name: 'Caldaia Vaillant',
            customerName: 'Rossi Srl',
            serialNumber: 'SN-9',
            prossimaManutenzione: '2026-12-03',
          ),
          _serverRow(
            id: 'p2',
            name: 'Caldaia Baxi',
            customerName: 'Verdi Spa',
            serialNumber: 'SN-2',
            warrantyExpiryDate: '2025-01-01',
            ultimaManutenzione: '2026-10-02',
          ),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Rossi Srl · SN-9'), findsOneWidget);
      expect(find.text('Prossima manutenzione 03/12/2026'), findsOneWidget);
      expect(find.text('Verdi Spa · SN-2'), findsOneWidget);
      expect(find.text('Ultima manutenzione 02/10/2026'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('the maintenance-due toggle and the summary share one predicate', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(id: 'p1', name: 'Caldaia in scadenza', prossimaManutenzione: '2026-11-05'),
          _serverRow(id: 'p2', name: 'Caldaia futura', prossimaManutenzione: '2026-12-10'),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('2 PRODOTTI'), findsOneWidget);
      expect(find.text('1 IN SCADENZA'), findsOneWidget);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      expect(find.text('Manutenzione in scadenza'), findsOneWidget);
      await tester.tap(find.text('Manutenzione in scadenza'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Caldaia in scadenza'), findsOneWidget);
      expect(find.text('Caldaia futura'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('the Filtri sheet exposes Cliente, Sede and Categoria', (tester) async {
      final db = _makeDb();
      await _seedLocation(db);
      final api = _FakeAdminApiClient(
        prodotti: [_serverRow(id: 'p1', name: 'Caldaia', categoria: 'Caldaie')],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();

      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('SEDE'), findsOneWidget);
      expect(find.text('CATEGORIA'), findsOneWidget);
      expect(find.text('Manutenzione in scadenza'), findsOneWidget);
      expect(find.text('Applica'), findsOneWidget);
      expect(find.text('Azzera'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('the sheet status chip filters the list; Azzera clears it', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(id: 'p1', name: 'Caldaia Vaillant', warrantyExpiryDate: '2027-06-01'),
          _serverRow(id: 'p2', name: 'Caldaia Baxi', warrantyExpiryDate: '2025-01-01'),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppChip, 'Garanzia scaduta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Caldaia Baxi'), findsOneWidget);
      expect(find.text('Caldaia Vaillant'), findsNothing);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Azzera'));
      await tester.tap(find.text('Azzera'));
      await tester.pumpAndSettle();

      expect(find.text('Caldaia Vaillant'), findsOneWidget);
      expect(find.text('Caldaia Baxi'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('the category facet trims stray spaces on both sides', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(id: 'p1', name: 'Caldaia Vaillant', categoria: ' Caldaie '),
          _serverRow(id: 'p2', name: 'Pompa', categoria: 'Idraulica'),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tutte le categorie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caldaie').hitTestable());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Caldaia Vaillant'), findsOneWidget);
      expect(find.text('Pompa'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('a facet the new search result dropped is cleared instead of crashing', (
      tester,
    ) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(
            id: 'p1',
            name: 'Caldaia Rossi',
            customerId: 'cust-1',
            customerName: 'Rossi Srl',
          ),
          _serverRow(
            id: 'p2',
            name: 'Pompa Bianchi',
            customerId: 'cust-2',
            customerName: 'Bianchi Srl',
          ),
        ],
        byQuery: {
          'bianchi': [
            _serverRow(
              id: 'p2',
              name: 'Pompa Bianchi',
              customerId: 'cust-2',
              customerName: 'Bianchi Srl',
            ),
          ],
        },
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tutti i clienti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rossi Srl').hitTestable());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();
      expect(find.text('Caldaia Rossi'), findsOneWidget);
      expect(find.text('Pompa Bianchi'), findsNothing);

      // A new search term replaces the server answer; the active Cliente facet now points at a
      // customer that is no longer in the result.
      await tester.enterText(find.byType(TextField), 'bianchi');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Nessun risultato'), findsOneWidget);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      expect(find.text('Tutti i clienti'), findsOneWidget);
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Pompa Bianchi'), findsOneWidget);
      expect(find.text('Caldaia Rossi'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('a filter that matches nothing shows the no-result state', (tester) async {
      final db = _makeDb();
      final api = _FakeAdminApiClient(
        prodotti: [
          _serverRow(id: 'p1', name: 'Caldaia Vaillant', warrantyExpiryDate: '2027-06-01'),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('INATTIVI').first);
      await tester.pumpAndSettle();

      expect(find.text('Nessun risultato'), findsOneWidget);
      expect(find.text('Caldaia Vaillant'), findsNothing);

      await _disposeScreen(tester);
    });
  });

  testWidgets('the Filtri sheet does not overflow at 320px', (tester) async {
    final db = _makeDb();
    await _seedLocation(db);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeAdminApiClient(
      prodotti: [_serverRow(id: 'p1', name: 'Caldaia', categoria: 'Caldaie')],
    );

    await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), null);
    expect(find.text('Applica'), findsOneWidget);

    await _disposeScreen(tester);
  });

  testWidgets('the list does not overflow at 320px', (tester) async {
    final db = _makeDb();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeAdminApiClient(
      prodotti: [
        _serverRow(
          id: 'p1',
          name: 'Caldaia Vaillant con un nome molto lungo che deve essere troncato',
          customerName: 'Rossi Impianti Srl con nome lungo',
          serialNumber: 'SN-1234567890',
          prossimaManutenzione: '2026-12-03',
        ),
      ],
    );

    await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), null);

    await _disposeScreen(tester);
  });

  testWidgets('Nuovo is hidden without contract write', (tester) async {
    final db = _makeDb();
    final api = _FakeAdminApiClient(
      prodotti: [_serverRow(id: 'p1', name: 'Caldaia')],
    );

    await tester.pumpWidget(
      _buildScreen(db: db, api: api, isOnline: true, entitlement: _entitlementWith(const {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('NUOVO'), findsNothing);

    await _disposeScreen(tester);
  });
}
