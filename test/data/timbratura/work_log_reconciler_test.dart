// Unit tests for WorkLogReconciler.
//
// The bug: a technician clocks in on mobile, then the same account clocks out via another
// surface (web). Mobile's local Drift `work_sessions` table never learns about it, so
// `timbraStateProvider` (purely local-derived) shows "on shift" forever.
//
// WorkLogReconciler closes that gap: it compares the server's authoritative view
// (GET /api/worklog/today, wrapped as [ServerWorkLogSnapshot]) against local state, and when the
// server says the shift is over but local still thinks it is open, appends a local 'fine' event
// so `timbraStateProvider` converges — and marks the stale opener so `TimbraSyncService` never
// resends it (see timbra_sync_service_test.dart for the resurrection-guard side of this).
//
// A second, symmetric bug: a technician clocks in via another surface (web) or reinstalls the
// app. Mobile's local table has NO record of the shift at all, so `timbraStateProvider` shows
// "off shift" / stale data even though the server has an active worklog.
//
// Verifies:
// - reconcileWith: local open + server closed → local corrected (fine appended, opener marked)
// - reconcileWith: local open + server still open → no-op (don't invent a close)
// - reconcileWith: local closed + server closed → no-op (already agrees)
// - reconcileWith: local unaware + server open with a start time → local corrected (ingresso
//   backfilled at the server's start time, marked orphaned so it's never resent)
// - reconcileWith: local unaware + server open with NO start time → no-op (never guess a time)
// - Idempotency: reconcileWith called N times converges, does not duplicate/toggle, in either
//   direction
// - reconcile(): network variant swallows errors (offline is not a crash)
// - reconcile(): network variant applies the same correction as reconcileWith on success, in
//   either direction

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart' show deriveShiftState;

// ── Fake repo ─────────────────────────────────────────────────────────────────
// In-memory list, mutated the same way the real Drift-backed repo would be.

class _FakeRepo implements IWorkSessionRepository {
  @override
  Future<void> markSyncFailed(String id) async {}

  final List<WorkSession> sessions;
  final List<String> orphanedIds = [];

  _FakeRepo(this.sessions);

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
    double? gpsAccuracyMeters,
  }) async {
    sessions.add(WorkSession(id: id, eventTime: eventTime, eventType: eventType, isPendingSync: true));
  }

  @override
  Stream<List<WorkSession>> watchTodaySessions() => Stream.value(sessions);

  @override
  Future<List<WorkSession>> getTodaySessions() async => List.of(sessions);

  @override
  Future<void> markSynced(List<String> ids) async {}

  @override
  Future<void> clearToday() async {}

  @override
  Future<void> markReconciledOrphan(String id) async {
    orphanedIds.add(id);
    final idx = sessions.indexWhere((s) => s.id == id);
    if (idx != -1) {
      sessions[idx] = WorkSession(
        id: sessions[idx].id,
        eventTime: sessions[idx].eventTime,
        eventType: sessions[idx].eventType,
        notes: reconciledOrphanMarker,
        isPendingSync: sessions[idx].isPendingSync,
      );
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// A synced local event (the default: a punch this device already pushed). Pending events are the
/// offline-punch case — see work_log_reconciler_active_test.dart.
WorkSession _ws(String id, String type, DateTime time, {String? notes}) =>
    WorkSession(id: id, eventType: type, eventTime: time, notes: notes, isPendingSync: false);

Future<List<ActiveTracker>> _noTrackers() async => const [];

void main() {
  group('WorkLogReconciler.reconcileWith', () {
    test('local open shift + server closed → appends fine and marks opener orphaned', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false));

      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 2);
      expect(sessions.last.eventType, 'fine');
      expect(deriveShiftState(sessions).isOnShift, isFalse);
      expect(repo.orphanedIds, ['open-1', sessions.last.id]); // the opener, then our own marked 'fine'
    });

    test('local open shift + server still Working → no-op', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: true, isOnPause: false));

      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 1);
      expect(repo.orphanedIds, isEmpty);
    });

    test('local already closed + server closed → no-op (already agrees)', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final t2 = DateTime.utc(2026, 8, 24, 17);
      final repo = _FakeRepo([_ws('1', 'ingresso', t1), _ws('2', 'fine', t2)]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false));

      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 2);
      expect(repo.orphanedIds, isEmpty);
    });

    test('local never punched in + server closed → no-op', () async {
      final repo = _FakeRepo([]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false));

      expect(await repo.getTodaySessions(), isEmpty);
    });

    test(
      'local never punched in + server on shift with a start time → backfills ingresso, marked orphaned',
      () async {
        // Relative to now: a start before local midnight is (deliberately) clamped to midnight.
        final serverStart = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
        final repo = _FakeRepo([]);
        final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

        await reconciler.reconcileWith(
          ServerWorkLogSnapshot(isOnShift: true, isOnPause: false, activeStartTime: serverStart),
        );

        final sessions = await repo.getTodaySessions();
        expect(sessions.length, 1);
        expect(sessions.single.eventType, 'ingresso');
        expect(sessions.single.eventTime, serverStart);
        expect(deriveShiftState(sessions).isOnShift, isTrue);
        expect(repo.orphanedIds, [sessions.single.id]);
      },
    );

    test('local never punched in + server on shift but NO start time available → no-op', () async {
      final repo = _FakeRepo([]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: true, isOnPause: false));

      expect(await repo.getTodaySessions(), isEmpty);
      expect(repo.orphanedIds, isEmpty);
    });

    test(
      'idempotent: backfill correction run 3 times converges, no duplicate ingresso rows',
      () async {
        // Relative to now: a start before local midnight is (deliberately) clamped to midnight.
        final serverStart = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
        final repo = _FakeRepo([]);
        final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);
        final snapshot = ServerWorkLogSnapshot(
          isOnShift: true,
          isOnPause: false,
          activeStartTime: serverStart,
        );

        await reconciler.reconcileWith(snapshot);
        await reconciler.reconcileWith(snapshot);
        await reconciler.reconcileWith(snapshot);

        final sessions = await repo.getTodaySessions();
        expect(sessions.length, 1);
        expect(repo.orphanedIds.length, 1);
      },
    );

    test('idempotent: running the same correction 3 times converges, no duplicate rows', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);
      const snapshot = ServerWorkLogSnapshot(isOnShift: false, isOnPause: false);

      await reconciler.reconcileWith(snapshot);
      await reconciler.reconcileWith(snapshot);
      await reconciler.reconcileWith(snapshot);

      final sessions = await repo.getTodaySessions();
      // Exactly one correction: the original ingresso plus a single synthetic fine — not three.
      expect(sessions.length, 2);
      expect(sessions.where((s) => s.eventType == 'fine').length, 1);
      expect(repo.orphanedIds, ['open-1', sessions.last.id]); // the opener, then our own marked 'fine'
      expect(deriveShiftState(sessions).isOnShift, isFalse);
    });
  });

  group('WorkLogReconciler.reconcile (network variant)', () {
    test('applies the same correction as reconcileWith on a successful fetch', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, fetchActive: _noTrackers);

      await reconciler.reconcile();

      final sessions = await repo.getTodaySessions();
      expect(deriveShiftState(sessions).isOnShift, isFalse);
      expect(repo.orphanedIds, ['open-1', sessions.last.id]); // the opener, then our own marked 'fine'
    });

    test('backfills from the attendance row of /worklog/active', () async {
      // Relative to now: a start before local midnight is (deliberately) clamped to midnight.
        final serverStart = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      final repo = _FakeRepo([]);
      final reconciler = WorkLogReconciler(
        repo: repo,
        fetchActive: () async => [
          ActiveTracker(
            kind: ActiveTrackerKind.attendance,
            id: 'wl-1',
            startedAtUtc: serverStart,
            state: ActiveTrackerState.working,
            shiftStartedAtUtc: serverStart,
          ),
        ],
      );

      await reconciler.reconcile();

      final sessions = await repo.getTodaySessions();
      expect(deriveShiftState(sessions).isOnShift, isTrue);
      expect(sessions.single.eventTime, serverStart);
      expect(repo.orphanedIds, [sessions.single.id]);
    });

    test('network error is swallowed — offline is normal, not a crash', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(
        repo: repo,
        fetchActive: () async => throw DioException(requestOptions: RequestOptions()),
      );

      await expectLater(reconciler.reconcile(), completes);

      // Local state left untouched — no correction can be made without a server answer.
      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 1);
      expect(repo.orphanedIds, isEmpty);
    });
  });
}
