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
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Fake LocationService that always returns a fixed coord.
class _FakeLocationService extends ILocationService {
  @override
  Future<GpsCoords?> getCurrentPosition() async => (lat: 45.4654, lng: 9.1859, accuracy: 10.0);
}

/// Fake CantiereWorklogApiClient — no network calls.
class _FakeApiClient extends CantiereWorklogApiClient {
  _FakeApiClient({
    this.activeLog,
    this.endShouldThrow = false,
    this.startShouldThrow = false,
  }) : super(Dio());

  final CantiereWorkLogDto? activeLog;
  final bool endShouldThrow;
  final bool startShouldThrow;

  /// Captures the [StartCantiereRequest] passed to startCantiere.
  final List<StartCantiereRequest> startedRequests = [];

  /// Captures batch-upsert calls the offline-fallback path makes.
  final List<List<CantiereMobileSessionDto>> upsertCalls = [];

  bool endCalled = false;

  @override
  Future<List<CantiereWorkLogDto>> getActive() async => activeLog != null ? [activeLog!] : [];

  @override
  Future<void> startCantiere(StartCantiereRequest request) async {
    if (startShouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/cantiereworklog/start'),
        type: DioExceptionType.connectionError,
      );
    }
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

  @override
  Future<List<CantiereMobileSessionResult>> upsertSessions(
    List<CantiereMobileSessionDto> sessions,
  ) async {
    upsertCalls.add(List.of(sessions));
    return sessions
        .map(
          (s) => CantiereMobileSessionResult(
            clientId: s.clientId,
            cantiereWorkLogId: 'wl-${s.clientId}',
            startTime: s.startTime,
            endTime: s.endTime,
            isActive: s.endTime == null,
          ),
        )
        .toList();
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
  String? cantiereId,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cantiereWorklogApiClientProvider.overrideWithValue(apiClient),
      locationServiceProvider.overrideWithValue(locationService ?? _FakeLocationService()),
      activeCantiereLogProvider.overrideWith(() => _FakeActiveNotifier(apiClient.activeLog)),
    ],
    child: MaterialApp(
      home: CantiereTimbraScreen(
        ticketId: ticketId,
        customerId: customerId,
        cantiereId: cantiereId,
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
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Cantiere Via Roma'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows linked ticket banner when ticketId provided', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, ticketId: 'tick-1', customerId: 'cust-1'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Collegato al ticket'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows an honest empty state when no cantieri in cache', (tester) async {
      // B1 fix: this used to claim the sync was "not yet connected" — misleading once
      // SyncService actually populates db.cantieri on every app session (see cantieriProvider's
      // own doc comment). The empty case is now just "nothing synced for this tenant yet".
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Nessun cantiere disponibile'), findsOneWidget);
      expect(find.textContaining('non è ancora sincronizzato'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('check-in calls startCantiere with correct ids', (tester) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
              customerId: const drift.Value('cust-1'),
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, ticketId: 'tick-1', customerId: 'cust-1'),
      );
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

    testWidgets('shows validation error when no cantiere selected and clock-in tapped', (
      tester,
    ) async {
      // The clock-in button is disabled outright when the cache holds zero
      // cantieri (see `noCantieriAvailable` in cantiere_timbra_screen.dart) —
      // an honest response to db.cantieri never being synced. This test
      // exercises the "cantieri exist but none picked" validation path
      // instead, which is what the button becomes reachable for once
      // syncing is wired up.
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Timbra ingresso cantiere'));
      await tester.tap(find.text('Timbra ingresso cantiere'));
      await tester.pumpAndSettle();

      expect(find.text('Seleziona un cantiere prima di timbrare.'), findsOneWidget);
      await _teardown(tester);
    });
  });

  // ── Active session (clock-out) UI ─────────────────────────────────────────

  group('active session', () {
    testWidgets('shows IN CANTIERE indicator', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('IN CANTIERE'), findsOneWidget);
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

      // workDate 2026-06-23 UTC + startTime '08:00:00' (also UTC, per backend convention) →
      // the actual clock-in instant is 2026-06-23T08:00:00Z, displayed in the device's local
      // zone. Computed rather than hardcoded so the expectation holds on any CI machine's TZ,
      // not just UTC+0.
      final expectedLabel = DateFormat(
        'HH:mm',
      ).format(DateTime.utc(2026, 6, 23, 8).toLocal());
      expect(find.text(expectedLabel), findsOneWidget);
      await _teardown(tester);
    });

    // The session carries a ticket id and nothing else, so this row used to render
    // `#${ticketId.substring(0, 8)}` — and the old test asserted exactly that, which is how the
    // GUID fragment survived review. It now resolves against the local mirror to the job's name.
    testWidgets('names the linked ticket, rather than printing its id', (tester) async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 'tick-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'Sostituzione pompa',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Sostituzione pompa'), findsOneWidget);
      expect(find.textContaining('tick-1'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('drops the row entirely when the mirror does not hold the ticket', (tester) async {
      // Nothing seeded. The honest answer is silence: printing the id back would name the job
      // with something the technician cannot match to anything in front of them.
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('TICKET'), findsNothing);
      expect(find.textContaining('tick-1'), findsNothing);
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

    testWidgets(
      'offline (connection error) clock-out queues locally instead of failing outright',
      (tester) async {
        // Item B2: this used to be online-only and show a blocking connection error. It now
        // falls back to the local Drift queue — the technician's "I left the site" is recorded
        // durably even with no signal, and CantiereTimbraSyncService pushes it once reconnected.
        final api = _FakeApiClient(activeLog: _activeLog(), endShouldThrow: true);
        await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Timbra uscita cantiere'));
        await tester.tap(find.text('Timbra uscita cantiere'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Connessione richiesta per la timbratura cantiere.'), findsNothing);
        expect(
          find.text('Uscita registrata offline: verrà inviata al ritorno della connessione.'),
          findsOneWidget,
        );

        final events = await (db.select(db.cantierePunches)).get();
        expect(events.where((e) => e.eventType == 'uscita'), hasLength(1));

        await _teardown(tester);
      },
    );
  });

  // ── Direct-entry mode (cantiereId provided — skips the picker) ─────────────

  group('direct-entry mode (cantiereId provided)', () {
    testWidgets('given a cantiereId, the picker is not shown', (tester) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Diretto',
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api, cantiereId: 'c1'));
      await tester.pumpAndSettle();

      // The full picker section header only renders in picker mode.
      expect(find.text('Seleziona cantiere'), findsNothing);
      expect(find.text('Cantiere Diretto'), findsOneWidget);

      await _teardown(tester);
    });
  });

  // ── Offline check-in (item B2) ────────────────────────────────────────────

  group('offline check-in', () {
    testWidgets(
      'connection error on startCantiere queues locally and switches to the active session body',
      (tester) async {
        await db
            .into(db.cantieri)
            .insert(
              CantieriCompanion.insert(
                id: 'cant-1',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                name: 'Cantiere Via Roma',
              ),
            );

        final api = _FakeApiClient(startShouldThrow: true);
        await tester.pumpWidget(
          _buildScreen(db: db, apiClient: api, ticketId: 'tick-1', customerId: 'cust-1'),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Cantiere Via Roma'));
        await tester.tap(find.text('Cantiere Via Roma'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Timbra ingresso cantiere'));
        await tester.tap(find.text('Timbra ingresso cantiere'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // No online request ever landed, and the screen did not show a blocking error — it
        // switched straight to "on site" from the local queue.
        expect(api.startedRequests, isEmpty);
        expect(find.text('IN CANTIERE'), findsOneWidget);

        final events = await (db.select(db.cantierePunches)).get();
        expect(events, hasLength(1));
        expect(events.single.eventType, 'ingresso');
        expect(events.single.cantiereId, 'cant-1');
        // The queued event's own background sync (fire-and-forget, via
        // CantiereTimbraSyncService) races the rest of this test — the fake API client answers
        // that push successfully, so by the time `pumpAndSettle` above has flushed every pending
        // microtask, the event is already marked synced. The point of this test is that the
        // *screen* never blocked on reachability, not that the queue stays pending forever.
        expect(events.single.isPendingSync, isFalse);
        expect(api.upsertCalls, isNotEmpty);

        await _teardown(tester);
      },
    );
  });
}
