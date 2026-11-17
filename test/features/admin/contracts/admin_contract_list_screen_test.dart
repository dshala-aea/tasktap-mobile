// dart format width=100
// test/features/admin/contracts/admin_contract_list_screen_test.dart
//
// The Contratti list answers offline from the synced `contracts` mirror. What these tests pin is
// the honesty of that answer and the prototype's grouping/filter contract:
//   • mirror rows carry a "potrebbero mancare …" line, because the sync is scoped;
//   • an empty mirror that was never synced says so instead of claiming the account has no
//     contracts;
//   • an empty mirror that *was* synced is a genuine empty list;
//   • a server answer is never labelled as mirrored;
//   • the chip, the group and the sheet's status facet share one expiry predicate (the server's
//     `inScadenza` rule: now < endDate <= now + 30 days).
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

import 'package:tasktap_mobile/core/time/business_time_providers.dart' show clockProvider;
import 'package:tasktap_mobile/core/widgets/widgets.dart' show ListFilterRow;
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/contracts/admin_contract_list_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({this.contracts = const [], this.error}) : super(Dio());

  final List<Map<String, dynamic>> contracts;

  /// When set, [fetchContracts] throws it — the harness uses this for "the radio says online but
  /// the request never arrived", the case the mirror exists for.
  final Object? error;

  int fetchCount = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchContracts({String? customerId}) async {
    fetchCount++;
    if (error != null) throw error!;
    return contracts;
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
  DateTime? now,
  Entitlement? entitlement,
}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      adminApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(isOnline),
      if (now != null) clockProvider.overrideWithValue(() => now),
      cachedEntitlementProvider.overrideWith((ref) async => entitlement),
    ],
    child: const MaterialApp(home: AdminContractListScreen()),
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
}) => db
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

Future<void> _seedContract(
  AppDatabase db, {
  String id = 'ctr-1',
  String name = 'Contratto Annuale',
  String customerId = 'cust-1',
  String? locationId,
  bool isActive = true,
  DateTime? endDate,
  String? codice,
}) => db
    .into(db.contracts)
    .insert(
      ContractsCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        name: name,
        customerId: customerId,
        locationId: Value(locationId),
        startDate: DateTime.utc(2026, 1, 1),
        endDate: Value(endDate),
        isActive: Value(isActive),
        codice: Value(codice),
      ),
    );

Map<String, dynamic> _serverContract({
  required String id,
  required String name,
  String customerId = 'cust-1',
  String? locationId,
  String? endDate,
  bool isActive = true,
  bool? autoRenewal,
  int? scadenzaGiorni,
  String? codice,
}) => {
  'id': id,
  'name': name,
  'customerId': customerId,
  'locationId': locationId,
  'endDate': endDate,
  'isActive': isActive,
  'autoRenewal': autoRenewal,
  'scadenzaGiorni': scadenzaGiorni,
  'codice': codice,
};

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Finder _chip(String label) =>
    find.descendant(of: find.byType(ListFilterRow), matching: find.text(label));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  group('offline (mirror)', () {
    testWidgets('shows the mirrored contracts and says the list may be partial', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Contratto Annuale'), findsOneWidget);
      expect(find.textContaining('Rossi Impianti'), findsOneWidget);
      expect(
        find.text(
          'Dati salvati sul dispositivo: potrebbero mancare contratti non ancora scaricati.',
        ),
        findsOneWidget,
      );

      await _disposeScreen(tester);
    });

    testWidgets('renders the prototype header, search and quick chips', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Contratti'), findsWidgets);
      expect(find.text('Cosa scade, cosa si rinnova, cosa è coperto.'), findsOneWidget);
      expect(find.text('Cerca contratto, cliente o codice…'), findsOneWidget);
      expect(_chip('ATTIVI'), findsOneWidget);
      expect(_chip('IN SCADENZA'), findsOneWidget);
      expect(_chip('SCADUTI'), findsOneWidget);
      expect(_chip('TUTTI'), findsOneWidget);
      expect(_chip('FILTRI'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('an inactive contract still lists, with its "Inattivo" pill', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db, isActive: false);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Contratto Annuale'), findsOneWidget);
      // StatusStamp uppercases its label, so the pill reads INATTIVO on screen.
      expect(find.text('INATTIVO'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets(
      'a never-synced device says the contracts are not available, not that there are none',
      (tester) async {
        final db = _makeDb();

        await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
        await tester.pumpAndSettle();

        expect(find.text('Contratti non disponibili offline'), findsOneWidget);
        // The empty-list copy would claim the account has no contracts at all — the exact
        // falsehood this branch exists to stop.
        expect(find.text('Nessun contratto'), findsNothing);

        await _disposeScreen(tester);
      },
    );

    testWidgets('a synced-but-empty mirror is a genuine empty list', (tester) async {
      final db = _makeDb();
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Nessun contratto'), findsOneWidget);
      expect(find.text('Contratti non disponibili offline'), findsNothing);

      await _disposeScreen(tester);
    });
  });

  group('grouping and expiry', () {
    testWidgets('the chip, group and sheet share the server inScadenza rule', (tester) async {
      final db = _makeDb();
      final today = DateTime.utc(2026, 11, 5);
      await _seedCustomer(db);
      // 20 days away → In scadenza (now < endDate <= now + 30 days).
      await _seedContract(
        db,
        id: 'expiring',
        name: 'Full service',
        endDate: DateTime.utc(2026, 11, 25),
      );
      // 45 days away → Attivi.
      await _seedContract(
        db,
        id: 'active',
        name: 'Assistenza impianti',
        endDate: DateTime.utc(2026, 12, 20),
      );
      // Already past → Scaduti.
      await _seedContract(
        db,
        id: 'expired',
        name: 'Manutenzione vecchia',
        endDate: DateTime.utc(2026, 10, 1),
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(
          db: db,
          api: _FakeAdminApiClient(),
          isOnline: false,
          now: today.add(const Duration(hours: 10)),
        ),
      );
      await tester.pumpAndSettle();

      // Groups, in the prototype's order, with derived counts.
      expect(find.text('In scadenza'), findsOneWidget);
      expect(find.text('Attivi'), findsOneWidget);
      expect(find.text('Scaduti'), findsOneWidget);
      expect(find.text('Full service'), findsOneWidget);
      expect(find.text('Assistenza impianti'), findsOneWidget);
      expect(find.text('Manutenzione vecchia'), findsOneWidget);

      await tester.tap(_chip('IN SCADENZA'));
      await tester.pumpAndSettle();

      // The quick chip shows the same set the group does.
      expect(find.text('Full service'), findsOneWidget);
      expect(find.text('Assistenza impianti'), findsNothing);
      expect(find.text('Manutenzione vecchia'), findsNothing);
      expect(find.text('In scadenza'), findsOneWidget);
      expect(find.text('Attivi'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('the expiry boundary is inclusive at 30 days and resets to active after', (
      tester,
    ) async {
      final db = _makeDb();
      final today = DateTime.utc(2026, 11, 5);
      await _seedCustomer(db);
      await _seedContract(
        db,
        id: 'day-30',
        name: 'Scade tra trenta',
        endDate: today.add(const Duration(days: 30)),
      );
      await _seedContract(
        db,
        id: 'day-31',
        name: 'Scade tra trentuno',
        endDate: today.add(const Duration(days: 31)),
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(
          db: db,
          api: _FakeAdminApiClient(),
          isOnline: false,
          now: today.add(const Duration(hours: 10)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_chip('IN SCADENZA'));
      await tester.pumpAndSettle();

      expect(find.text('Scade tra trenta'), findsOneWidget);
      expect(find.text('Scade tra trentuno'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('summary and group counts derive from the filtered set', (tester) async {
      final db = _makeDb();
      final today = DateTime.utc(2026, 11, 5);
      await _seedCustomer(db);
      await _seedContract(
        db,
        id: 'expiring',
        name: 'Full service',
        endDate: DateTime.utc(2026, 11, 25),
      );
      await _seedContract(
        db,
        id: 'active',
        name: 'Assistenza impianti',
        endDate: DateTime.utc(2026, 12, 20),
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(
          db: db,
          api: _FakeAdminApiClient(),
          isOnline: false,
          now: today.add(const Duration(hours: 10)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 CONTRATTI'), findsOneWidget);
      expect(find.text('1 IN SCADENZA'), findsOneWidget);

      await _disposeScreen(tester);
    });
  });

  group('filters and search', () {
    testWidgets('search matches contract, customer and codice', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db, id: 'cust-1', name: 'Rossi Impianti');
      await _seedCustomer(db, id: 'cust-2', name: 'Bianchi Servizi');
      await _seedContract(
        db,
        id: 'c1',
        name: 'Full service',
        customerId: 'cust-1',
        codice: 'CT-100',
      );
      await _seedContract(db, id: 'c2', name: 'Manutenzione caldaie', customerId: 'cust-2');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'bianchi');
      await tester.pumpAndSettle();
      expect(find.text('Manutenzione caldaie'), findsOneWidget);
      expect(find.text('Full service'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'CT-100');
      await tester.pumpAndSettle();
      expect(find.text('Full service'), findsOneWidget);
      expect(find.text('Manutenzione caldaie'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('the filter sheet exposes every facet and applies customer', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db, id: 'cust-1', name: 'Rossi Impianti');
      await _seedCustomer(db, id: 'cust-2', name: 'Bianchi Servizi');
      await _seedLocation(db);
      final api = _FakeAdminApiClient(
        contracts: [
          _serverContract(
            id: 'c1',
            name: 'Full service',
            customerId: 'cust-1',
            locationId: 'loc-1',
            autoRenewal: true,
          ),
          _serverContract(
            id: 'c2',
            name: 'Manutenzione caldaie',
            customerId: 'cust-2',
            autoRenewal: true,
          ),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(_chip('FILTRI'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contratti-filter-customer')), findsOneWidget);
      expect(find.byKey(const Key('contratti-filter-location')), findsOneWidget);
      expect(find.byKey(const Key('contratti-filter-from')), findsOneWidget);
      expect(find.byKey(const Key('contratti-filter-to')), findsOneWidget);
      expect(find.byKey(const Key('contratti-filter-auto-renewal')), findsOneWidget);

      await tester.tap(find.byKey(const Key('contratti-filter-customer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rossi Impianti').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Full service'), findsOneWidget);
      expect(find.text('Manutenzione caldaie'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('the sheet status facet uses the same expiry buckets as the chips', (tester) async {
      final db = _makeDb();
      final today = DateTime.utc(2026, 11, 5);
      await _seedCustomer(db);
      await _seedContract(
        db,
        id: 'expired',
        name: 'Manutenzione vecchia',
        endDate: DateTime.utc(2026, 10, 1),
      );
      await _seedContract(
        db,
        id: 'active',
        name: 'Assistenza impianti',
        endDate: DateTime.utc(2026, 12, 20),
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(
          db: db,
          api: _FakeAdminApiClient(),
          isOnline: false,
          now: today.add(const Duration(hours: 10)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_chip('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-status-scaduti')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Manutenzione vecchia'), findsOneWidget);
      expect(find.text('Assistenza impianti'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('the auto-renewal toggle filters only automatic contracts', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      final api = _FakeAdminApiClient(
        contracts: [
          _serverContract(id: 'c1', name: 'Full service', autoRenewal: true),
          _serverContract(id: 'c2', name: 'Manutenzione caldaie', autoRenewal: false),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(_chip('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-auto-renewal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-auto-renewal')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Full service'), findsOneWidget);
      expect(find.text('Manutenzione caldaie'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('Azzera clears an applied filter and shows every contract again', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      final api = _FakeAdminApiClient(
        contracts: [
          _serverContract(id: 'c1', name: 'Full service', autoRenewal: true),
          _serverContract(id: 'c2', name: 'Manutenzione caldaie', autoRenewal: false),
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(_chip('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-auto-renewal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-auto-renewal')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-apply')));
      await tester.pumpAndSettle();
      expect(find.text('Manutenzione caldaie'), findsNothing);

      await tester.tap(_chip('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('contratti-filter-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contratti-filter-reset')));
      await tester.pumpAndSettle();

      expect(find.text('Full service'), findsOneWidget);
      expect(find.text('Manutenzione caldaie'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('offline rows keep the auto-renewal facet disabled with a reason', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      await tester.tap(_chip('FILTRI'));
      await tester.pumpAndSettle();

      expect(
        find.text('Disponibile quando i contratti sono stati aggiornati online.'),
        findsOneWidget,
      );

      await _disposeScreen(tester);
    });
  });

  group('online', () {
    testWidgets('server rows are shown without the mirror notice', (tester) async {
      final db = _makeDb();
      // A stale mirror row that must NOT appear: the server answered, so it is the truth.
      await _seedCustomer(db);
      await _seedContract(db, name: 'Contratto Vecchio');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        contracts: [_serverContract(id: 'ctr-server', name: 'Contratto Nuovo')],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Contratto Nuovo'), findsOneWidget);
      expect(find.text('Contratto Vecchio'), findsNothing);
      expect(find.textContaining('potrebbero mancare'), findsNothing);

      await _disposeScreen(tester);
    });

    testWidgets('a request that never arrived falls back to the mirror', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/contracts'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(api.fetchCount, 1);
      expect(find.text('Contratto Annuale'), findsOneWidget);
      expect(find.textContaining('potrebbero mancare'), findsOneWidget);

      await _disposeScreen(tester);
    });

    testWidgets('a 403 is reported as an error, never answered from stale rows', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/contracts'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/api/contracts'),
            statusCode: 403,
          ),
        ),
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Contratto Annuale'), findsNothing);
      expect(find.text('Contratti non disponibili offline'), findsNothing);

      await _disposeScreen(tester);
    });
  });

  group('layout', () {
    testWidgets('renders at 320px without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(
        db,
        name: 'Contratto con un nome italiano molto lungo che deve andare a capo',
        endDate: DateTime.utc(2027, 12, 31),
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(tester.takeException(), null);

      await _disposeScreen(tester);
    });

    testWidgets('a long title is clamped to two lines', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(
        db,
        name:
            'Contratto di manutenzione ordinaria e straordinaria degli impianti termici '
            'della sede di Milano con rinnovo annuale',
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(
        find.text(
          'Contratto di manutenzione ordinaria e straordinaria degli impianti termici '
          'della sede di Milano con rinnovo annuale',
        ),
      );
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);

      await _disposeScreen(tester);
    });

    testWidgets('Nuovo is shown only when the role can write contracts', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();
      expect(find.text('NUOVO'), findsNothing);
      await _disposeScreen(tester);

      await tester.pumpWidget(
        _buildScreen(
          db: db,
          api: _FakeAdminApiClient(),
          isOnline: false,
          entitlement: Entitlement(
            features: const {},
            capabilities: const {'contratti.contract.write'},
            seatType: 'office',
            fetchedAt: DateTime.utc(2026, 9, 23),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NUOVO'), findsOneWidget);
      await _disposeScreen(tester);
    });
  });
}
