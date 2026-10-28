// Widget tests for the smart-working chip and the fail-open punch button on TimbraScreen.
//
// Uses in-memory Drift + Riverpod overrides; no network.
//
// The rule these tests pin is the inversion the feature exists for: only an explicit `false` may
// hide the punch button. `null` (unknown — cold start, signed out, another user, or before
// /auth/me answers) must never take the control away from a technician who is standing on site
// needing to clock in. See smartWorkingTodayProvider's own doc comment.
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
Widget _buildApp(
  AppDatabase db, {
  required String clockInMethod,
  required bool? smartWorking,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      timbraSyncServiceProvider.overrideWithValue(_makeNoopSyncService()),
      // Real LocationService touches platform channels (Geolocator) that no widget test here
      // mocks, and PunchNotifier calls it on every punch/pause.
      locationServiceProvider.overrideWithValue(const DisabledLocationService()),
      effectiveClockInMethodProvider.overrideWithValue(clockInMethod),
      smartWorkingTodayProvider.overrideWithValue(smartWorking),
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
}
