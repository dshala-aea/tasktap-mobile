// Integration tests: WorkLogReconciler wired through Riverpod, proving the actual bug this
// change fixes end-to-end — not just the pure reconciler function in isolation.
//
// Bug: technician clocks in on mobile; the same account clocks out via another surface (web).
// Before this fix, `timbraStateProvider` (features/timbra/timbra_providers.dart) derived its
// state purely from the local Drift `work_sessions` table and never learned of the server-side
// stop, so the mobile UI kept showing "on shift" forever.
//
// These tests seed the local Drift DB the same way a real clock-in would, override the worklog
// API client to answer as the server would (ClockedOut), run the reconciler through its provider,
// and assert that both `timbraStateProvider` and the dashboard's `visibleTrackersProvider`
// converge to the server's truth — proving the fix reaches the screens, not just the service.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Waits for `todaySessionsProvider`'s Drift stream to deliver its latest emission.
///
/// `container.read(provider.future)` alone can return an already-cached (pre-write) value
/// immediately rather than waiting for a fresh one — the in-memory NativeDatabase delivers its
/// change notification via the event loop, not synchronously within a single `await`.
/// `pumpEventQueue()` flushes that queue so the assertions below see the write that just
/// happened, matching how a real widget watching this provider would pick it up.
Future<void> _awaitTodaySessions(ProviderContainer container) async {
  await container.read(todaySessionsProvider.future);
  await pumpEventQueue();
  await container.read(todaySessionsProvider.future);
}

class _NoopApiClient extends WorklogApiClient {
  _NoopApiClient() : super(Dio());
  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async => [];
  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];
}

/// Answers GET /api/worklog/today the way the server would once the same-account clock-out
/// on the web has already landed: status ClockedOut, no matter what mobile still has locally.
class _ServerSaysClockedOutClient extends WorklogApiClient {
  _ServerSaysClockedOutClient() : super(Dio());

  @override
  Future<GiornataDto> getGiornata() async => const GiornataDto(
    status: 'ClockedOut',
    workedMinutes: 480,
    breakMinutes: 0,
    isPayrollLocked: false,
    actions: [],
  );

  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async => [];
  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];
}

void main() {
  group('WorkLogReconciler wired through providers', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = _makeDb();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          timbraSyncServiceProvider.overrideWithValue(
            TimbraSyncService(repo: _StubRepoForSync(), apiClient: _NoopApiClient()),
          ),
          worklogApiClientProvider.overrideWithValue(_ServerSaysClockedOutClient()),
          // No other kind of tracker is running server-side for this scenario.
          activeTrackersProvider.overrideWith((ref) => Stream.value(const <ActiveTracker>[])),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
      'timbraStateProvider still shows on-shift before reconciliation runs (reproduces the bug)',
      () async {
        final repo = container.read(workSessionRepositoryProvider);
        await repo.addEvent(
          id: 'mobile-open-shift',
          eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          eventType: 'ingresso',
        );
        await _awaitTodaySessions(container);

        expect(container.read(timbraStateProvider).isOnShift, isTrue);
      },
    );

    test(
      'after reconciliation, timbraStateProvider reflects the server-confirmed clock-out',
      () async {
        final repo = container.read(workSessionRepositoryProvider);
        await repo.addEvent(
          id: 'mobile-open-shift',
          eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          eventType: 'ingresso',
        );
        await _awaitTodaySessions(container);
        expect(container.read(timbraStateProvider).isOnShift, isTrue, reason: 'sanity check');

        await container.read(workLogReconcilerProvider).reconcile();
        await _awaitTodaySessions(container);

        expect(container.read(timbraStateProvider).isOnShift, isFalse);
      },
    );

    test(
      'after reconciliation, the dashboard drops the stale attendance tracker too '
      '(visibleTrackersProvider shares timbraStateProvider as its root)',
      () async {
        final repo = container.read(workSessionRepositoryProvider);
        await repo.addEvent(
          id: 'mobile-open-shift',
          eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          eventType: 'ingresso',
        );
        await _awaitTodaySessions(container);
        expect(
          container.read(visibleTrackersProvider).any((t) => t.kind == ActiveTrackerKind.attendance),
          isTrue,
          reason: 'sanity check: attendance tracker shown while locally still on shift',
        );

        await container.read(workLogReconcilerProvider).reconcile();
        await _awaitTodaySessions(container);

        expect(
          container.read(visibleTrackersProvider).any((t) => t.kind == ActiveTrackerKind.attendance),
          isFalse,
        );
      },
    );

    test('reconciling twice in a row converges — second run is a no-op', () async {
      final repo = container.read(workSessionRepositoryProvider);
      await repo.addEvent(
        id: 'mobile-open-shift',
        eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        eventType: 'ingresso',
      );
      await _awaitTodaySessions(container);

      await container.read(workLogReconcilerProvider).reconcile();
      await _awaitTodaySessions(container);
      final afterFirst = await repo.getTodaySessions();

      await container.read(workLogReconcilerProvider).reconcile();
      await _awaitTodaySessions(container);
      final afterSecond = await repo.getTodaySessions();

      expect(afterSecond.length, afterFirst.length);
      expect(container.read(timbraStateProvider).isOnShift, isFalse);
    });
  });
}

// A pending-sync stub so timbraSyncServiceProvider's override never hits Dio when
// PunchNotifier's fire-and-forget syncNow() call happens to run during these tests.
class _StubRepoForSync implements IWorkSessionRepository {
  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
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
