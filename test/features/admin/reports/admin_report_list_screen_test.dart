// dart format width=100
// test/features/admin/reports/admin_report_list_screen_test.dart
//
// The admin Rapportini list answers offline from the synced `draft_reports` mirror. What that may
// and may not claim:
//   • mirror rows carry the "potrebbero mancare …" line — the mirror holds what *this device*
//     synced, which under a "Vista amministratore" header is a narrower set than it sounds;
//   • the stato chip filters the mirror too (the mirror stores the enum name, same as the wire);
//   • a never-synced device says the rapportini are unavailable, not that there are none;
//   • a server answer is never labelled as mirrored.
//
// CRITICAL: every test that pumps a screen watching a Drift stream MUST end with:
//   await tester.pumpWidget(const SizedBox.shrink());
//   await tester.pumpAndSettle();
// to avoid "A Timer is still pending" hangs from Drift's StreamQueryStore.

import 'package:dio/dio.dart';
// `isNull` is both a drift query expression and a matcher; the matcher is what the assertions use.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_list_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({this.reports = const [], this.error}) : super(Dio());

  final List<Map<String, dynamic>> reports;
  final Object? error;

  int fetchCount = 0;
  String? lastStato;
  String? lastCustomerId;
  String? lastLocationId;
  String? lastTicketId;
  String? lastCantiereId;
  DateTime? lastDateFrom;
  DateTime? lastDateTo;

  @override
  Future<List<Map<String, dynamic>>> fetchReports({
    String? stato,
    String? cantiereId,
    String? customerId,
    String? locationId,
    String? ticketId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int pageSize = 50,
  }) async {
    fetchCount++;
    lastStato = stato;
    lastCustomerId = customerId;
    lastLocationId = locationId;
    lastTicketId = ticketId;
    lastCantiereId = cantiereId;
    lastDateFrom = dateFrom;
    lastDateTo = dateTo;
    if (error != null) throw error!;
    return reports;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

List<Override> _overrides({
  required AppDatabase db,
  required AdminApiClient api,
  required bool isOnline,
}) => [
  appDatabaseProvider.overrideWithValue(db),
  adminApiClientProvider.overrideWithValue(api),
  isOnlineProvider.overrideWithValue(isOnline),
];

Widget _buildScreen({
  required AppDatabase db,
  required AdminApiClient api,
  required bool isOnline,
}) {
  return ProviderScope(
    overrides: _overrides(db: db, api: api, isOnline: isOnline),
    child: const MaterialApp(home: AdminReportListScreen()),
  );
}

Future<void> _seedReport(
  AppDatabase db, {
  required String id,
  required String title,
  String stato = 'Bozza',
  DateTime? createdAt,
  String? customerId,
  DateTime? startedAt,
  DateTime? endedAt,
}) => db
    .into(db.draftReports)
    .insert(
      DraftReportsCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: createdAt ?? DateTime.utc(2026, 10, 1),
        title: title,
        insertedUserId: 'user-1',
        locationId: 'loc-1',
        stato: Value(stato),
        customerId: Value(customerId),
        startedAt: Value(startedAt),
        endedAt: Value(endedAt),
      ),
    );

Future<void> _seedCustomer(AppDatabase db, {required String id, required String name}) => db
    .into(db.customers)
    .insert(
      CustomersCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 1, 1),
        companyName: name,
      ),
    );

void main() {
  setUpAll(() async => initializeDateFormatting('it'));

  group('offline (mirror)', () {
    testWidgets('shows the mirrored rapportini and says the list may be partial', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Manutenzione caldaia', stato: 'Inviato');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Manutenzione caldaia'), findsOneWidget);
      expect(
        find.textContaining('potrebbero mancare rapporti di intervento non ancora scaricati'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a never-synced device says the rapportini are unavailable, not that there are none',
      (tester) async {
        final db = _makeDb();

        await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
        await tester.pumpAndSettle();

        expect(find.text('Rapporti di intervento non disponibili offline'), findsOneWidget);
        expect(find.text('Nessun rapporto di intervento'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    test('the stato filter applies to the mirror as well', () async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Bozza uno');
      await _seedReport(db, id: 'r2', title: 'Inviato uno', stato: 'Inviato');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final container = ProviderContainer(
        overrides: _overrides(db: db, api: _FakeAdminApiClient(), isOnline: false),
      );
      addTearDown(container.dispose);

      final inviati = await container.read(
        adminReportsProvider(const StatoFilter('Inviato')).future,
      );
      expect(inviati.fromMirror, isTrue);
      expect(inviati.rows.map((r) => r['title']), ['Inviato uno']);

      final tutti = await container.read(adminReportsProvider(const StatoFilter(null)).future);
      expect(tutti.rows.length, 2);
    });
  });

  group('online', () {
    testWidgets('the server answer is used as-is, with no mirror notice', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Rapportino Vecchio');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        reports: [
          {'id': 'r-server', 'title': 'Rapportino Nuovo', 'stato': 'Inviato'},
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Rapportino Nuovo'), findsOneWidget);
      expect(find.text('Rapportino Vecchio'), findsNothing);
      expect(find.textContaining('potrebbero mancare'), findsNothing);
      // The list opens on the prototype's first chip, "Inviati"; the server still receives
      // the stato it asks for.
      expect(api.lastStato, 'Inviato');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a request that never arrived falls back to the mirror', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Manutenzione caldaia', stato: 'Inviato');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/reports'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      expect(find.text('Manutenzione caldaia'), findsOneWidget);
      expect(find.textContaining('potrebbero mancare'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the quick chips are Inviati/Controllati/Fatturati/Tutti with no Nuovo', (
      tester,
    ) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Rapportino inviato', stato: 'Inviato');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('INVIATI'), findsOneWidget);
      expect(find.text('CONTROLLATI'), findsOneWidget);
      expect(find.text('FATTURATI'), findsOneWidget);
      expect(find.text('TUTTI'), findsOneWidget);
      expect(find.text('BOZZA'), findsNothing);
      expect(find.text('NUOVO'), findsNothing);
      expect(find.text('FILTRI'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Bozza stays reachable through the Filtri sheet', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Rapportino inviato', stato: 'Inviato');
      await _seedReport(db, id: 'r2', title: 'Rapportino in bozza', stato: 'Bozza');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Rapportino in bozza'), findsNothing);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-filter-status-bozza')));
      await tester.tap(find.byKey(const Key('report-filter-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Rapportino in bozza'), findsOneWidget);
      expect(find.text('Rapportino inviato'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('groups and summary derive from the filtered rows', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Inviato uno', stato: 'Inviato');
      await _seedReport(db, id: 'r2', title: 'Inviato due', stato: 'Inviato');
      await _seedReport(db, id: 'r3', title: 'Controllato uno', stato: 'Controllato');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      // Inviati is the default chip, so only that group is on screen.
      expect(find.text('Inviati'), findsOneWidget);
      expect(find.text('Controllati'), findsNothing);

      await tester.tap(find.text('TUTTI'));
      await tester.pumpAndSettle();

      expect(find.text('Inviati'), findsOneWidget);
      expect(find.text('Controllati'), findsOneWidget);
      expect(find.text('3 REPORT'), findsOneWidget);
      expect(find.text('2 DA CONTROLLARE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('rows carry cliente · periodo · ore and search matches the customer', (
      tester,
    ) async {
      final db = _makeDb();
      await _seedCustomer(db, id: 'cust-1', name: 'Rossi Srl');
      await _seedReport(
        db,
        id: 'r1',
        title: 'Rapportino 2026-0412',
        stato: 'Inviato',
        customerId: 'cust-1',
        startedAt: DateTime.utc(2026, 11, 1, 8),
        endedAt: DateTime.utc(2026, 11, 2, 14),
      );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(_buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.text('Rossi Srl · Novembre · 30h'), findsOneWidget);
      expect(find.text('In attesa di controllo'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Rossi');
      await tester.pumpAndSettle();
      expect(find.text('Rapportino 2026-0412'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('duplicate customer ids do not break the Cliente dropdown', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db, id: 'cust-1', name: 'Rossi Srl');
      await _seedCustomer(db, id: 'cust-2', name: 'Bianchi Srl');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        reports: [
          {'id': 'r1', 'title': 'Rapportino uno', 'stato': 'Inviato', 'customerId': 'cust-1'},
          {'id': 'r2', 'title': 'Rapportino due', 'stato': 'Inviato', 'customerId': 'cust-1'},
          {'id': 'r3', 'title': 'Rapportino tre', 'stato': 'Inviato', 'customerId': 'cust-2'},
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-filter-cliente')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rossi Srl').last);
      await tester.pumpAndSettle();
      final apply = find.byKey(const Key('report-filter-apply'));
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      expect(api.lastCustomerId, 'cust-1');
      expect(find.text('Rapportino uno'), findsOneWidget);
      expect(find.text('Rapportino due'), findsOneWidget);
      expect(find.text('Rapportino tre'), findsNothing);

      // Reopening the sheet with the filter applied must not trip Flutter's dropdown value
      // assertion (the duplicate-customer regression).
      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-filter-cliente')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Sede facet reaches the server with the visitor id', (tester) async {
      final db = _makeDb();
      await _seedCustomer(db, id: 'cust-1', name: 'Rossi Srl');
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'loc-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              customerId: 'cust-1',
              name: 'Sede Milano',
            ),
          );
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      final api = _FakeAdminApiClient(
        reports: [
          {
            'id': 'r1',
            'title': 'Rapportino Milano',
            'stato': 'Inviato',
            'customerId': 'cust-1',
            'locationId': 'loc-1',
          },
        ],
      );

      await tester.pumpWidget(_buildScreen(db: db, api: api, isOnline: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-filter-sede')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Milano').last);
      await tester.pumpAndSettle();
      final apply = find.byKey(const Key('report-filter-apply'));
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      expect(api.lastLocationId, 'loc-1');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
