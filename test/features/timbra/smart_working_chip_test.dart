// Widget tests for the smart-working chip and the fail-open punch button on TimbraScreen.
//
// Uses in-memory Drift + Riverpod overrides. No request leaves the process: the stub API client
// holds a bare `Dio` and is never called, and the screen's own `/worklog/today` and
// `/worklog/active` reads are answered by the test binding with a 400 — the screen renders those as
// its sessions error line, which nothing here asserts on.
//
// The rule these tests pin is the inversion the feature exists for: only an explicit `false` may
// hide the punch button. `null` (unknown — cold start, signed out, another user, or before
// /auth/me answers) must never take the control away from a technician who is standing on site
// needing to clock in, and an open shift keeps its pause and stop controls whatever the flag says.
// See isButtonPunchWithheld's own doc comment.
//
// The screen has a 1-second Timer.periodic for the live clock, disposed the same way as
// timbra_screen_test.dart does (advance fake time, then unmount).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_screen.dart';

// ── No-op stubs (punches never reach an API client) ──────────────────────────

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

/// [smartWorking] is the value the screen reads from `smartWorkingTodayProvider`:
/// `true` approved, `false` explicitly not approved, `null` unknown.
///
/// Pass [liveFlag] instead to drive that value from a provider the test can change mid-flight —
/// the mid-shift revocation case the flag's per-day nature makes possible.
Widget _buildApp(
  AppDatabase db, {
  required String clockInMethod,
  bool? smartWorking,
  ProviderListenable<bool?>? liveFlag,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      timbraSyncServiceProvider.overrideWithValue(_makeNoopSyncService()),
      // Real LocationService touches platform channels (Geolocator) that no widget test here
      // mocks, and PunchNotifier calls it on every punch/pause.
      locationServiceProvider.overrideWithValue(const DisabledLocationService()),
      effectiveClockInMethodProvider.overrideWithValue(clockInMethod),
      if (liveFlag == null)
        smartWorkingTodayProvider.overrideWithValue(smartWorking)
      else
        smartWorkingTodayProvider.overrideWith((ref) => ref.watch(liveFlag)),
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

  const chipSemantics = 'Giornata di smart working approvata';

  group('QrOnly', () {
    testWidgets('qrOnly_withUnknownFlag_stillShowsThePunchButton', (tester) async {
      // The core inversion. A tenant that requires QR would normally hide the button punch
      // outright; an unknown smart-working flag must not be read as "not approved", because a
      // stale false would strand the technician the feature exists for.
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: null));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsOneWidget);
      expect(find.text('La tua azienda richiede la timbratura con QR.'), findsNothing);
      // Unknown must not claim an approved day either.
      expect(find.text('Smart working'), findsNothing);

      await _teardownTimer(tester);
    });

    testWidgets('qrOnly_withFlagFalse_hidesThePunchButton', (tester) async {
      // Only an explicit false may hide it — the pre-existing behaviour, now conditional.
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsNothing);
      expect(find.text('FINE TURNO'), findsNothing);
      expect(find.text('La tua azienda richiede la timbratura con QR.'), findsOneWidget);
      expect(find.text('Scansiona QR'), findsOneWidget);
      expect(find.text('Smart working'), findsNothing);

      await _teardownTimer(tester);
    });

    testWidgets('qrOnly_withFlagTrue_showsThePunchButtonAndTheChip', (tester) async {
      // An approved remote day: the button punch is legitimate today, so it comes back even
      // though the tenant requires QR — and the chip says why.
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsOneWidget);
      expect(find.text('La tua azienda richiede la timbratura con QR.'), findsNothing);
      expect(find.text('Smart working'), findsOneWidget);
      expect(find.bySemanticsLabel(chipSemantics), findsOneWidget);

      await _teardownTimer(tester);
    });
  });

  group('Both', () {
    testWidgets('bothMethod_withFlagTrue_showsTheChip', (tester) async {
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'Both', smartWorking: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsOneWidget);
      expect(find.text('Smart working'), findsOneWidget);
      expect(find.bySemanticsLabel(chipSemantics), findsOneWidget);

      await _teardownTimer(tester);
    });

    testWidgets('bothMethod_withUnknownFlag_showsNoChip', (tester) async {
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'Both', smartWorking: null));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsOneWidget);
      expect(find.text('Smart working'), findsNothing);
      expect(find.bySemanticsLabel(chipSemantics), findsNothing);

      await _teardownTimer(tester);
    });
  });

  group('an open shift is never left unendable', () {
    testWidgets(
      'qrOnly_approvalRevokedMidShift_keepsTheEndAndPauseControlsAndOffersTheQr',
      (tester) async {
        // The flag is per-day and re-read on every resume, so it can flip under a technician's
        // hands: the office revokes the approval, or a night shift crosses the business-day
        // rollover. The punch button is the same control that ends the shift, so the rule may only
        // ever remove a way to START work — never a way to finish it.
        final liveFlag = StateProvider<bool?>((ref) => null);
        await tester.pumpWidget(
          _buildApp(db, clockInMethod: 'QrOnly', liveFlag: liveFlag),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Unknown keeps the button, which is how the shift gets started here.
        await tester.tap(find.text('INIZIA TURNO'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('FINE TURNO'), findsOneWidget);
        expect(find.text('PAUSA'), findsOneWidget);

        // The approval is withdrawn while the shift runs.
        final container = ProviderScope.containerOf(tester.element(find.byType(TimbraScreen)));
        container.read(liveFlag.notifier).state = false;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text('FINE TURNO'),
          findsOneWidget,
          reason: 'an open shift must still be endable',
        );
        expect(find.text('PAUSA'), findsOneWidget, reason: 'and still breakable');
        expect(
          find.text('La tua azienda richiede la timbratura con QR.'),
          findsNothing,
          reason: 'the start-only notice must not replace a finish control',
        );
        expect(find.text('Smart working'), findsNothing);

        // The one refusal the button cannot resolve — the row day's approval was cancelled — has to
        // stay reachable, or this shift can only be closed from the tracker row on Home.
        expect(find.text('Scansiona QR'), findsOneWidget);
        expect(find.textContaining('chiudi la giornata con il QR'), findsOneWidget);

        await _teardownTimer(tester);
      },
    );

    testWidgets('qrOnly_openShiftOnAnApprovedDay_offersNoScanAction', (tester) async {
      // Nothing to fall back to: the day is approved, so the button is legal on its own.
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: true));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('FINE TURNO'), findsOneWidget);
      expect(find.text('PAUSA'), findsOneWidget);
      expect(find.text('Scansiona QR'), findsNothing);

      await _teardownTimer(tester);
    });

    testWidgets('nonQrOnly_openShift_keepsTheSingleControl', (tester) async {
      // The fallback is a QrOnly affordance; a tenant that accepts button punches sees only the
      // controls it had before.
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'Both', smartWorking: null));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('INIZIA TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('FINE TURNO'), findsOneWidget);
      expect(find.text('PAUSA'), findsOneWidget);
      expect(find.text('Scansiona QR'), findsNothing);

      await _teardownTimer(tester);
    });

    testWidgets('qrOnly_shiftOpenedBeforeMidnight_keepsTheFinishControlAndEndsIt', (tester) async {
      // The business-day rollover is what the day-scoped `timbraStateProvider` cannot cross: a
      // shift punched at 22:00 is in yesterday's window, so at 00:01 it reads as "no shift". The
      // flag must not turn that into "no way to finish" — the server's own gate accepts a
      // ButtonOnly end-of-shift punch when the ROW's WorkDate was approved, which is exactly the
      // night shift this covers. Two days back is used, not "yesterday", so this test cannot rot
      // at the Rome midnight it is about.
      await WorkSessionRepository(db).addEvent(
        id: 'night-opener',
        eventTime: DateTime.now().toUtc().subtract(const Duration(days: 2)),
        eventType: 'ingresso',
      );

      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsNothing, reason: 'a shift IS open, yesterday or not');
      expect(
        find.text('FINE TURNO'),
        findsOneWidget,
        reason: 'an open shift keeps the control that finishes it, past midnight too',
      );
      expect(
        find.text('La tua azienda richiede la timbratura con QR.'),
        findsNothing,
        reason: 'the start-only notice must not replace a finish control',
      );
      // And the scanner stays reachable beside it — the one refusal the two-day rule cannot
      // resolve is a cancelled approval on the row's own day.
      expect(find.text('Scansiona QR'), findsOneWidget);

      await tester.tap(find.text('FINE TURNO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The tap ended the shift instead of attempting a ClockIn and 409ing against the open row.
      final rows = await (db.select(db.workSessions)
            ..orderBy([(s) => OrderingTerm.asc(s.eventTime), (s) => OrderingTerm.asc(s.id)]))
          .get();
      expect(rows.map((r) => r.eventType), ['ingresso', 'fine']);
      // With nothing open any more the flag is back to removing only a way to START — the tenant's
      // own rule, not a finish control stuck on screen.
      expect(find.text('La tua azienda richiede la timbratura con QR.'), findsOneWidget);
      expect(find.text('FINE TURNO'), findsNothing);

      await _teardownTimer(tester);
    });

    testWidgets('qrOnly_withFlagFalseAndNoShift_stillHidesTheStart', (tester) async {
      // The other half of the same rule: with nothing open, the flag removes only a way to start,
      // which is exactly what the tenant asked for.
      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INIZIA TURNO'), findsNothing);
      expect(find.text('La tua azienda richiede la timbratura con QR.'), findsOneWidget);

      await _teardownTimer(tester);
    });
  });

  group('layout', () {
    testWidgets('the chip renders in the fixed layout on a tall phone, with no overflow', (
      tester,
    ) async {
      // The five flag tests above all run at the default 800×600, where the screen always takes
      // its scrolling fallback. This pins the chip's own height in the branch that has a pixel
      // budget — 390×844 is the tall-phone case timbra_screen_test.dart uses.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(db, clockInMethod: 'Both', smartWorking: true));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Smart working'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('INIZIA TURNO'), matching: find.byType(SingleChildScrollView)),
        findsNothing,
        reason: 'the chip still fits inside _kFixedLayoutMinHeight on a tall phone',
      );
      expect(tester.takeException(), isNull);

      await _teardownTimer(tester);
    });

    testWidgets('an open shift plus the qr fallback still fit the fixed layout on a tall phone', (
      tester,
    ) async {
      // The tallest arrangement this task can draw: punch + pause + the scanner fallback, which
      // the budget comment in timbra_screen.dart counts at ≈252dp of controls. Same 390×844 as the
      // test above, so the fixed branch is the branch under test rather than the scrolling one.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkSessionRepository(db).addEvent(
        id: 'seed-ingresso',
        eventTime: DateTime.now().toUtc(),
        eventType: 'ingresso',
      );

      await tester.pumpWidget(_buildApp(db, clockInMethod: 'QrOnly', smartWorking: false));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('FINE TURNO'), findsOneWidget);
      expect(find.text('PAUSA'), findsOneWidget);
      expect(find.text('Scansiona QR'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('FINE TURNO'), matching: find.byType(SingleChildScrollView)),
        findsNothing,
        reason: 'the fallback still fits inside _kFixedLayoutMinHeight on a tall phone',
      );
      expect(tester.takeException(), isNull);

      await _teardownTimer(tester);
    });
  });
}
