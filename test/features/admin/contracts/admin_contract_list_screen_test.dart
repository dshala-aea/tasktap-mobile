// dart format width=100
// test/features/admin/contracts/admin_contract_list_screen_test.dart
//
// The Contratti list answers offline from the synced `contracts` mirror. What these tests pin is
// the honesty of that answer, not just that rows appear:
//   • mirror rows carry a "potrebbero mancare …" line, because the sync is scoped;
//   • an empty mirror that was never synced says so instead of claiming the account has no
//     contracts;
//   • an empty mirror that *was* synced is a genuine empty list;
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

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
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
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      adminApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(isOnline),
      // Fail-closed and deterministic: the screen's only entitlement read is the "Nuovo
      // contratto" FAB gate, which these tests do not exercise.
      cachedEntitlementProvider.overrideWith((ref) async => null),
    ],
    child: const MaterialApp(home: AdminContractListScreen()),
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

Future<void> _seedContract(
  AppDatabase db, {
  String id = 'ctr-1',
  String name = 'Contratto Annuale',
  String customerId = 'cust-1',
  bool isActive = true,
}) => db
    .into(db.contracts)
    .insert(
      ContractsCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        name: name,
        customerId: customerId,
        startDate: DateTime.utc(2026, 1, 1),
        isActive: Value(isActive),
      ),
    );

void main() {
  group('offline (mirror)', () {
    testWidgets('shows the mirrored contracts and says the list may be partial', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contratto Annuale'), findsOneWidget);
      // The customer name comes from the customers mirror — an id alone would render as '—'.
      expect(find.text('Rossi Impianti'), findsOneWidget);
      expect(
        find.text(
          'Dati salvati sul dispositivo: potrebbero mancare contratti non ancora scaricati.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an inactive contract still lists, with its "Inattivo" pill', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db);
      await _seedContract(db, isActive: false);
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contratto Annuale'), findsOneWidget);
      // StatusStamp uppercases its label, so the pill reads INATTIVO on screen.
      expect(find.text('INATTIVO'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a never-synced device says the contracts are not available, not that there are none',
      (tester) async {
        final db = _makeDb();

        await tester.pumpWidget(
          _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
        );
        await tester.pumpAndSettle();

        expect(find.text('Contratti non disponibili offline'), findsOneWidget);
        // The empty-list copy would claim the account has no contracts at all — the exact
        // falsehood this branch exists to stop.
        expect(find.text('Nessun contratto'), findsNothing);

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

      expect(find.text('Nessun contratto'), findsOneWidget);
      expect(find.text('Contratti non disponibili offline'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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
        contracts: [
          {
            'id': 'ctr-server',
            'name': 'Contratto Nuovo',
            'customerId': 'cust-1',
            'isActive': true,
          },
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Contratto Nuovo'), findsOneWidget);
      expect(find.text('Contratto Vecchio'), findsNothing);
      expect(find.textContaining('potrebbero mancare'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
