// dart format width=100
// test/features/admin/prodotti/admin_prodotto_list_screen_test.dart
//
// The Asset list answers offline from the synced `prodotti_assistenza` mirror. These tests pin
// what that answer may and may not claim:
//   • mirror rows carry the "potrebbero mancare …" line (the sync payload is scoped);
//   • the search box still filters offline — over the same three fields the server matches;
//   • a never-synced device says the assets are unavailable, not that there are none;
//   • a server answer is never labelled as mirrored.
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

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_list_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({this.prodotti = const [], this.error}) : super(Dio());

  final List<Map<String, dynamic>> prodotti;
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
    return prodotti;
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
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      adminApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(isOnline),
      // The search box lives in a real StateProvider; this test sets it up-front instead of
      // typing, because the 350ms debounce is not what is under test.
      adminProdottiQueryProvider.overrideWith((ref) => query),
    ],
    child: const MaterialApp(home: AdminProdottoListScreen()),
  );
}

Future<void> _seedCustomer(AppDatabase db, {String id = 'cust-1'}) => db
    .into(db.customers)
    .insert(
      CustomersCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        companyName: 'Rossi Impianti',
      ),
    );

Future<void> _seedProdotto(
  AppDatabase db, {
  required String id,
  required String name,
  String customerId = 'cust-1',
  String? codice,
  String? categoria,
}) => db
    .into(db.prodottiAssistenza)
    .insert(
      ProdottiAssistenzaCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        name: name,
        customerId: customerId,
        locationId: 'loc-1',
        codice: Value(codice),
        categoria: Value(categoria),
      ),
    );

void main() {
  group('offline (mirror)', () {
    testWidgets(
      'shows the mirrored assets, resolves customer names, and says the list may be partial',
      (tester) async {
        final db = _makeDb();
        await _seedCustomer(db);
        await _seedProdotto(db, id: 'p1', name: 'Caldaia Rossi', codice: 'C-001');
        await db.setLastSync(DateTime.utc(2026, 10, 1));

        await tester.pumpWidget(
          _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
        );
        await tester.pumpAndSettle();

        expect(find.text('C-001 · Caldaia Rossi'), findsOneWidget);
        // Resolved from the customers mirror — an id alone would render as '—'.
        expect(find.textContaining('Rossi Impianti'), findsOneWidget);
        expect(
          find.text('Dati salvati sul dispositivo: potrebbero mancare asset non ancora scaricati.'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the search box filters the mirror by codice, name or categoria', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedProdotto(db, id: 'p1', name: 'Caldaia Rossi', codice: 'C-001');
      await _seedProdotto(db, id: 'p2', name: 'Bruciatore Bianchi', codice: 'C-002');
      await _seedProdotto(db, id: 'p3', name: 'Gruppo Termico', categoria: 'Climatizzazione');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      for (final (query, expected, absent) in [
        ('c-002', 'Bruciatore Bianchi', 'Caldaia Rossi'), // codice, case-insensitive
        ('rossi', 'Caldaia Rossi', 'Bruciatore Bianchi'), // name
        ('climatizz', 'Gruppo Termico', 'Caldaia Rossi'), // categoria
      ]) {
        await tester.pumpWidget(
          _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false, query: query),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining(expected), findsOneWidget, reason: 'query: $query');
        expect(find.textContaining(absent), findsNothing, reason: 'query: $query');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a never-synced device says the assets are not available, not that there are none',
      (tester) async {
        final db = _makeDb();

        await tester.pumpWidget(
          _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
        );
        await tester.pumpAndSettle();

        expect(find.text('Asset non disponibili offline'), findsOneWidget);
        expect(find.text('Nessun asset'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a synced-but-empty mirror is a genuine empty list', (tester) async {
      final db = _makeDb();
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nessun asset'), findsOneWidget);
      expect(find.text('Asset non disponibili offline'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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
          {
            'id': 'p-server',
            'name': 'Asset Nuovo',
            'customerName': 'Verdi Service',
            'isActive': true,
          },
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, api: api, isOnline: true, query: 'nuovo'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Asset Nuovo'), findsOneWidget);
      expect(find.text('Asset Vecchio'), findsNothing);
      expect(find.textContaining('potrebbero mancare'), findsNothing);
      // The term still goes to the server as `q` — offline fallback must not turn server-side
      // search into a client-side filter over the first page.
      expect(api.lastQuery, 'nuovo');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
