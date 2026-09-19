// Unit tests for CantiereWorkLogReconciler. Mirrors work_log_reconciler_test.dart's coverage for
// the cantiere (worksite) session instead of personal attendance.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
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
  }) async {
    addedEventTypes.add(eventType);
    events.add(
      CantierePunche(id: id, eventTime: eventTime, eventType: eventType, isPendingSync: true),
    );
  }

  @override
  Stream<List<CantierePunche>> watchTodayEvents() => Stream.value(events);

  @override
  Future<List<CantierePunche>> getTodayEvents() async => List.of(events);

  @override
  Future<void> markSynced(List<String> ids) async {}

  @override
  Future<void> markSyncError(String id, String message) async {}

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

CantierePunche _cp(String id, String type, DateTime time, {String? cantiereId}) => CantierePunche(
  id: id,
  eventType: type,
  eventTime: time,
  isPendingSync: true,
  cantiereId: cantiereId,
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
      expect(repo.orphanedIds, ['open-1']);
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
      expect(repo.orphanedIds, ['open-1']);
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
      expect(repo.orphanedIds, ['open-1']);
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
