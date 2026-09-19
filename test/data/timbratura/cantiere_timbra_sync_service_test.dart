// Unit tests for CantiereTimbraSyncService. Mirrors timbra_sync_service_test.dart's coverage.
//
// Uses fakes for ICantiereSessionRepository and CantiereWorklogApiClient. No network calls.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';

// ── Fake repo ─────────────────────────────────────────────────────────────────

class _FakeRepo implements ICantiereSessionRepository {
  final List<CantierePunche> events;
  final List<String> markedSynced = [];

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
  }) async {}

  @override
  Stream<List<CantierePunche>> watchTodayEvents() => Stream.value(events);

  @override
  Future<List<CantierePunche>> getTodayEvents() async => events;

  @override
  Future<void> markSynced(List<String> ids) async {
    markedSynced.addAll(ids);
  }

  @override
  Future<void> markSyncError(String id, String message) async {}

  @override
  Future<void> markReconciledOrphan(String id) async {}

  @override
  Future<void> clearToday() async {}
}

// ── Fake API client ───────────────────────────────────────────────────────────

class _FakeApiClient extends CantiereWorklogApiClient {
  _FakeApiClient() : super(Dio());

  final List<List<CantiereMobileSessionDto>> calls = [];
  bool shouldThrow = false;

  @override
  Future<List<CantiereMobileSessionResult>> upsertSessions(
    List<CantiereMobileSessionDto> sessions,
  ) async {
    if (shouldThrow) throw Exception('Network error');
    calls.add(List.of(sessions));
    return sessions
        .map(
          (s) => CantiereMobileSessionResult(
            clientId: s.clientId,
            cantiereWorkLogId: 'wl-${s.clientId}',
            startTime: s.startTime,
            endTime: s.endTime,
            isActive: s.endTime == null,
          ),
        )
        .toList();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CantierePunche _cp(
  String id,
  String type,
  DateTime time, {
  String? cantiereId,
  String? customerId,
  String? ticketId,
  String? notes,
}) => CantierePunche(
  id: id,
  eventType: type,
  eventTime: time,
  isPendingSync: true,
  cantiereId: cantiereId,
  customerId: customerId,
  ticketId: ticketId,
  notes: notes,
);

void main() {
  group('CantiereTimbraSyncService.syncNow', () {
    test('no events → no API call', () async {
      final repo = _FakeRepo([]);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls, isEmpty);
      expect(repo.markedSynced, isEmpty);
    });

    test('ingresso → uscita: calls upsertSessions with one interval', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final events = [
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('id-2', 'uscita', t2),
      ];
      final repo = _FakeRepo(events);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls.length, 1);
      final dtos = api.calls[0];
      expect(dtos.length, 1);
      expect(dtos[0].clientId, 'id-1');
      expect(dtos[0].cantiereId, 'cant-1');
      expect(dtos[0].customerId, 'cust-1');
      expect(dtos[0].startTime, t1);
      expect(dtos[0].endTime, t2);
    });

    test('markSynced receives both event ids', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final events = [
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('id-2', 'uscita', t2),
      ];
      final repo = _FakeRepo(events);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(repo.markedSynced, containsAll(['id-1', 'id-2']));
    });

    test('active interval has null endTime in DTO', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final events = [_cp('id-open', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1')];
      final repo = _FakeRepo(events);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls[0][0].endTime, isNull);
    });

    test('API error → swallowed, no rethrow', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final events = [_cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1')];
      final repo = _FakeRepo(events);
      final api = _FakeApiClient()..shouldThrow = true;
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await expectLater(svc.syncNow(), completes);
      expect(repo.markedSynced, isEmpty);
    });

    test('an orphan-marked open interval is never pushed (resurrection guard)', () async {
      final t1 = DateTime.utc(2026, 8, 24, 8);
      final events = [
        _cp(
          'id-1',
          'ingresso',
          t1,
          cantiereId: 'cant-1',
          customerId: 'cust-1',
          notes: cantiereReconciledOrphanMarker,
        ),
      ];
      final repo = _FakeRepo(events);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls, isEmpty);
      expect(repo.markedSynced, isEmpty);
    });
  });
}
