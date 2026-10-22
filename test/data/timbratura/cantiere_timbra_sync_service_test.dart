// Unit tests for CantiereTimbraSyncService. Mirrors timbra_sync_service_test.dart's coverage.
//
// Uses fakes for ICantiereSessionRepository and CantiereWorklogApiClient. No network calls.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_assembler.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';

// ── Fake repo ─────────────────────────────────────────────────────────────────

class _FakeRepo implements ICantiereSessionRepository {
  final List<CantierePunche> events;

  /// Pending rows that are NOT in [events] — i.e. a backlog from an earlier business day. The real
  /// repository's `getPendingEvents()` is day-agnostic; this models that.
  final List<CantierePunche> pendingBeyondToday;
  final List<String> markedSynced = [];
  final Map<String, String?> syncErrors = {};

  _FakeRepo(this.events, {this.pendingBeyondToday = const []});

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
  }) async {}

  @override
  Stream<List<CantierePunche>> watchTodayEvents() => Stream.value(events);

  /// The screen's "is a session open" read — the latest punch of the whole log. This fake holds
  /// one day's events, so its last row is that punch.
  @override
  Stream<CantierePunche?> watchLatestPunch() =>
      Stream.value(events.isEmpty ? null : events.last);

  @override
  Future<List<CantierePunche>> getTodayEvents() async => events;

  @override
  Future<List<CantierePunche>> getPendingEvents() async =>
      [...events.where((e) => e.isPendingSync), ...pendingBeyondToday];

  // Not exercised by these tests (the sync never asks); implemented off the same assembler the
  // real repository uses so the fake stays a faithful stand-in for the interface.
  @override
  Future<List<CantiereWorkInterval>> getClosedIntervalsFor(String cantiereId) async => [
    for (final i in assembleCantiereIntervals(events))
      if (i.cantiereId == cantiereId && i.endTime != null) i,
  ];

  @override
  Future<List<String>> getClosedIntervalClientIds(String cantiereId) async =>
      [for (final i in await getClosedIntervalsFor(cantiereId)) i.clientId];

  @override
  Future<int> getPendingCount() async => (await getPendingEvents())
      .where((e) => e.notes != cantiereReconciledOrphanMarker)
      .length;

  @override
  Future<void> markSynced(List<String> ids) async {
    markedSynced.addAll(ids);
  }

  @override
  Future<void> markSyncError(String id, String? message) async {
    syncErrors[id] = message;
    final i = events.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final e = events[i];
    events[i] = CantierePunche(
      id: e.id,
      eventTime: e.eventTime,
      eventType: e.eventType,
      cantiereId: e.cantiereId,
      customerId: e.customerId,
      ticketId: e.ticketId,
      description: e.description,
      latitude: e.latitude,
      longitude: e.longitude,
      safetyNotes: e.safetyNotes,
      departureLatitude: e.departureLatitude,
      departureLongitude: e.departureLongitude,
      notes: e.notes,
      isPendingSync: e.isPendingSync,
      syncError: message,
    );
  }

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

  /// When set, [upsertSessions] throws exactly this instead of [shouldThrow]'s generic exception —
  /// for the classification tests, which need a real server answer.
  Object? errorToThrow;

  @override
  Future<List<CantiereMobileSessionResult>> upsertSessions(
    List<CantiereMobileSessionDto> sessions,
  ) async {
    if (errorToThrow != null) throw errorToThrow!;
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
  String? safetyNotes,
  double? departureLatitude,
  double? departureLongitude,
}) => CantierePunche(
  id: id,
  eventType: type,
  eventTime: time,
  isPendingSync: true,
  cantiereId: cantiereId,
  customerId: customerId,
  ticketId: ticketId,
  notes: notes,
  safetyNotes: safetyNotes,
  departureLatitude: departureLatitude,
  departureLongitude: departureLongitude,
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

    /// The clock-out screen's fields must survive the queue. Sending the interval without them
    /// makes an offline clock-out a poorer record than the same visit closed with signal, and the
    /// safety note is the one field on that screen a compliance audit actually asks for.
    test('the clock-out fields ride on the closing DTO', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final events = [
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp(
          'id-2',
          'uscita',
          t2,
          safetyNotes: 'area recintata',
          departureLatitude: 45.4660,
          departureLongitude: 9.1880,
        ),
      ];
      final repo = _FakeRepo(events);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      final dto = api.calls[0][0];
      expect(dto.endTime, t2);
      expect(dto.safetyNotes, 'area recintata');
      expect(dto.departureLatitude, 45.4660);
      expect(dto.departureLongitude, 9.1880);
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

  // ── P0-2: the queue is not day-scoped ───────────────────────────────────────
  group('CantiereTimbraSyncService.syncNow — multi-day backlog', () {
    test('a pending event dated yesterday is assembled and POSTed', () async {
      final start = DateTime.utc(2026, 6, 22, 8);
      final end = DateTime.utc(2026, 6, 22, 17);
      final repo = _FakeRepo(
        [],
        pendingBeyondToday: [
          _cp('y-1', 'ingresso', start, cantiereId: 'cant-1', customerId: 'cust-1'),
          _cp('y-2', 'uscita', end),
        ],
      );
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls.length, 1);
      final dto = api.calls.single.single;
      expect(dto.clientId, 'y-1');
      expect(dto.startTime, start);
      expect(dto.endTime, end);
      expect(repo.markedSynced, containsAll(['y-1', 'y-2']));
    });

    test('a multi-day backlog is assembled and sent one day at a time', () async {
      final day1Start = DateTime.utc(2026, 6, 22, 8);
      final day1End = DateTime.utc(2026, 6, 22, 17);
      final day2Start = DateTime.utc(2026, 6, 23, 9);
      final day2End = DateTime.utc(2026, 6, 23, 18);
      final repo = _FakeRepo([], pendingBeyondToday: [
        _cp('d1-in', 'ingresso', day1Start, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('d1-out', 'uscita', day1End),
        _cp('d2-in', 'ingresso', day2Start, cantiereId: 'cant-2', customerId: 'cust-1'),
        _cp('d2-out', 'uscita', day2End),
      ]);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls.length, 2, reason: 'one POST per business day');
      expect(api.calls[0].single.clientId, 'd1-in');
      expect(api.calls[0].single.endTime, day1End);
      expect(api.calls[1].single.clientId, 'd2-in');
      expect(api.calls[1].single.endTime, day2End);
      expect(repo.markedSynced, containsAll(['d1-in', 'd1-out', 'd2-in', 'd2-out']));
    });

    test('an unclosed day is not closed by the next day\'s clock-in', () async {
      final day1Start = DateTime.utc(2026, 6, 22, 8);
      final day2Start = DateTime.utc(2026, 6, 23, 9);
      final day2End = DateTime.utc(2026, 6, 23, 18);
      final repo = _FakeRepo([], pendingBeyondToday: [
        _cp('d1-in', 'ingresso', day1Start, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('d2-in', 'ingresso', day2Start, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('d2-out', 'uscita', day2End),
      ]);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls[0].single.endTime, isNull, reason: 'day 1 stays open, not a 25-hour visit');
      expect(api.calls[1].single.endTime, day2End);
    });

    test('an overnight site visit is sent as one closed interval, in the day it began', () async {
      final start = DateTime.utc(2026, 6, 22, 22);
      final end = DateTime.utc(2026, 6, 23, 6);
      final repo = _FakeRepo([], pendingBeyondToday: [
        _cp('n-1', 'ingresso', start, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('n-2', 'uscita', end),
      ]);
      final api = _FakeApiClient();
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(api.calls.length, 1);
      expect(api.calls.single.single.clientId, 'n-1');
      expect(api.calls.single.single.endTime, end);
      expect(repo.markedSynced, containsAll(['n-1', 'n-2']));
    });
  });

  // ── P0-3: failures are classified, never swallowed ──────────────────────────
  group('CantiereTimbraSyncService.syncNow — failure classification', () {
    test('a 400 marks the error, keeps the events pending, and stops auto-retrying', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final repo = _FakeRepo([
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
      ]);
      final api = _FakeApiClient()..errorToThrow = _serverRefusal(400);
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(repo.syncErrors.keys, ['id-1']);
      expect(repo.syncErrors['id-1'], isNotEmpty);
      expect(repo.markedSynced, isEmpty, reason: 'a refused event is never marked synced');
      expect((await repo.getTodayEvents()).single.isPendingSync, isTrue);
      expect(
        await repo.getPendingCount(),
        1,
        reason: 'it is still unsent work, so the counter must show it',
      );

      // A later automatic run must not hammer the same refused bytes.
      api.errorToThrow = null;
      await svc.syncNow();
      expect(api.calls, isEmpty);
    });

    test('a 500 keeps the events pending and backs off instead of marking an error', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final repo = _FakeRepo([
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
      ]);
      final api = _FakeApiClient()..errorToThrow = _serverRefusal(500);
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();

      expect(repo.syncErrors, isEmpty);
      expect(repo.markedSynced, isEmpty);
      expect((await repo.getTodayEvents()).single.isPendingSync, isTrue);

      // Backed off: an immediate automatic retry does not reach the server.
      api.errorToThrow = null;
      await svc.syncNow();
      expect(api.calls, isEmpty);

      // A manual sync clears the hold and sends.
      await svc.syncNow(manual: true);
      expect(api.calls.length, 1);
    });

    test('a manual sync releases events held by a permanent refusal', () async {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final repo = _FakeRepo([
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
      ]);
      final api = _FakeApiClient()..errorToThrow = _serverRefusal(422);
      final svc = CantiereTimbraSyncService(repo: repo, apiClient: api);

      await svc.syncNow();
      expect(repo.syncErrors['id-1'], isNotEmpty);

      api.errorToThrow = null;
      await svc.syncNow(manual: true);

      expect(repo.syncErrors['id-1'], isNull);
      expect(api.calls.length, 1);
      expect(repo.markedSynced, contains('id-1'));
    });
  });
}

/// A real server answer, as `ProblemDetails` (the backend writes `code` at the root).
DioException _serverRefusal(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/cantiereworklog/mobile/sessions'),
  response: Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: '/api/cantiereworklog/mobile/sessions'),
    statusCode: status,
    data: {'title': 'Refused', 'code': 'invalid_request'},
  ),
  type: DioExceptionType.badResponse,
);
