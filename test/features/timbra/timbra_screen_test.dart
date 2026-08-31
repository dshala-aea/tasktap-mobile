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
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart' show giornataProvider;
import 'package:tasktap_mobile/features/timbra/timbra_screen.dart';

// ── No-op stubs (prevent Dio from being constructed by providers) ─────────────

abstract class _StubRepo implements IWorkSessionRepository {
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
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async => [];

  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];
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
      // Real LocationService touches platform channels (Geolocator) that no widget test here
      // mocks, and PunchNotifier now calls it (best-effort, silent GPS capture — see
      // PunchNotifier._captureGpsSilently) on every punch/pause. DisabledLocationService is the
      // same "no position, never prompts" behavior the app itself falls back to whenever the
      // technician has GPS turned off, so this is a realistic default, not just a test workaround.
      locationServiceProvider.overrideWithValue(locationService ?? const DisabledLocationService()),
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

  testWidgets('shows Sessioni di oggi section heading', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump();
    expect(find.text('SESSIONI DI OGGI'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('shows Nessuna timbratura oggi when no sessions', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nessuna timbratura oggi'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('punch button tap adds Ingresso session row', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('INIZIA TURNO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ingresso'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('sync dot appears when isPendingSync events exist', (tester) async {
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

    // The amber sync dot has tooltip "Non sincronizzato".
    expect(find.byTooltip('Non sincronizzato'), findsOneWidget);
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

    testWidgets('tapping PAUSA records a Pausa entry and flips to RIPRENDI', (tester) async {
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

    testWidgets('tapping RIPRENDI records a Ripresa entry and flips back to PAUSA', (tester) async {
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

      expect(find.text('Ripresa'), findsOneWidget);
      expect(find.text('PAUSA'), findsOneWidget);
      await _teardownTimer(tester);
    });

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
    testWidgets('a tall phone holds the controls still and scrolls only the sessions', (
      tester,
    ) async {
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
    });

    testWidgets('a short phone scrolls the page rather than crushing the list', (tester) async {
      // A squeezed session card is worse than a scroll: the day's total is the one number on it
      // anybody is looking for, and at a few pixels tall nothing renders at all.
      await tester.binding.setSurfaceSize(const Size(320, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(db));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow at the smallest supported size');
      await _teardownTimer(tester);
    });
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

    testWidgets('renders the server reason above the punch button when ClockIn is refused', (
      tester,
    ) async {
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
    });

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
}
