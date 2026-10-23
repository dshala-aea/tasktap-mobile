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

  @override
  Future<List<Map<String, dynamic>>> fetchReports({
    String? stato,
    String? cantiereId,
    int page = 1,
    int pageSize = 50,
  }) async {
    fetchCount++;
    lastStato = stato;
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
      ),
    );

void main() {
  setUpAll(() async => initializeDateFormatting('it'));

  group('offline (mirror)', () {
    testWidgets('shows the mirrored rapportini and says the list may be partial', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Manutenzione caldaia');
      await db.setLastSync(DateTime.utc(2026, 10, 1));

      await tester.pumpWidget(
        _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manutenzione caldaia'), findsOneWidget);
      expect(
        find.textContaining('potrebbero mancare rapportini non ancora scaricati'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a never-synced device says the rapportini are unavailable, not that there are none',
      (tester) async {
        final db = _makeDb();

        await tester.pumpWidget(
          _buildScreen(db: db, api: _FakeAdminApiClient(), isOnline: false),
        );
        await tester.pumpAndSettle();

        expect(find.text('Rapportini non disponibili offline'), findsOneWidget);
        expect(find.text('Nessun rapportino'), findsNothing);

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
      // The default chip is "Tutti", which sends no stato — the server filter must not be
      // replaced by the mirror's client-side one.
      expect(api.lastStato, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a request that never arrived falls back to the mirror', (tester) async {
      final db = _makeDb();
      await _seedReport(db, id: 'r1', title: 'Manutenzione caldaia');
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
  });
}
