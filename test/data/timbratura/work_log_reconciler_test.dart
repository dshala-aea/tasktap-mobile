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
// Verifies:
// - reconcileWith: local open + server closed → local corrected (fine appended, opener marked)
// - reconcileWith: local open + server still open → no-op (don't invent a close)
// - reconcileWith: local closed + server closed → no-op (already agrees)
// - Idempotency: reconcileWith called N times converges, does not duplicate/toggle
// - reconcile(): network variant swallows errors (offline is not a crash)
// - reconcile(): network variant applies the same correction as reconcileWith on success

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart' show deriveShiftState;

// ── Fake repo ─────────────────────────────────────────────────────────────────
// In-memory list, mutated the same way the real Drift-backed repo would be.

class _FakeRepo implements IWorkSessionRepository {
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

// ── Fake API client ───────────────────────────────────────────────────────────

class _FakeApiClient extends WorklogApiClient {
  _FakeApiClient() : super(Dio());

  GiornataDto? giornataToReturn;
  Object? errorToThrow;
  int getGiornataCalls = 0;

  @override
  Future<GiornataDto> getGiornata() async {
    getGiornataCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return giornataToReturn!;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

WorkSession _ws(String id, String type, DateTime time, {String? notes}) =>
    WorkSession(id: id, eventType: type, eventTime: time, notes: notes, isPendingSync: true);

GiornataDto _giornata(String status) => GiornataDto(
  status: status,
  workedMinutes: 0,
  breakMinutes: 0,
  isPayrollLocked: false,
  actions: const [],
);

void main() {
  group('ServerWorkLogSnapshot.fromGiornata', () {
    test('ClockedOut → not on shift, not on pause', () {
      final snap = ServerWorkLogSnapshot.fromGiornata(_giornata('ClockedOut'));
      expect(snap.isOnShift, isFalse);
      expect(snap.isOnPause, isFalse);
    });

    test('Working → on shift, not on pause', () {
      final snap = ServerWorkLogSnapshot.fromGiornata(_giornata('Working'));
      expect(snap.isOnShift, isTrue);
      expect(snap.isOnPause, isFalse);
    });

    test('OnBreak → on shift and on pause', () {
      final snap = ServerWorkLogSnapshot.fromGiornata(_giornata('OnBreak'));
      expect(snap.isOnShift, isTrue);
      expect(snap.isOnPause, isTrue);
    });
  });

  group('WorkLogReconciler.reconcileWith', () {
    test('local open shift + server closed → appends fine and marks opener orphaned', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false));

      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 2);
      expect(sessions.last.eventType, 'fine');
      expect(deriveShiftState(sessions).isOnShift, isFalse);
      expect(repo.orphanedIds, ['open-1']);
    });

    test('local open shift + server still Working → no-op', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: true, isOnPause: false));

      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 1);
      expect(repo.orphanedIds, isEmpty);
    });

    test('local already closed + server closed → no-op (already agrees)', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final t2 = DateTime.utc(2026, 8, 24, 17);
      final repo = _FakeRepo([_ws('1', 'ingresso', t1), _ws('2', 'fine', t2)]);
      final reconciler = WorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false));

      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 2);
      expect(repo.orphanedIds, isEmpty);
    });

    test('local never punched in + server closed → no-op', () async {
      final repo = _FakeRepo([]);
      final reconciler = WorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false));

      expect(await repo.getTodaySessions(), isEmpty);
    });

    test('idempotent: running the same correction 3 times converges, no duplicate rows', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final reconciler = WorkLogReconciler(repo: repo, apiClient: _FakeApiClient());
      const snapshot = ServerWorkLogSnapshot(isOnShift: false, isOnPause: false);

      await reconciler.reconcileWith(snapshot);
      await reconciler.reconcileWith(snapshot);
      await reconciler.reconcileWith(snapshot);

      final sessions = await repo.getTodaySessions();
      // Exactly one correction: the original ingresso plus a single synthetic fine — not three.
      expect(sessions.length, 2);
      expect(sessions.where((s) => s.eventType == 'fine').length, 1);
      expect(repo.orphanedIds, ['open-1']);
      expect(deriveShiftState(sessions).isOnShift, isFalse);
    });
  });

  group('WorkLogReconciler.reconcile (network variant)', () {
    test('applies the same correction as reconcileWith on a successful fetch', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final api = _FakeApiClient()..giornataToReturn = _giornata('ClockedOut');
      final reconciler = WorkLogReconciler(repo: repo, apiClient: api);

      await reconciler.reconcile();

      final sessions = await repo.getTodaySessions();
      expect(deriveShiftState(sessions).isOnShift, isFalse);
      expect(repo.orphanedIds, ['open-1']);
    });

    test('network error is swallowed — offline is normal, not a crash', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_ws('open-1', 'ingresso', t1)]);
      final api = _FakeApiClient()..errorToThrow = DioException(requestOptions: RequestOptions());
      final reconciler = WorkLogReconciler(repo: repo, apiClient: api);

      await expectLater(reconciler.reconcile(), completes);

      // Local state left untouched — no correction can be made without a server answer.
      final sessions = await repo.getTodaySessions();
      expect(sessions.length, 1);
      expect(repo.orphanedIds, isEmpty);
    });
  });
}
