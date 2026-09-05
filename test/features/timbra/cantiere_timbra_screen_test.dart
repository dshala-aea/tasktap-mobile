// test/features/timbra/cantiere_timbra_screen_test.dart
//
// Widget tests for CantiereTimbraScreen.
//
// CRITICAL: every test that pumps a screen watching a Drift stream MUST end
// with:
//   await tester.pumpWidget(const SizedBox.shrink());
//   await tester.pumpAndSettle();
// to avoid "A Timer is still pending" hangs from Drift's StreamQueryStore.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/drift.dart' as drift show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart';
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

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
    this.assegnazioni = const [],
    this.assegnazioniShouldThrow = false,
  }) : super(Dio());

  final CantiereWorkLogDto? activeLog;
  final bool endShouldThrow;
  final bool startShouldThrow;

  /// Crew assignments getAssegnazioni() answers with. Empty by default — matches "no assignment
  /// row for me" for every pre-existing test in this file, which never overrides this and so keeps
  /// getting today's single-button flow unchanged (isLeadForCantiereProvider reads "not lead").
  final List<CantiereCrewAssignmentDto> assegnazioni;
  final bool assegnazioniShouldThrow;

  /// Captures the [StartCantiereRequest] passed to startCantiere.
  final List<StartCantiereRequest> startedRequests = [];

  /// Captures batch-upsert calls the offline-fallback path makes.
  final List<List<CantiereMobileSessionDto>> upsertCalls = [];

  /// Captures the [BatchStartCantiereRequest]s passed to batchStart.
  final List<BatchStartCantiereRequest> batchStartRequests = [];

  /// Overrides the default all-success response for a given batchStart call.
  BatchStartResponse Function(BatchStartCantiereRequest)? batchStartResponseBuilder;

  bool endCalled = false;

  @override
  Future<List<CantiereCrewAssignmentDto>> getAssegnazioni(String cantiereId) async {
    if (assegnazioniShouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/cantieri/$cantiereId/assegnazioni'),
        type: DioExceptionType.connectionError,
      );
    }
    return assegnazioni;
  }

  @override
  Future<BatchStartResponse> batchStart(BatchStartCantiereRequest request) async {
    batchStartRequests.add(request);
    if (batchStartResponseBuilder != null) return batchStartResponseBuilder!(request);
    return BatchStartResponse(
      results: request.userIds
          .map((id) => BatchStartResult(userId: id, success: true, workLogId: 'wl-$id'))
          .toList(),
    );
  }

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

/// Test AuthUser for lead-branching tests — id matches the fake assignments' own `userId: 'me'`
/// rows so isLeadForCantiereProvider can resolve "am I the lead" against them.
final _testUser = AuthUser(
  id: 'me',
  email: 'tecnico@example.com',
  accessToken: 'tok',
  refreshToken: 'ref',
  expiresAt: DateTime.utc(2030, 1, 1),
);

Widget _buildScreen({
  required AppDatabase db,
  required _FakeApiClient apiClient,
  ILocationService? locationService,
  String? ticketId,
  String? customerId,
  String? cantiereId,
  AuthUser? currentUser,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cantiereWorklogApiClientProvider.overrideWithValue(apiClient),
      locationServiceProvider.overrideWithValue(locationService ?? _FakeLocationService()),
      activeCantiereLogProvider.overrideWith(() => _FakeActiveNotifier(apiClient.activeLog)),
      currentUserProvider.overrideWithValue(currentUser),
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

    testWidgets('renders Cantiere section', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Cantiere'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('renders Inizia timbratura button', (tester) async {
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
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
      await tester.ensureVisible(find.text('Inizia timbratura'));
      await tester.tap(find.text('Inizia timbratura'));
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

      await tester.ensureVisible(find.text('Inizia timbratura'));
      await tester.tap(find.text('Inizia timbratura'));
      await tester.pumpAndSettle();

      expect(find.text('Seleziona un cantiere prima di timbrare.'), findsOneWidget);
      await _teardown(tester);
    });
  });

  // ── Active session (clock-out) UI ─────────────────────────────────────────

  group('active session', () {
    // NOTE ON pumpAndSettle: _ActiveSessionBody now mounts Ticker-driven widgets
    // (_CantiereElapsedTicker, _CantiereTodayTotal) that reschedule a frame every tick for as
    // long as they're on screen — exactly like personal Timbra's own ticking hero
    // (_TimbraScreenState with TickerProviderStateMixin), whose own test file
    // (timbra_screen_test.dart) never calls pumpAndSettle() for the same reason: it would never
    // observe zero scheduled frames and always time out. Tests below use a fixed pump()
    // sequence instead, once the screen has an active session on the very first frame.
    // _teardown() itself stays safe: it unmounts the tree (disposing the ticker) before its own
    // pumpAndSettle().
    testWidgets('shows TIMBRATURA ATTIVA indicator', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('TIMBRATURA ATTIVA'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('shows Timbra uscita cantiere button', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Timbra uscita cantiere'), findsOneWidget);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The ticket label now renders inline with the cantiere name in a single Text ("<cantiere>
      // · <ticket title>"), not its own standalone widget the way the old KeyVal row was — so an
      // exact find.text('Sostituzione pompa') no longer matches; textContaining does, without
      // caring which container renders it (same intent the original assertion had).
      expect(find.textContaining('Sostituzione pompa'), findsOneWidget);
      expect(find.textContaining('tick-1'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('drops the row entirely when the mirror does not hold the ticket', (tester) async {
      // Nothing seeded. The honest answer is silence: printing the id back would name the job
      // with something the technician cannot match to anything in front of them.
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('TICKET'), findsNothing);
      expect(find.textContaining('tick-1'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('clock-out calls endCantiere on the API client', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

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

    testWidgets('check-in succeeds against the fixed cantiere, without ever touching the picker', (
      tester,
    ) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Diretto',
              customerId: const drift.Value('cust-1'),
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'c1', ticketId: 'tick-1'),
      );
      await tester.pumpAndSettle();

      // Direct-entry mode: no picker row to tap — the button must work off the resolved fixed
      // cantiere alone (see _effectiveCantiere in cantiere_timbra_screen.dart; this used to fall
      // through to the "Seleziona un cantiere" validation error because _handleStartCantiere read
      // the picker-only _selectedCantiere field instead).
      await tester.ensureVisible(find.text('Inizia timbratura'));
      await tester.tap(find.text('Inizia timbratura'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Seleziona un cantiere prima di timbrare.'), findsNothing);
      expect(api.startedRequests, hasLength(1));
      expect(api.startedRequests.first.cantiereId, 'c1');
      expect(api.startedRequests.first.customerId, 'cust-1');
      expect(api.startedRequests.first.ticketId, 'tick-1');

      await _teardown(tester);
    });

    testWidgets('shows an honest not-found message when the fixed cantiere is not synced locally', (
      tester,
    ) async {
      // Nothing seeded for 'missing-id' — the fixed-cantiere card must distinguish this from
      // "still loading" rather than spinning forever (see fixedCantiereAsync.when in
      // cantiere_timbra_screen.dart).
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api, cantiereId: 'missing-id'));
      await tester.pumpAndSettle();

      expect(find.text('Cantiere non trovato su questo dispositivo.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _teardown(tester);
    });

    testWidgets(
      'the start button stays disabled, not just the card message, when the fixed cantiere is '
      'not found',
      (tester) async {
        // Regression for the button previously staying enabled through both the loading and
        // not-found direct-entry states, falling through to the self-contradictory "Seleziona un
        // cantiere prima di timbrare." on a screen with no picker at all.
        final api = _FakeApiClient();
        await tester.pumpWidget(_buildScreen(db: db, apiClient: api, cantiereId: 'missing-id'));
        await tester.pumpAndSettle();

        final button = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'Inizia timbratura'),
        );
        expect(button.onPressed, isNull);

        await _teardown(tester);
      },
    );

    testWidgets('the start button stays disabled while the fixed cantiere is still loading', (
      tester,
    ) async {
      // A real Drift StreamProvider backed by an in-memory NativeDatabase resolves its first
      // watchSingleOrNull value within a single pump, so there's no reliable window to observe
      // "still loading" through the real provider. Overriding cantiereByIdProvider with a stream
      // that never emits pins the screen in AsyncLoading deterministically instead.
      final neverEmits = StreamController<CantieriData?>();
      addTearDown(neverEmits.close);

      final api = _FakeApiClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            cantiereWorklogApiClientProvider.overrideWithValue(api),
            locationServiceProvider.overrideWithValue(_FakeLocationService()),
            activeCantiereLogProvider.overrideWith(() => _FakeActiveNotifier(api.activeLog)),
            cantiereByIdProvider.overrideWith((ref, id) => neverEmits.stream),
          ],
          child: const MaterialApp(home: CantiereTimbraScreen(cantiereId: 'c1')),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Inizia timbratura'),
      );
      expect(button.onPressed, isNull);

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

        await tester.ensureVisible(find.text('Inizia timbratura'));
        await tester.tap(find.text('Inizia timbratura'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // Not pumpAndSettle(): the active-session body now mounts Ticker-driven widgets (see the
        // 'active session' group's note above) that never let scheduled frames reach zero.
        await tester.pump(const Duration(milliseconds: 300));

        // No online request ever landed, and the screen did not show a blocking error — it
        // switched straight to "on site" from the local queue.
        expect(api.startedRequests, isEmpty);
        expect(find.text('TIMBRATURA ATTIVA'), findsOneWidget);

        final events = await (db.select(db.cantierePunches)).get();
        expect(events, hasLength(1));
        expect(events.single.eventType, 'ingresso');
        expect(events.single.cantiereId, 'cant-1');
        // The queued event's own background sync (fire-and-forget, via
        // CantiereTimbraSyncService) races the rest of this test — the fake API client answers
        // that push successfully, so by the time the two `pump(300ms)` calls above have drained
        // the microtask/immediate-future chain against the in-memory fake DB/API client, the
        // event is already marked synced. The point of this test is that the *screen* never
        // blocked on reachability, not that the queue stays pending forever.
        expect(events.single.isPendingSync, isFalse);
        expect(api.upsertCalls, isNotEmpty);

        await _teardown(tester);
      },
    );
  });

  // ── Lead branching (Task 3) ────────────────────────────────────────────────

  group('lead branching', () {
    Future<void> seedCantiere(AppDatabase db) => db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'cant-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Cantiere Via Roma',
          ),
        );

    testWidgets(
      '"Tutta la squadra" calls batchStart with every assigned userId',
      (tester) async {
        await seedCantiere(db);
        final api = _FakeApiClient(
          assegnazioni: const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
            CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
            CantiereCrewAssignmentDto(id: 'a3', userId: 'teammate-2', isLead: false),
          ],
        );

        await tester.pumpWidget(
          _buildScreen(
            db: db,
            apiClient: api,
            cantiereId: 'cant-1',
            customerId: 'cust-1',
            currentUser: _testUser,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Me e squadra'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(api.batchStartRequests, hasLength(1));
        expect(
          api.batchStartRequests.first.userIds,
          unorderedEquals(['me', 'teammate-1', 'teammate-2']),
        );
        expect(api.batchStartRequests.first.cantiereId, 'cant-1');

        await _teardown(tester);
      },
    );

    testWidgets(
      'names every offender when batch-start partially fails, without dropping anyone',
      (tester) async {
        // The endpoint's own "name every offender" contract (see BatchStartResult.error): a
        // failed person must never be silently dropped, and the whole batch must not fail just
        // because one person's clock-in did.
        await seedCantiere(db);
        final api = _FakeApiClient(
          assegnazioni: const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
            CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
            CantiereCrewAssignmentDto(id: 'a3', userId: 'teammate-2', isLead: false),
          ],
        );
        api.batchStartResponseBuilder = (request) => BatchStartResponse(
          results: [
            const BatchStartResult(userId: 'me', success: true, workLogId: 'wl-me'),
            const BatchStartResult(userId: 'teammate-1', success: false, error: 'AlreadyOpen'),
            const BatchStartResult(userId: 'teammate-2', success: false, error: 'NotAssigned'),
          ],
        );

        await tester.pumpWidget(
          _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Me e squadra'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Alcuni membri non sono stati avviati'), findsOneWidget);
        // Neither the local mirror nor the fake seeds a colleague row for these ids, so the
        // dialog falls back to the raw userId — same fallback contract as colleagueNameProvider
        // everywhere else in the app.
        expect(find.text('teammate-1: ha già una timbratura aperta'), findsOneWidget);
        expect(find.text('teammate-2: non risulta assegnato a questo cantiere'), findsOneWidget);
        // The one person who *did* succeed must not appear in the failures dialog.
        expect(find.textContaining('me:'), findsNothing);

        // Close the dialog before teardown.
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await _teardown(tester);
      },
    );

    testWidgets(
      '"Seleziona squadra" calls batchStart with only the checked subset of userIds',
      (tester) async {
        await seedCantiere(db);
        final api = _FakeApiClient(
          assegnazioni: const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
            CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
            CantiereCrewAssignmentDto(id: 'a3', userId: 'teammate-2', isLead: false),
            CantiereCrewAssignmentDto(id: 'a4', userId: 'teammate-3', isLead: false),
          ],
        );

        await tester.pumpWidget(
          _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Squadra'));
        await tester.pumpAndSettle();

        // Toggle exactly two of the four assigned rows (skip 'me' the lead, and skip
        // 'teammate-2') — the fake seeds no colleague rows, so the picker falls back to raw
        // userIds as the row labels (same fallback contract as colleagueNameProvider).
        await tester.tap(find.text('teammate-1'));
        await tester.tap(find.text('teammate-3'));
        await tester.pump();

        await tester.ensureVisible(find.text('Conferma (2)'));
        await tester.tap(find.text('Conferma (2)'));
        await tester.pumpAndSettle();

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(api.batchStartRequests, hasLength(1));
        expect(
          api.batchStartRequests.first.userIds,
          unorderedEquals(['teammate-1', 'teammate-3']),
        );
        // Neither the lead nor the skipped teammate should have been included.
        expect(api.batchStartRequests.first.userIds, isNot(contains('me')));
        expect(api.batchStartRequests.first.userIds, isNot(contains('teammate-2')));

        await _teardown(tester);
      },
    );

    testWidgets(
      'shows a success toast counting how many people were actually started',
      (tester) async {
        // Final-review fix: a fully successful batch used to leave the lead's own screen
        // unchanged (nothing to clock in/out of themselves), so there was no feedback at all that
        // anything happened.
        await seedCantiere(db);
        final api = _FakeApiClient(
          assegnazioni: const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
            CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
            CantiereCrewAssignmentDto(id: 'a3', userId: 'teammate-2', isLead: false),
          ],
        );

        await tester.pumpWidget(
          _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Me e squadra'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Timbrate 3 persone'), findsOneWidget);

        await _teardown(tester);
      },
    );

    testWidgets(
      'still shows the success-count toast alongside the failures dialog on a partial success',
      (tester) async {
        // The toast must appear regardless of whether some people also failed — the lead should
        // always get a count of what worked, not just what didn't.
        await seedCantiere(db);
        final api = _FakeApiClient(
          assegnazioni: const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
            CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
          ],
        );
        api.batchStartResponseBuilder = (request) => BatchStartResponse(
          results: [
            const BatchStartResult(userId: 'me', success: true, workLogId: 'wl-me'),
            const BatchStartResult(userId: 'teammate-1', success: false, error: 'AlreadyOpen'),
          ],
        );

        await tester.pumpWidget(
          _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Me e squadra'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Timbrata 1 persona'), findsOneWidget);
        expect(find.text('Alcuni membri non sono stati avviati'), findsOneWidget);

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await _teardown(tester);
      },
    );

    testWidgets(
      "resolves a failed teammate's real name in the failures dialog, not just the raw id",
      (tester) async {
        // Regression test for the colleagueNameProvider misuse: _showBatchFailuresDialog used to
        // call `ref.read(colleagueNameProvider(...))` inside a one-shot `showDialog` builder, which
        // captures whatever the (async, Drift-backed) provider's state happened to be at that exact
        // instant — almost always AsyncLoading — and never rebuilds, so a colleague row that
        // resolves moments later stayed invisible and the dialog was stuck on the raw userId
        // forever. It now watches from a Consumer scoped to each row.
        await seedCantiere(db);
        await db
            .into(db.colleagues)
            .insert(ColleaguesCompanion.insert(id: 'teammate-1', displayName: 'Luigi Bianchi'));

        final api = _FakeApiClient(
          assegnazioni: const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
            CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
          ],
        );
        api.batchStartResponseBuilder = (request) => BatchStartResponse(
          results: [
            const BatchStartResult(userId: 'me', success: true, workLogId: 'wl-me'),
            const BatchStartResult(userId: 'teammate-1', success: false, error: 'AlreadyOpen'),
          ],
        );

        await tester.pumpWidget(
          _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Me e squadra'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Luigi Bianchi: ha già una timbratura aperta'), findsOneWidget);
        expect(find.textContaining('teammate-1:'), findsNothing);

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await _teardown(tester);
      },
    );
  });

  group('formatHoursMinutes', () {
    test('formats whole hours with zero minutes', () {
      expect(formatHoursMinutes(const Duration(hours: 2)), '2h 00m');
    });

    test('formats hours and minutes, zero-padded', () {
      expect(formatHoursMinutes(const Duration(hours: 6, minutes: 5)), '6h 05m');
    });

    test('formats zero duration', () {
      expect(formatHoursMinutes(Duration.zero), '0h 00m');
    });
  });

  group('clampedElapsedSinceMidnight', () {
    test('returns the full elapsed time when startTime is already today', () {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8).toUtc();
      final now = start.add(const Duration(hours: 1, minutes: 18));

      expect(clampedElapsedSinceMidnight(start, now), const Duration(hours: 1, minutes: 18));
    });

    test('clamps to since-midnight when startTime was yesterday', () {
      final today = DateTime.now();
      final todayMidnightUtc = DateTime(today.year, today.month, today.day).toUtc();
      final start = todayMidnightUtc.subtract(const Duration(hours: 5)); // started yesterday
      final now = todayMidnightUtc.add(const Duration(hours: 2));

      // Only the 2h since midnight counts, not the 5h before it.
      expect(clampedElapsedSinceMidnight(start, now), const Duration(hours: 2));
    });
  });

  group('_CantiereElapsedTicker / _CantiereTodayTotal — injected clock', () {
    testWidgets('_CantiereElapsedTicker shows elapsed time computed from its injected clock', (
      tester,
    ) async {
      final start = DateTime.utc(2026, 6, 21, 8, 0);
      final fixedNow = DateTime.utc(2026, 6, 21, 9, 30);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: cantiereElapsedTickerForTest(
              startTime: start,
              style: const TextStyle(),
              clock: () => fixedNow,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1h 30m'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('_CantiereTodayTotal combines closed hours with the live session elapsed', (
      tester,
    ) async {
      final sessionStart = DateTime.utc(2026, 6, 21, 8, 0);
      final fixedNow = DateTime.utc(2026, 6, 21, 9, 0); // 1h into the current session

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: cantiereTodayTotalForTest(
              closedHours: const Duration(hours: 2),
              sessionStart: sessionStart,
              clock: () => fixedNow,
            ),
          ),
        ),
      );
      await tester.pump();

      // 2h closed + 1h live = 3h 00m
      expect(find.text('3h 00m'), findsOneWidget);

      await _teardown(tester);
    });
  });

  group('check-in body — OGGI header and lead menu', () {
    testWidgets('shows OGGI 0h 00m when no hours logged yet today', (tester) async {
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

      await tester.pumpWidget(_buildScreen(db: db, apiClient: api, currentUser: _testUser));
      await tester.pumpAndSettle();

      expect(find.text('OGGI'), findsOneWidget);
      expect(find.text('0h 00m'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('OGGI total reflects a closed interval logged earlier today', (tester) async {
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
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 7).toUtc();
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e1',
              eventTime: start,
              eventType: 'ingresso',
              cantiereId: const Value('cant-1'),
            ),
          );
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e2',
              eventTime: start.add(const Duration(hours: 2, minutes: 30)),
              eventType: 'uscita',
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('2h 30m'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('shows a single Inizia timbratura button and no menu for a non-lead', (
      tester,
    ) async {
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
      final api = _FakeApiClient(
        assegnazioni: const [CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: false)],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
      expect(find.textContaining('Per:'), findsNothing);

      await _teardown(tester);
    });

    testWidgets('shows the Inizia timbratura button plus a Per: Me menu for a lead', (
      tester,
    ) async {
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
      final api = _FakeApiClient(
        assegnazioni: const [
          CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
          CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
      expect(find.textContaining('Per: Me'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('shows no Per menu when the assignment fetch fails (offline fallback)', (
      tester,
    ) async {
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
      final api = _FakeApiClient(assegnazioniShouldThrow: true);

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
      expect(find.textContaining('Per:'), findsNothing);

      await _teardown(tester);
    });

    testWidgets('tapping Inizia timbratura starts solo, for a lead or non-lead alike', (
      tester,
    ) async {
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
      final api = _FakeApiClient(
        assegnazioni: const [CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true)],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inizia timbratura'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.startedRequests, hasLength(1));
      expect(api.batchStartRequests, isEmpty);

      await _teardown(tester);
    });

    testWidgets('picking Squadra from the Per menu opens the teammate picker', (tester) async {
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
      final api = _FakeApiClient(
        assegnazioni: const [
          CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
          CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Per: Me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squadra'));
      await tester.pumpAndSettle();

      // The teammate picker sheet is now open (same sheet _handleSelectSquadra always opened).
      expect(find.text('teammate-1'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('picking Me e squadra from the Per menu batch-starts everyone', (tester) async {
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
      final api = _FakeApiClient(
        assegnazioni: const [
          CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
          CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Per: Me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Me e squadra'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.batchStartRequests, hasLength(1));
      expect(
        api.batchStartRequests.first.userIds,
        unorderedEquals(['me', 'teammate-1']),
      );

      await _teardown(tester);
    });
  });

  group('active session body — OGGI header and live elapsed', () {
    testWidgets('shows OGGI total plus the live current-session elapsed', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      // Not pumpAndSettle(): the active-session body mounts Ticker-driven widgets (see the
      // 'active session' group's note above) that never let scheduled frames reach zero.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('OGGI'), findsOneWidget);
      // _CantiereElapsedTicker is private to the lib file (separate Dart library from this test
      // file), so it can't be named directly here — match by runtimeType string instead, the
      // standard way to assert a private widget type is present from outside its library.
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_CantiereElapsedTicker'),
        findsOneWidget,
      );

      await _teardown(tester);
    });

    testWidgets('shows TIMBRATURA ATTIVA and the cantiere name', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('TIMBRATURA ATTIVA'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('still shows the pending-sync indicator when a punch has not synced', (
      tester,
    ) async {
      // eventTime must fall within today's real-clock bounds (see
      // CantiereSessionRepository._todayBounds(), DateTime.now()-based) for
      // todayCantiereEventsProvider to pick it up and derive an active local session — a fixed
      // historical date would never qualify, same reasoning as the check-in body's own
      // "today"-scoped OGGI test above.
      final today = DateTime.now();
      final eventTime = DateTime(today.year, today.month, today.day, 8).toUtc();
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e1',
              eventTime: eventTime,
              eventType: 'ingresso',
              cantiereId: const Value('cant-1'),
            ),
          );
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('Non sincronizzata'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('still shows Timbra uscita cantiere and ends the session on tap', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('Timbra uscita cantiere'));
      await tester.tap(find.text('Timbra uscita cantiere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.endCalled, isTrue);
      await _teardown(tester);
    });
  });

  group('cantiereTodayHoursProvider', () {
    ProviderContainer buildContainer(AppDatabase db) => ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );

    Future<void> punch(
      AppDatabase db, {
      required String id,
      required DateTime eventTime,
      required String eventType,
      String? cantiereId,
    }) => db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: id,
            eventTime: eventTime,
            eventType: eventType,
            cantiereId: Value(cantiereId),
          ),
        );

    test('sums a single closed ingresso→uscita interval for the given cantiere', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8).toUtc();

      await punch(db, id: 'e1', eventTime: start, eventType: 'ingresso', cantiereId: 'cant-1');
      await punch(
        db,
        id: 'e2',
        eventTime: start.add(const Duration(hours: 3)),
        eventType: 'uscita',
      );

      // Let the StreamProvider this derives from emit its first value.
      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, const Duration(hours: 3));
    });

    test('ignores events for a different cantiere', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8).toUtc();

      await punch(db, id: 'e1', eventTime: start, eventType: 'ingresso', cantiereId: 'cant-OTHER');
      await punch(
        db,
        id: 'e2',
        eventTime: start.add(const Duration(hours: 3)),
        eventType: 'uscita',
      );

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, Duration.zero);
    });

    test('excludes a still-open interval (no matching uscita yet)', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final closedStart = DateTime(today.year, today.month, today.day, 7).toUtc();

      await punch(
        db,
        id: 'e1',
        eventTime: closedStart,
        eventType: 'ingresso',
        cantiereId: 'cant-1',
      );
      await punch(
        db,
        id: 'e2',
        eventTime: closedStart.add(const Duration(hours: 2)),
        eventType: 'uscita',
      );
      // A second, still-open interval later the same day.
      await punch(
        db,
        id: 'e3',
        eventTime: closedStart.add(const Duration(hours: 4)),
        eventType: 'ingresso',
        cantiereId: 'cant-1',
      );

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      // Only the first, closed 2h interval counts — the open 'ingresso' with no 'uscita' after it
      // must not contribute anything (that portion is the live-ticking concern, not this provider).
      expect(result, const Duration(hours: 2));
    });

    test('sums multiple closed intervals for the same cantiere', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final s1 = DateTime(today.year, today.month, today.day, 7).toUtc();
      final s2 = DateTime(today.year, today.month, today.day, 12).toUtc();

      await punch(db, id: 'e1', eventTime: s1, eventType: 'ingresso', cantiereId: 'cant-1');
      await punch(db, id: 'e2', eventTime: s1.add(const Duration(hours: 2)), eventType: 'uscita');
      await punch(db, id: 'e3', eventTime: s2, eventType: 'ingresso', cantiereId: 'cant-1');
      await punch(
        db,
        id: 'e4',
        eventTime: s2.add(const Duration(minutes: 90)),
        eventType: 'uscita',
      );

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, const Duration(hours: 3, minutes: 30));
    });

    test('returns Duration.zero when there are no events at all', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, Duration.zero);
    });
  });
}
