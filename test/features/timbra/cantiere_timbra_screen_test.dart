// test/features/timbra/cantiere_timbra_screen_test.dart
//
// Widget tests for CantiereTimbraScreen.
//
// CRITICAL: every test that pumps a screen watching a Drift stream MUST end
// with:
//   await tester.pumpWidget(const SizedBox.shrink());
//   await tester.pumpAndSettle();
// to avoid "A Timer is still pending" hangs from Drift's StreamQueryStore.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/drift.dart' as drift show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Fake LocationService that always returns a fixed coord.
class _FakeLocationService implements ILocationService {
  @override
  Future<GpsCoords?> getCurrentPosition() async =>
      (lat: 45.4654, lng: 9.1859);
}

/// Fake CantiereWorklogApiClient — no network calls.
class _FakeApiClient extends CantiereWorklogApiClient {
  _FakeApiClient({
    this.activeLog,
    this.endShouldThrow = false,
  }) : super(Dio());

  final CantiereWorkLogDto? activeLog;
  final bool endShouldThrow;

  /// Captures the [StartCantiereRequest] passed to startCantiere.
  final List<StartCantiereRequest> startedRequests = [];

  bool endCalled = false;

  @override
  Future<List<CantiereWorkLogDto>> getActive() async =>
      activeLog != null ? [activeLog!] : [];

  @override
  Future<void> startCantiere(StartCantiereRequest request) async {
    startedRequests.add(request);
  }

  @override
  Future<void> endCantiere([EndCantiereRequest? request]) async {
    if (endShouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/cantiereworklog/end'),
        type: DioExceptionType.connectionError,
      );
    }
    endCalled = true;
  }
}

/// Override notifier that extends the real notifier type and uses a fake client.
class _FakeActiveNotifier extends ActiveCantiereLogNotifier {
  _FakeActiveNotifier(this._fakeLog);
  final CantiereWorkLogDto? _fakeLog;

  @override
  Future<CantiereWorkLogDto?> build() async => _fakeLog;

  @override
  Future<void> refresh() async {
    state = AsyncData(_fakeLog);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Widget _buildScreen({
  required AppDatabase db,
  required _FakeApiClient apiClient,
  ILocationService? locationService,
  String? ticketId,
  String? customerId,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cantiereWorklogApiClientProvider.overrideWithValue(apiClient),
      locationServiceProvider
          .overrideWithValue(locationService ?? _FakeLocationService()),
      activeCantiereLogProvider
          .overrideWith(() => _FakeActiveNotifier(apiClient.activeLog)),
    ],
    child: MaterialApp(
      home: CantiereTimbraScreen(
        ticketId: ticketId,
        customerId: customerId,
      ),
    ),
  );
}

// ── Test data ─────────────────────────────────────────────────────────────────

CantiereWorkLogDto _activeLog() => CantiereWorkLogDto(
      id: 'log-1',
      cantiereId: 'cant-1',
      customerId: 'cust-1',
      ticketId: 'tick-1',
      workDate: DateTime.utc(2026, 6, 23),
      startTime: '08:00:00',
    );

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  // ── Check-in UI (no active session) ──────────────────────────────────────

  group('no active session', () {
    testWidgets('renders Timbra cantiere header', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Timbra cantiere'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('renders Seleziona cantiere section', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Seleziona cantiere'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('renders Timbra ingresso cantiere button', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Timbra ingresso cantiere'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows cantiere picker rows from Drift', (tester) async {
      await db.into(db.cantieri).insert(CantieriCompanion.insert(
            id: 'cant-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Cantiere Via Roma',
          ));

      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Cantiere Via Roma'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows linked ticket banner when ticketId provided',
        (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(
        db: db,
        apiClient: api,
        ticketId: 'tick-1',
        customerId: 'cust-1',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Collegato al ticket'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows empty state when no cantieri in cache', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Selezione cantiere non disponibile'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('check-in calls startCantiere with correct ids', (tester) async {
      await db.into(db.cantieri).insert(CantieriCompanion.insert(
            id: 'cant-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Cantiere Via Roma',
            customerId: const drift.Value('cust-1'),
          ));

      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(
        db: db,
        apiClient: api,
        ticketId: 'tick-1',
        customerId: 'cust-1',
      ));
      await tester.pumpAndSettle();

      // Select the cantiere.
      await tester.ensureVisible(find.text('Cantiere Via Roma'));
      await tester.tap(find.text('Cantiere Via Roma'));
      await tester.pumpAndSettle();

      // Tap clock-in button.
      await tester.ensureVisible(find.text('Timbra ingresso cantiere'));
      await tester.tap(find.text('Timbra ingresso cantiere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.startedRequests, hasLength(1));
      expect(api.startedRequests.first.cantiereId, 'cant-1');
      expect(api.startedRequests.first.customerId, 'cust-1');
      expect(api.startedRequests.first.ticketId, 'tick-1');
      await _teardown(tester);
    });

    testWidgets('shows validation error when no cantiere selected and clock-in tapped',
        (tester) async {
      // The clock-in button is disabled outright when the cache holds zero
      // cantieri (see `noCantieriAvailable` in cantiere_timbra_screen.dart) —
      // an honest response to db.cantieri never being synced. This test
      // exercises the "cantieri exist but none picked" validation path
      // instead, which is what the button becomes reachable for once
      // syncing is wired up.
      await db.into(db.cantieri).insert(CantieriCompanion.insert(
            id: 'cant-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Cantiere Via Roma',
          ));

      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Timbra ingresso cantiere'));
      await tester.tap(find.text('Timbra ingresso cantiere'));
      await tester.pumpAndSettle();

      expect(find.text('Seleziona un cantiere prima di timbrare.'),
          findsOneWidget);
      await _teardown(tester);
    });
  });

  // ── Active session (clock-out) UI ─────────────────────────────────────────

  group('active session', () {
    testWidgets('shows Sessione cantiere attiva indicator', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Sessione cantiere attiva'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows Timbra uscita cantiere button', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Timbra uscita cantiere'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows ingresso time from active log', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      // startTime '08:00:00' → displayed as '08:00'
      expect(find.text('08:00'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows ticket reference in active session card', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.textContaining('tick-1'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('clock-out calls endCantiere on the API client', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Timbra uscita cantiere'));
      await tester.tap(find.text('Timbra uscita cantiere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.endCalled, isTrue);
      await _teardown(tester);
    });

    testWidgets('shows Italian connection error when end call fails',
        (tester) async {
      final api = _FakeApiClient(
        activeLog: _activeLog(),
        endShouldThrow: true,
      );
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Timbra uscita cantiere'));
      await tester.tap(find.text('Timbra uscita cantiere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Connessione richiesta per la timbratura cantiere.'),
          findsOneWidget);
      await _teardown(tester);
    });
  });
}
