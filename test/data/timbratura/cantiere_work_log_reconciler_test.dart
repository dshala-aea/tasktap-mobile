// Unit tests for CantiereWorkLogReconciler. Mirrors work_log_reconciler_test.dart's coverage for
// the cantiere (worksite) session instead of personal attendance.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_assembler.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';

// ── Fake repo ─────────────────────────────────────────────────────────────────

class _FakeRepo implements ICantiereSessionRepository {
  final List<CantierePunche> events;
  final List<String> orphanedIds = [];
  final List<String> addedEventTypes = [];

  _FakeRepo(this.events);

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    String? cantiereId,
    String? customerId,
    String? ticketId,
    String? description,
    double? latitude,
    double? longitude,
    String? safetyNotes,
    double? departureLatitude,
    double? departureLongitude,
    String? workOrderNumber,
    String? equipmentUsed,
    int? teamSize,
    String? weatherConditions,
  }) async {
    addedEventTypes.add(eventType);
    events.add(
      CantierePunche(id: id, eventTime: eventTime, eventType: eventType, isPendingSync: true),
    );
  }

  @override
  Stream<List<CantierePunche>> watchTodayEvents() => Stream.value(events);

  /// The screen's "is a session open" read — the latest punch of the whole log, not of today.
  @override
  Stream<CantierePunche?> watchLatestPunch() =>
      Stream.value(events.isEmpty ? null : events.last);

  @override
  Future<List<CantierePunche>> getTodayEvents() async => List.of(events);

  @override
  Future<List<CantierePunche>> getPendingEvents() async =>
      events.where((e) => e.isPendingSync).toList();

  // Not exercised here (the reconciler never asks); implemented off the same assembler the real
  // repository uses so the fake stays a faithful stand-in for the interface.
  @override
  Future<List<CantiereWorkInterval>> getClosedIntervalsFor(String cantiereId) async => [
    for (final i in assembleCantiereIntervals(events))
      if (i.cantiereId == cantiereId && i.endTime != null) i,
  ];

  @override
  Future<List<String>> getClosedIntervalClientIds(String cantiereId) async =>
      [for (final i in await getClosedIntervalsFor(cantiereId)) i.clientId];

  @override
  Future<int> getPendingCount() async =>
      events.where((e) => e.isPendingSync && e.notes != cantiereReconciledOrphanMarker).length;

  @override
  Future<void> markSynced(List<String> ids) async {}

  @override
  Future<void> markSyncError(String id, String? message) async {}

  @override
  Future<void> markReconciledOrphan(String id) async {
    orphanedIds.add(id);
    final idx = events.indexWhere((e) => e.id == id);
    if (idx != -1) {
      events[idx] = CantierePunche(
        id: events[idx].id,
        eventTime: events[idx].eventTime,
        eventType: events[idx].eventType,
        cantiereId: events[idx].cantiereId,
        customerId: events[idx].customerId,
        notes: cantiereReconciledOrphanMarker,
        isPendingSync: events[idx].isPendingSync,
      );
    }
  }

  @override
  Future<void> clearToday() async {}
}

// ── Fake API client ───────────────────────────────────────────────────────────

class _FakeApiClient extends CantiereWorklogApiClient {
  _FakeApiClient() : super(Dio());

  List<CantiereWorkLogDto> activeToReturn = const [];
  Object? errorToThrow;
  int getActiveCalls = 0;

  @override
  Future<List<CantiereWorkLogDto>> getActive() async {
    getActiveCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return activeToReturn;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CantierePunche _cp(
  String id,
  String type,
  DateTime time, {
  String? cantiereId,
  bool isPendingSync = false,
  String? notes,
}) => CantierePunche(
  id: id,
  eventType: type,
  eventTime: time,
  isPendingSync: isPendingSync,
  cantiereId: cantiereId,
  notes: notes,
);

CantiereWorkLogDto _activeLog() => CantiereWorkLogDto(
  id: 'log-1',
  cantiereId: 'cant-1',
  customerId: 'cust-1',
  workDate: DateTime.utc(2026, 8, 24),
  startTime: '08:00:00',
);

void main() {
  group('CantiereWorkLogReconciler.reconcileWith', () {
    test('local open visit + server has no active session → appends uscita, marks opener', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      final events = await repo.getTodayEvents();
      expect(events.length, 2);
      expect(events.last.eventType, 'uscita');
      // The opener AND the correction it appended, so the sync pushes neither.
      expect(repo.orphanedIds.first, 'open-1');
      expect(repo.orphanedIds.length, 2);
    });

    test('local open visit + server still has an active session → no-op', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: true);

      final events = await repo.getTodayEvents();
      expect(events.length, 1);
      expect(repo.orphanedIds, isEmpty);
    });

    test('local already closed + server has no active session → no-op (already agrees)', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final t2 = DateTime.utc(2026, 8, 24, 17);
      final repo = _FakeRepo([
        _cp('1', 'ingresso', t1, cantiereId: 'cant-1'),
        _cp('2', 'uscita', t2),
      ]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      final events = await repo.getTodayEvents();
      expect(events.length, 2);
      expect(repo.orphanedIds, isEmpty);
    });

    test('local never checked in + server has no active session → no-op', () async {
      final repo = _FakeRepo([]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      expect(await repo.getTodayEvents(), isEmpty);
    });

    test('idempotent: running the same correction 3 times converges, no duplicate rows', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);
      await reconciler.reconcileWith(serverHasActiveSession: false);
      await reconciler.reconcileWith(serverHasActiveSession: false);

      final events = await repo.getTodayEvents();
      expect(events.length, 2);
      expect(events.where((e) => e.eventType == 'uscita').length, 1);
      // The opener AND the correction it appended, so the sync pushes neither.
      expect(repo.orphanedIds.first, 'open-1');
      expect(repo.orphanedIds.length, 2);
    });

    test('the appended uscita is marked too, so it cannot freeze the unsynced guard', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      final uscita = (await repo.getTodayEvents()).firstWhere((e) => e.eventType == 'uscita');
      expect(uscita.notes, cantiereReconciledOrphanMarker);
      // ... and it is not counted as unsent work that a sync would clear.
      expect(await repo.getPendingCount(), 0);
    });

    // F3: a clock-in still waiting to be pushed must never be orphan-marked. The server has no
    // active session precisely because the punch has not arrived yet — "correcting" here would
    // mark the technician's own check-in and the sync would then filter it out: the punch is lost.
    test('a PENDING opener + server with no active session → no-op (local unsynced wins)', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([
        _cp('open-1', 'ingresso', t1, cantiereId: 'cant-1', isPendingSync: true),
      ]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      final events = await repo.getTodayEvents();
      expect(events.length, 1, reason: 'no uscita appended over an unsent clock-in');
      expect(events.single.notes, isNot(cantiereReconciledOrphanMarker));
      expect(repo.orphanedIds, isEmpty);
    });

    test('a pending non-opener event also holds the correction off', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([
        _cp('open-1', 'ingresso', t1, cantiereId: 'cant-1'),
        _cp('gone-1', 'uscita', t1.add(const Duration(hours: 1)), isPendingSync: true),
      ]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      expect((await repo.getTodayEvents()).length, 2);
      expect(repo.orphanedIds, isEmpty);
    });

    test('a marked correction does not hold the correction off forever', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([
        // The reconciler's own output: pending by construction, never pushed, never a reason to
        // stop reconciling.
        _cp(
          'marker-1',
          'ingresso',
          t1,
          cantiereId: 'cant-1',
          isPendingSync: true,
          notes: cantiereReconciledOrphanMarker,
        ),
      ]);
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: _FakeApiClient());

      await reconciler.reconcileWith(serverHasActiveSession: false);

      expect(repo.orphanedIds.first, 'marker-1');
      expect((await repo.getTodayEvents()).length, 2);
    });
  });

  group('CantiereWorkLogReconciler.reconcile (network variant)', () {
    test('applies the same correction as reconcileWith on a successful fetch', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final api = _FakeApiClient()..activeToReturn = const [];
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: api);

      await reconciler.reconcile();

      final events = await repo.getTodayEvents();
      expect(events.last.eventType, 'uscita');
      // The opener AND the correction it appended, so the sync pushes neither.
      expect(repo.orphanedIds.first, 'open-1');
      expect(repo.orphanedIds.length, 2);
    });

    test('server still reports an active session → no correction', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final api = _FakeApiClient()..activeToReturn = [_activeLog()];
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: api);

      await reconciler.reconcile();

      expect(repo.orphanedIds, isEmpty);
    });

    test('network error is swallowed — offline is normal, not a crash', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final repo = _FakeRepo([_cp('open-1', 'ingresso', t1, cantiereId: 'cant-1')]);
      final api = _FakeApiClient()..errorToThrow = DioException(requestOptions: RequestOptions());
      final reconciler = CantiereWorkLogReconciler(repo: repo, apiClient: api);

      await expectLater(reconciler.reconcile(), completes);

      final events = await repo.getTodayEvents();
      expect(events.length, 1);
      expect(repo.orphanedIds, isEmpty);
    });
  });
}
