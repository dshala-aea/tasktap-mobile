// Unit tests for TimbraSyncService.
//
// Uses fakes for IWorkSessionRepository and WorklogApiClient.
// No network calls are made; WorklogApiClient is subclassed to override
// the methods that hit Dio.
//
// Verifies:
// - syncNow() with no sessions → no API call
// - syncNow() with sessions → calls upsertSessions + markSynced
// - syncNow() on API error → swallows exception (no rethrow)
// - markSynced receives all event ids (not just opener ids)
// - resurrection guard: an opener WorkLogReconciler has flagged as orphaned (server already
//   closed this interval elsewhere) is excluded from the push, so a stale local "still active"
//   event can never re-open or extend a worklog the server has already closed.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

// ── Fake repo ─────────────────────────────────────────────────────────────────

class _FakeRepo implements IWorkSessionRepository {
  final List<WorkSession> sessions;
  final List<String> markedSynced = [];

  _FakeRepo(this.sessions);

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
  }) async {}

  @override
  Stream<List<WorkSession>> watchTodaySessions() => Stream.value(sessions);

  @override
  Future<List<WorkSession>> getTodaySessions() async => sessions;

  @override
  Future<void> markSynced(List<String> ids) async {
    markedSynced.addAll(ids);
  }

  @override
  Future<void> clearToday() async {}

  @override
  Future<void> markReconciledOrphan(String id) async {}
}

// ── Fake API client ───────────────────────────────────────────────────────────
// Subclasses WorklogApiClient but overrides the two methods so Dio is never used.

class _FakeApiClient extends WorklogApiClient {
  _FakeApiClient() : super(Dio());

  final List<List<MobileSessionDto>> calls = [];
  bool shouldThrow = false;

  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async {
    if (shouldThrow) throw Exception('Network error');
    calls.add(List.of(sessions));
    return sessions
        .map(
          (s) => UpsertSessionResponse(
            clientId: s.clientId,
            workLogId: 'wl-${s.clientId}',
            startTime: s.startTime,
            endTime: s.endTime,
            isActive: s.endTime == null,
          ),
        )
        .toList();
  }

  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

WorkSession _ws(String id, String type, DateTime time, {String? notes}) =>
    WorkSession(id: id, eventType: type, eventTime: time, notes: notes, isPendingSync: true);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('TimbraSyncService.syncNow', () {
    test('no sessions → no API call', () async {
      final repo = _FakeRepo([]);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls, isEmpty);
      expect(repo.markedSynced, isEmpty);
    });

    test('ingresso → fine: calls upsertSessions with one interval', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final sessions = [_ws('id-1', 'ingresso', t1), _ws('id-2', 'fine', t2)];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls.length, 1);
      final dtos = api.calls[0];
      expect(dtos.length, 1);
      expect(dtos[0].clientId, 'id-1');
      expect(dtos[0].startTime, t1);
      expect(dtos[0].endTime, t2);
      expect(dtos[0].latitude, isNull);
      expect(dtos[0].longitude, isNull);
    });

    test('markSynced receives all event ids', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 12);
      final t3 = DateTime.utc(2026, 6, 23, 13);
      final sessions = [
        _ws('id-1', 'ingresso', t1),
        _ws('id-2', 'pausa', t2),
        _ws('id-3', 'ripresa', t3),
      ];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      // All three event ids should be marked synced
      expect(repo.markedSynced, containsAll(['id-1', 'id-2', 'id-3']));
    });

    test('active interval has null endTime in DTO', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final sessions = [_ws('id-open', 'ingresso', t1)];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls[0][0].endTime, isNull);
    });

    test('API error → swallowed, no rethrow', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final sessions = [_ws('id-1', 'ingresso', t1)];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient()..shouldThrow = true;
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      // Must not throw
      await expectLater(svc.syncNow(), completes);
      // markSynced not called on error
      expect(repo.markedSynced, isEmpty);
    });

    test('two-interval session sends two DTOs', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 12);
      final t3 = DateTime.utc(2026, 6, 23, 13);
      final t4 = DateTime.utc(2026, 6, 23, 17);
      final sessions = [
        _ws('id-1', 'ingresso', t1),
        _ws('id-2', 'pausa', t2),
        _ws('id-3', 'ripresa', t3),
        _ws('id-4', 'fine', t4),
      ];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls[0].length, 2);
      expect(api.calls[0][0].clientId, 'id-1');
      expect(api.calls[0][1].clientId, 'id-3');
    });
  });

  group('TimbraSyncService.syncNow — resurrection guard', () {
    test('an orphan-marked open interval is never pushed', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      // A stale open shift the reconciler has already determined the server closed elsewhere.
      final sessions = [_ws('id-1', 'ingresso', t1, notes: reconciledOrphanMarker)];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls, isEmpty);
      expect(repo.markedSynced, isEmpty);
    });

    test(
      'an orphaned opener does not block a later, legitimate shift from syncing',
      () async {
        final t1 = DateTime.utc(2026, 8, 24, 8);
        final t2 = DateTime.utc(2026, 8, 24, 9);
        final t3 = DateTime.utc(2026, 8, 24, 14);
        final sessions = [
          // Stale shift, closed server-side elsewhere and marked orphaned by the reconciler.
          _ws('id-1', 'ingresso', t1, notes: reconciledOrphanMarker),
          // Local correction closing it for display purposes only.
          _ws('id-2', 'fine', t2),
          // A brand-new shift punched in normally afterwards.
          _ws('id-3', 'ingresso', t3),
        ];
        final repo = _FakeRepo(sessions);
        final api = _FakeApiClient();
        final svc = TimbraSyncService(repo: repo, apiClient: api);

        await svc.syncNow();

        expect(api.calls.length, 1);
        final dtos = api.calls[0];
        expect(dtos.length, 1);
        expect(dtos[0].clientId, 'id-3');
        expect(dtos[0].endTime, isNull);
        expect(repo.markedSynced, contains('id-3'));
        expect(repo.markedSynced, isNot(contains('id-1')));
      },
    );

    test('a normal (non-orphaned) open interval is unaffected — still syncs', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final sessions = [_ws('id-1', 'ingresso', t1)];
      final repo = _FakeRepo(sessions);
      final api = _FakeApiClient();
      final svc = TimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls.length, 1);
      expect(api.calls[0][0].clientId, 'id-1');
      expect(repo.markedSynced, contains('id-1'));
    });
  });
}
