// Widget tests for TimbraScreen.
//
// Uses in-memory Drift + Riverpod overrides; no network.
// The screen has a 1-second Timer.periodic for the live clock. We dispose
// it by advancing fake time by 1 s, then replacing the widget. This avoids
// the "timer still pending" assertion from the test framework.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart'
    show nowProvider;
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart'
    show giornataProvider, serverDayProvider, todaySessionsProvider;
import 'package:tasktap_mobile/features/timbra/timbra_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

// ── No-op stubs (prevent Dio from being constructed by providers) ─────────────

abstract class _StubRepo implements IWorkSessionRepository {
  @override
  Stream<List<WorkSession>> watchSyncFailedSessions({
    Duration within = const Duration(days: 7),
  }) => const Stream<List<WorkSession>>.empty();

  @override
  Future<void> markSyncFailed(String id) async {}

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
    double? gpsAccuracyMeters,
  }) async {}

  @override
  Stream<List<WorkSession>> watchTodaySessions() => const Stream.empty();

  @override
  Future<List<WorkSession>> getTodaySessions() async => [];

  @override
  Stream<List<WorkSession>> watchAllSessions() => const Stream.empty();

  @override
  Future<List<WorkSession>> getAllSessions() async => [];

  @override
  Future<List<WorkSession>> getPendingSessions() async => [];

  @override
  Future<int> getPendingCount() async => 0;

  @override
  Future<void> markSynced(List<String> ids) async {}

  @override
  Future<void> clearToday() async {}

  @override
  Future<void> markReconciledOrphan(String id) async {}
}

class _NoopRepo extends _StubRepo {}

class _NoopApiClient extends WorklogApiClient {
  _NoopApiClient() : super(Dio());

  @override
  Future<List<UpsertSessionResponse>> upsertSessions(
    List<MobileSessionDto> sessions, {
    List<MobileSessionDto> breaks = const [],
  }) async => [];

  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];

  // The rail reads the server's own day through this endpoint (the typed rows, not
  // `/worklog/mobile/today` — see serverDayProvider). A widget test must not reach the network for
  // it: the provider treats any failure as "offline", which would silently pass either way.
  @override
  Future<List<DayWorkLogEntry>> fetchDayEntries({
    required String userId,
    required DateTime day,
    BusinessTime? businessTime,
  }) async => [];
}

TimbraSyncService _makeNoopSyncService() =>
    TimbraSyncService(repo: _NoopRepo(), apiClient: _NoopApiClient());

// ── Test helpers ──────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Widget _buildApp(
  AppDatabase db, {
  ILocationService? locationService,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      timbraSyncServiceProvider.overrideWithValue(_makeNoopSyncService()),
      worklogApiClientProvider.overrideWithValue(_NoopApiClient()),
      // serverDayProvider reads the persisted internal User.Id (a SharedPreferences value). A
      // widget test has no plugin, so give it a stable id; the no-op client returns no rows.
      internalUserIdProvider.overrideWith((ref) async => 'test-user'),
      // Real LocationService touches platform channels (Geolocator) that no widget test here
      // mocks, and PunchNotifier now calls it (best-effort, silent GPS capture — see
      // PunchNotifier._captureGpsSilently) on every punch/pause. DisabledLocationService is the
      // same "no position, never prompts" behavior the app itself falls back to whenever the
      // technician has GPS turned off, so this is a realistic default, not just a test workaround.
      locationServiceProvider.overrideWithValue(
        locationService ?? const DisabledLocationService(),
      ),
      ...extraOverrides,
    ],
    child: const MaterialApp(home: TimbraScreen()),
  );
}

/// Disposes the screen by unmounting it, which cancels the Timer.periodic.
/// Must be called at the end of every test.
Future<void> _teardownTimer(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  // Pump enough times to flush any pending zero-duration timers (e.g., Drift).
  for (var i = 0; i < 5; i++) {
    await tester.pump(Duration.zero);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;

  setUpAll(() async => initializeDateFormatting('it'));
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('TimbraScreen renders Scaffold', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('shows INIZIA TURNO initially', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump();
    expect(find.text('INIZIA TURNO'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets(
    'offers a back control — this route is pushed on the root navigator',
    (tester) async {
      // Defect: the screen sits on the root navigator, so the app's tab bar is not on screen and
      // the header declared no leading control. Android's system gesture was the only way out.
      await tester.pumpWidget(_buildApp(db));
      await tester.pump();

      expect(find.bySemanticsLabel('Indietro'), findsOneWidget);
      await _teardownTimer(tester);
    },
  );

  testWidgets('shows Nessuna timbratura oggi when no sessions', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 100));
    // serverDayProvider waits for the persisted internal user id before it can say the server's
    // day is complete; let that future settle before asserting the empty-day copy.
    await tester.pump();
    expect(find.text('Nessuna timbratura oggi'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('punch button tap puts the first stretch on the day', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('INIZIA TURNO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Turno'), findsOneWidget);
    // The whole point of the rebuild: every stretch says who recorded it.
    expect(find.textContaining('questo telefono'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('an unsent punch is marked on its own row', (tester) async {
    // Pre-seed a pending session directly into the DB.
    await db
        .into(db.workSessions)
        .insert(
          WorkSessionsCompanion.insert(
            id: 'test-pending',
            eventTime: DateTime.now().toUtc(),
            eventType: 'ingresso',
          ),
        );

    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('in attesa'), findsOneWidget);
    await _teardownTimer(tester);
  });

  // The defect this screen was rebuilt for: a punch made on the totem, on another device, or
  // corrected by the office never appeared, so the total undercounted and the technician had no
  // way to see it was wrong. The row now comes from the server's day, merged with this phone's
  // own unsent punches, and it says where it came from.
  testWidgets('a punch this phone never made is in the day, and says so', (
    tester,
  ) async {
    final clock = DateTime.utc(2026, 7, 10, 7); // 09:00 Rome
    await tester.pumpWidget(
      _buildApp(
        db,
        extraOverrides: [
          businessTimeProvider.overrideWithValue(
            BusinessTime('Europe/Rome', clock: () => clock),
          ),
          nowProvider.overrideWith((ref) => Stream.value(clock)),
          serverDayProvider.overrideWith(
            (ref) async => [
              DayWorkLogEntry(
                id: 'srv-1',
                clientId: null,
                start: DateTime.utc(2026, 7, 10, 6), // 08:00 Rome
                end: DateTime.utc(2026, 7, 10, 7), // 09:00 Rome
                kind: DayWorkLogKind.ordinary,
                sorgente: 'totem',
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Turno'), findsOneWidget);
    expect(find.textContaining('totem'), findsOneWidget);
    // …and it is inside the total, which is the number that used to undercount.
    expect(find.bySemanticsLabel('Ore lavorate oggi 1h 00m'), findsOneWidget);

    await _teardownTimer(tester);
  });

  // A punch the server permanently refused is hidden from every count on this screen on purpose
  // (a rejected opener would double the day, and nothing will retry it), so before this notice
  // existed the only trace was a toast that scrolled away. Seeded through the real repository so
  // the test exercises the same marker and window the app uses.
  testWidgets('a refused punch is named on screen and opens its details', (
    tester,
  ) async {
    final repo = WorkSessionRepository(db);
    await repo.addEvent(
      id: 'refused',
      eventTime: DateTime.now().toUtc(),
      eventType: 'ingresso',
    );
    await repo.markSyncFailed('refused');

    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 timbratura non registrata dal server'), findsOneWidget);
    // Still hidden from "Sessioni di oggi" — the notice is the only place it shows.
    expect(find.text('Ingresso'), findsNothing);

    await tester.tap(find.text('1 timbratura non registrata dal server'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ingresso'), findsOneWidget);
    expect(find.textContaining('segnalale all'), findsOneWidget);

    await _teardownTimer(tester);
  });

  // ── Pause / resume control ────────────────────────────────────────────────
  //
  // `togglePause` existed on PunchNotifier with nothing in the UI calling it
  // (break start/end was unreachable). These verify the pill is wired up: it
  // only appears once a shift is open, and toggles between PAUSA/RIPRENDI
  // while recording the corresponding session.

  group('pause/resume control', () {
    testWidgets('is not shown before a shift starts', (tester) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PAUSA'), findsNothing);
      expect(find.text('RIPRENDI'), findsNothing);
      await _teardownTimer(tester);
    });

    testWidgets('appears labeled PAUSA once a shift is open', (tester) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('PAUSA'), findsOneWidget);
      await _teardownTimer(tester);
    });

    testWidgets('tapping PAUSA records a Pausa entry and flips to RIPRENDI', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('PAUSA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Pausa'), findsOneWidget);
      expect(find.text('RIPRENDI'), findsOneWidget);
      expect(find.text('PAUSA'), findsNothing);
      await _teardownTimer(tester);
    });

    testWidgets(
      'tapping RIPRENDI records a Ripresa entry and flips back to PAUSA',
      (tester) async {
        await tester.pumpWidget(_buildApp(db));
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('INIZIA TURNO'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('PAUSA'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('RIPRENDI'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Two worked stretches now — the one before the pause and the one after it.
        expect(find.text('Turno'), findsNWidgets(2));
        expect(find.text('PAUSA'), findsOneWidget);
        await _teardownTimer(tester);
      },
    );

    testWidgets('disappears again once the shift ends', (tester) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('PAUSA'), findsOneWidget);

      await tester.tap(find.text('FINE TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('PAUSA'), findsNothing);
      expect(find.text('RIPRENDI'), findsNothing);
      await _teardownTimer(tester);
    });
  });

  /// The screen's height budget, which used to be spent badly in both directions.
  ///
  /// It began as one SingleChildScrollView, so the punch button — the only reason to open the
  /// screen — could be scrolled off it and on a small phone started that way. Pinning everything
  /// instead is the opposite failure: the controls take about 400dp, so on a 640dp viewport the
  /// session list gets a few pixels and shows nothing at all.
  group('layout adapts to the height it is given', () {
    testWidgets(
      'a tall phone holds the controls still and scrolls only the sessions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_buildApp(db));
        await tester.pump(const Duration(milliseconds: 50));

        // The punch control is not inside anything that scrolls, so it cannot leave the screen.
        expect(
          find.ancestor(
            of: find.text('INIZIA TURNO'),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        await _teardownTimer(tester);
      },
    );

    testWidgets(
      'a short phone scrolls the page rather than crushing the list',
      (tester) async {
        // A squeezed session card is worse than a scroll: the day's total is the one number on it
        // anybody is looking for, and at a few pixels tall nothing renders at all.
        await tester.binding.setSurfaceSize(const Size(320, 560));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_buildApp(db));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'no overflow at the smallest supported size',
        );
        await _teardownTimer(tester);
      },
    );
  });

  // ── Status-First Hero (2026-08-30) ────────────────────────────────────────
  //
  // The state badge (IN TURNO / IN PAUSA / FUORI TURNO) and the promoted guard banner replacing
  // the old under-button reason text.

  group('hero status', () {
    testWidgets('shows FUORI TURNO before any shift starts', (tester) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('FUORI TURNO'), findsOneWidget);
      await _teardownTimer(tester);
    });

    testWidgets('shows IN TURNO once a shift starts', (tester) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // The status pill crossfades on change (AnimatedSwitcher, 220ms) — let it finish so the
      // outgoing label is actually gone, not mid-fade.
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('IN TURNO'), findsOneWidget);
      expect(find.text('FUORI TURNO'), findsNothing);
      await _teardownTimer(tester);
    });

    testWidgets('shows IN PAUSA while on break', (tester) async {
      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('PAUSA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('IN PAUSA'), findsOneWidget);
      expect(find.text('IN TURNO'), findsNothing);
      await _teardownTimer(tester);
    });
  });

  group('guard banner', () {
    GiornataDto giornataWith(GiornataActionDto action) => GiornataDto(
      status: 'Working',
      workedMinutes: 0,
      breakMinutes: 0,
      isPayrollLocked: action.reasonCode == 'payroll_locked',
      actions: [action],
    );

    testWidgets(
      'renders the server reason above the punch button when ClockIn is refused',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            db,
            extraOverrides: [
              giornataProvider.overrideWith(
                (ref) async => giornataWith(
                  const GiornataActionDto(
                    action: 'ClockIn',
                    enabled: false,
                    reasonCode: 'payroll_locked',
                    reason: "Il periodo è chiuso per le buste paga: chiedi all'amministrazione.",
                  ),
                ),
              ),
            ],
          ),
        );
        // Let giornataProvider's future resolve before asserting on its dependents.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        // findsOneWidget also proves it is not duplicated under the dimmed button anymore —
        // _PunchButton no longer renders its own copy of the reason (see its doc comment).
        expect(find.textContaining('chiuso per le buste paga'), findsOneWidget);
        await _teardownTimer(tester);
      },
    );

    testWidgets('does not render when ClockIn is allowed', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: [
            giornataProvider.overrideWith(
              (ref) async => giornataWith(
                const GiornataActionDto(action: 'ClockIn', enabled: true),
              ),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(LucideIcons.alertTriangle), findsNothing);
      await _teardownTimer(tester);
    });
  });

  // ── Clock-in method gating (Task 13) ──────────────────────────────────────
  //
  // effectiveClockInMethodProvider (Task 12) reflects the tenant/user's configured clock-in
  // method. This is a UI-only gate for UX purposes — the backend already enforces the real
  // authorization on both the button and kiosk-QR clock-in endpoints.

  group('clock-in method gating', () {
    // The QrOnly case moved to smart_working_chip_test.dart when the button became conditional on
    // the smart-working flag too: the method alone no longer decides, so its assertions live
    // beside the flag's own, in one place.

    testWidgets('hides the header QR icon when method is buttonOnly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: [
            effectiveClockInMethodProvider.overrideWithValue('ButtonOnly'),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.bySemanticsLabel('Timbra con QR'), findsNothing);
      expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
      // The punch button remains available.
      expect(find.text('INIZIA TURNO'), findsOneWidget);

      await _teardownTimer(tester);
    });

    testWidgets(
      'shows both the punch button and the QR header icon when method is both',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            db,
            extraOverrides: [
              effectiveClockInMethodProvider.overrideWithValue('Both'),
            ],
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('INIZIA TURNO'), findsOneWidget);
        expect(find.bySemanticsLabel('Timbra con QR'), findsOneWidget);

        await _teardownTimer(tester);
      },
    );

    testWidgets(
      'shows both by default (no override) — existing behavior unchanged',
      (tester) async {
        await tester.pumpWidget(_buildApp(db));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('INIZIA TURNO'), findsOneWidget);
        expect(find.bySemanticsLabel('Timbra con QR'), findsOneWidget);

        await _teardownTimer(tester);
      },
    );
  });

  group('business-zone time (device zone irrelevant)', () {
    List<Override> zoneOverrides(
      DateTime clockInstant, {
      List<WorkSession>? sessions,
    }) => [
      businessTimeProvider.overrideWithValue(
        BusinessTime('Europe/Rome', clock: () => clockInstant),
      ),
      nowProvider.overrideWith((ref) => Stream.value(clockInstant)),
      if (sessions != null)
        todaySessionsProvider.overrideWith((ref) => Stream.value(sessions)),
    ];

    testWidgets('punch row shows Rome wall-clock time', (tester) async {
      final clock = DateTime.utc(2026, 7, 10, 7);
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: zoneOverrides(
            clock,
            sessions: [
              WorkSession(
                id: 's1',
                eventTime: DateTime.utc(2026, 7, 10, 6),
                eventType: 'ingresso',
                isPendingSync: false,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      // The rail's own label, not a bare `08:00` — the gutter prints the same string as an hour
      // tick, so a substring match would count the scale as well as the punch.
      expect(find.textContaining('dal 08:00'), findsOneWidget);
      await _teardownTimer(tester);
    });

    testWidgets('small clock shows Rome time with seconds', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: zoneOverrides(DateTime.utc(2026, 7, 10, 20, 15, 30)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('22:15:30'), findsOneWidget);
      await _teardownTimer(tester);
    });

    testWidgets('date subtitle uses the Rome calendar date', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: zoneOverrides(DateTime.utc(2026, 7, 10, 22, 30)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('SAB 11 LUG 2026'), findsOneWidget);
      await _teardownTimer(tester);
    });
  });

  // ── Server-day freshness ─────────────────────────────────────────────────
  //
  // The guard used to keep the first `/api/worklog/today` answer for as long as the screen
  // stayed open. After a punch (or a punch from another device) it could therefore keep saying
  // "Non risulti in servizio" even though the local day says the shift is open — and the finish
  // button stayed disabled. The day must be re-read when the screen refreshes and after a punch.
  group('server-day freshness', () {
    testWidgets('a live refresh clears a stale not_clocked_in guard', (
      tester,
    ) async {
      final repo = WorkSessionRepository(db);
      await repo.addEvent(
        id: 'open-shift',
        eventTime: DateTime.now().toUtc(),
        eventType: 'ingresso',
      );
      await repo.markSynced(['open-shift']);

      var calls = 0;
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: [
            giornataProvider.overrideWith((ref) async {
              calls++;
              if (calls == 1) {
                return const GiornataDto(
                  status: 'ClockedOut',
                  workedMinutes: 0,
                  breakMinutes: 0,
                  isPayrollLocked: false,
                  actions: [
                    GiornataActionDto(
                      action: 'ClockOut',
                      enabled: false,
                      reasonCode: 'not_clocked_in',
                      reason: 'Non risulti in servizio.',
                    ),
                  ],
                );
              }
              return const GiornataDto(
                status: 'Working',
                workedMinutes: 0,
                breakMinutes: 0,
                isPayrollLocked: false,
                actions: [GiornataActionDto(action: 'ClockOut', enabled: true)],
              );
            }),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Non risulti in servizio'), findsOneWidget);

      // WorkLogLiveRefresh polls every 15s; the second answer is the synced truth.
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();

      expect(calls, greaterThan(1));
      expect(find.textContaining('Non risulti in servizio'), findsNothing);
      await _teardownTimer(tester);
    });

    testWidgets('a local punch invalidates the guard immediately', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _buildApp(
          db,
          extraOverrides: [
            giornataProvider.overrideWith((ref) async {
              calls++;
              return const GiornataDto(
                status: 'ClockedOut',
                workedMinutes: 0,
                breakMinutes: 0,
                isPayrollLocked: false,
                actions: [GiornataActionDto(action: 'ClockIn', enabled: true)],
              );
            }),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      final initialCalls = calls;
      expect(initialCalls, greaterThanOrEqualTo(1));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('IN TURNO'), findsOneWidget);
      expect(calls, greaterThan(initialCalls));
      await _teardownTimer(tester);
    });
  });
}
