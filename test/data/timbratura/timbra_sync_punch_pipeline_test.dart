// dart format width=100
// TimbraSyncService on the unified punch pipeline (EPIC 29): every pending local event is sent as a
// punch event, the server's per-event outcome decides what happens to it.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

class _Repo implements IWorkSessionRepository {
  _Repo(this.sessions);

  final List<WorkSession> sessions;
  final List<String> synced = [];
  final List<String> failed = [];

  @override
  Future<List<WorkSession>> getTodaySessions() async => sessions;
  @override
  Future<List<WorkSession>> getAllSessions() async => List.of(sessions);
  @override
  Future<List<WorkSession>> getPendingSessions() async =>
      sessions.where((s) => s.isPendingSync).toList();
  @override
  Future<int> getPendingCount() async => (await getPendingSessions()).length;
  @override
  Future<void> markSynced(List<String> ids) async => synced.addAll(ids);
  @override
  Future<void> markSyncFailed(String id) async => failed.add(id);
  @override
  Stream<List<WorkSession>> watchTodaySessions() => Stream.value(sessions);
  @override
  Stream<List<WorkSession>> watchAllSessions() => Stream.value(sessions);
  @override
  Stream<List<WorkSession>> watchSyncFailedSessions({
    Duration within = const Duration(days: 7),
  }) => const Stream<List<WorkSession>>.empty();
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
  Future<void> clearToday() async {}
  @override
  Future<void> markReconciledOrphan(String id) async {}
}

class _Api extends WorklogApiClient {
  _Api() : super(Dio());

  final List<List<PunchEventDto>> punchCalls = [];
  int legacyCalls = 0;

  /// Per event id: the outcome the server answers. Missing ids are `Applied`.
  final Map<String, PunchEventResultDto> answers = {};
  Object? failWith;

  @override
  Future<PunchBatchResultDto> applyPunches(List<PunchEventDto> events) async {
    if (failWith != null) throw failWith!;
    punchCalls.add(List.of(events));
    return PunchBatchResultDto(
      results: [
        for (final e in events)
          answers[e.clientEventId] ??
              PunchEventResultDto(clientEventId: e.clientEventId, outcome: 'Applied'),
      ],
    );
  }

  @override
  Future<List<UpsertSessionResponse>> upsertSessions(
    List<MobileSessionDto> sessions, {
    List<MobileSessionDto> breaks = const [],
  }) async {
    legacyCalls++;
    return [];
  }
}

WorkSession _ws(String id, String type, DateTime time, {String? notes, double? lat}) => WorkSession(
  id: id,
  eventType: type,
  eventTime: time,
  notes: notes,
  isPendingSync: true,
  latitude: lat,
);

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/worklog/punches'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/worklog/punches'),
    statusCode: status,
  ),
);

final _t = DateTime.utc(2026, 11, 19, 6);

TimbraSyncService _svc(_Repo repo, _Api api, {bool pipeline = true, List<String>? notices}) =>
    TimbraSyncService(
      repo: repo,
      apiClient: api,
      punchPipelineEnabled: () async => pipeline,
      onNotice: notices?.add,
      clock: () => DateTime.utc(2026, 11, 19, 18),
    );

void main() {
  group('punch pipeline sync', () {
    test('sends each pending event as a punch, oldest first, with its own instant and id', () async {
      final repo = _Repo([
        _ws('a', 'ingresso', _t, lat: 45.1),
        _ws('b', 'pausa', _t.add(const Duration(hours: 4))),
        _ws('c', 'ripresa', _t.add(const Duration(hours: 4, minutes: 30))),
        _ws('d', 'fine', _t.add(const Duration(hours: 9))),
      ]);
      final api = _Api();

      await _svc(repo, api).syncNow();

      expect(api.legacyCalls, 0);
      final sent = api.punchCalls.single;
      expect(sent.map((e) => e.type), ['ClockIn', 'BreakStart', 'BreakEnd', 'ClockOut']);
      expect(sent.map((e) => e.clientEventId), ['a', 'b', 'c', 'd']);
      expect(sent.first.occurredAtUtc, _t);
      expect(sent.first.latitude, 45.1);
      expect(sent.first.deviceUtc, DateTime.utc(2026, 11, 19, 18)); // send time, not tap time
      expect(repo.synced, ['a', 'b', 'c', 'd']);
    });

    test('a break is sent at once: the server holds it open while the person is on break', () async {
      final repo = _Repo([
        _ws('a', 'ingresso', _t),
        _ws('b', 'pausa', _t.add(const Duration(hours: 4))),
      ]);
      final api = _Api();

      await _svc(repo, api).syncNow();

      expect(api.punchCalls.single.map((e) => e.type), ['ClockIn', 'BreakStart']);
      expect(repo.synced, ['a', 'b']);
    });

    test('NoOp counts as done: the state asked for already held', () async {
      final repo = _Repo([_ws('a', 'ingresso', _t)]);
      final api = _Api()
        ..answers['a'] = const PunchEventResultDto(clientEventId: 'a', outcome: 'NoOp');

      await _svc(repo, api).syncNow();

      expect(repo.synced, ['a']);
      expect(repo.failed, isEmpty);
    });

    test('a rejected tap is retired and explained once; the others still go through', () async {
      final repo = _Repo([
        _ws('a', 'ingresso', _t),
        _ws('b', 'pausa', _t.add(const Duration(hours: 4))),
        _ws('c', 'fine', _t.add(const Duration(hours: 9))),
      ]);
      final api = _Api()
        ..answers['b'] = const PunchEventResultDto(
          clientEventId: 'b',
          outcome: 'Rejected',
          reason: 'superseded',
        );
      final notices = <String>[];

      await _svc(repo, api, notices: notices).syncNow();

      expect(repo.failed, ['b']);
      expect(repo.synced, ['a', 'c']);
      expect(notices, [punchRejectionMessage('superseded')]);

      // The same reason again in this run says nothing more.
      final repo2 = _Repo([_ws('x', 'pausa', _t)]);
      final api2 = _Api()
        ..answers['x'] = const PunchEventResultDto(
          clientEventId: 'x',
          outcome: 'Rejected',
          reason: 'superseded',
        );
      final svc = _svc(repo2, api2, notices: notices);
      await svc.syncNow();
      expect(notices.length, 2); // a new service instance has its own once-per-reason memory
    });

    test('a transient failure leaves every event pending', () async {
      final repo = _Repo([_ws('a', 'ingresso', _t)]);
      final api = _Api()..failWith = _http(503);

      await _svc(repo, api).syncNow();

      expect(repo.synced, isEmpty);
      expect(repo.failed, isEmpty);
    });

    test('offline (no response) leaves every event pending', () async {
      final repo = _Repo([_ws('a', 'ingresso', _t)]);
      final api = _Api()
        ..failWith = DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        );

      await _svc(repo, api).syncNow();

      expect(repo.synced, isEmpty);
      expect(repo.failed, isEmpty);
    });

    test('a permanent refusal of the whole request retires the events instead of looping', () async {
      final repo = _Repo([_ws('a', 'ingresso', _t)]);
      final api = _Api()..failWith = _http(400);

      await _svc(repo, api).syncNow();

      expect(repo.failed, ['a']);
      expect(repo.synced, isEmpty);
    });

    test('reconciler corrections are never sent', () async {
      final repo = _Repo([
        _ws('a', 'ingresso', _t, notes: reconciledOrphanMarker),
        _ws('b', 'fine', _t.add(const Duration(hours: 2))),
      ]);
      final api = _Api();

      await _svc(repo, api).syncNow();

      expect(api.punchCalls.single.map((e) => e.clientEventId), ['b']);
    });

    test('a backlog from earlier days goes in one ordered batch', () async {
      final repo = _Repo([
        _ws('old-in', 'ingresso', _t.subtract(const Duration(days: 1))),
        _ws('old-out', 'fine', _t.subtract(const Duration(days: 1)).add(const Duration(hours: 8))),
        _ws('in', 'ingresso', _t),
      ]);
      final api = _Api();

      await _svc(repo, api).syncNow();

      expect(api.punchCalls.single.map((e) => e.clientEventId), ['old-in', 'old-out', 'in']);
    });

    test('with the flag off the legacy interval batch is used and no punch is sent', () async {
      final repo = _Repo([_ws('a', 'ingresso', _t), _ws('b', 'fine', _t.add(const Duration(hours: 8)))]);
      final api = _Api();

      await _svc(repo, api, pipeline: false).syncNow();

      expect(api.punchCalls, isEmpty);
      expect(api.legacyCalls, 1);
    });

    test('nothing pending → no request', () async {
      final api = _Api();
      await _svc(_Repo([]), api).syncNow();
      expect(api.punchCalls, isEmpty);
    });
  });

  group('punchRejectionMessage', () {
    test('each known reason has its own text and unknown ones fall back', () {
      final texts = {
        for (final r in ['superseded', 'not_clocked_in', 'on_break', 'too_old', 'in_future'])
          r: punchRejectionMessage(r),
      };
      expect(texts.values.toSet().length, 5);
      expect(punchRejectionMessage('something_new'), punchRejectionMessage(null));
    });
  });
}
