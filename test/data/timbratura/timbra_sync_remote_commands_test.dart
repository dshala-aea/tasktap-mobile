// dart format width=100
// Fine / Pausa / Ripresa on a shift that was started on ANOTHER device (backfilled locally by the
// reconciler, orphan-marked). The mobile batch POST /worklog/mobile/sessions matches by ClientId
// and can never find that remote row, so these taps must act on the server shift through the
// plain REST endpoints (end, break/start, break/end). The local event row is the persisted
// command: pending until the call is accepted (or permanently refused), so an offline tap is not
// lost and is retried on reconnect.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

class _Repo implements IWorkSessionRepository {
  _Repo(this.sessions);
  final List<WorkSession> sessions;

  bool isPending(String id) => sessions.firstWhere((s) => s.id == id).isPendingSync;

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
  Future<void> markSynced(List<String> ids) async {
    for (final id in ids) {
      final i = sessions.indexWhere((s) => s.id == id);
      final s = sessions[i];
      sessions[i] = WorkSession(
        id: s.id,
        eventTime: s.eventTime,
        eventType: s.eventType,
        notes: s.notes,
        isPendingSync: false,
      );
    }
  }

  @override
  Future<List<WorkSession>> getTodaySessions() async => List.of(sessions);
  @override
  Stream<List<WorkSession>> watchTodaySessions() => Stream.value(sessions);
  @override
  Future<void> clearToday() async {}
  @override
  Future<void> markReconciledOrphan(String id) async {}
}

class _Api extends WorklogApiClient {
  _Api() : super(Dio());
  final calls = <String>[];
  final batches = <List<MobileSessionDto>>[];
  Object? error;

  Future<void> _rest(String name) async {
    calls.add(name);
    if (error != null) throw error!;
  }

  @override
  Future<void> endWork() => _rest('end');
  @override
  Future<void> startBreak() => _rest('break/start');
  @override
  Future<void> endBreak() => _rest('break/end');

  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async {
    batches.add(sessions);
    return [];
  }
}

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(),
  type: DioExceptionType.badResponse,
  response: Response(requestOptions: RequestOptions(), statusCode: code),
);

DioException get _offline =>
    DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError);

final _t0 = DateTime.utc(2026, 9, 30, 8);
WorkSession _remoteIngresso() => WorkSession(
  id: 'remote-i',
  eventTime: _t0,
  eventType: 'ingresso',
  notes: reconciledOrphanMarker,
  isPendingSync: true,
);
WorkSession _remoteMarked(String id, String type, DateTime t) => WorkSession(
  id: id,
  eventTime: t,
  eventType: type,
  notes: reconciledOrphanMarker,
  isPendingSync: true,
);
WorkSession _cmd(String id, String type, DateTime t) =>
    WorkSession(id: id, eventTime: t, eventType: type, isPendingSync: true);

void main() {
  late _Api api;
  var applied = 0;
  TimbraSyncService svc(_Repo r) => TimbraSyncService(
    repo: r,
    apiClient: api,
    onRemoteCommandsApplied: () => applied++,
  );

  setUp(() {
    api = _Api();
    applied = 0;
  });

  test('Fine on a backfilled shift => POST /worklog/end, event synced, refresh requested', () async {
    final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _t0.add(const Duration(hours: 2)))]);
    await svc(repo).syncNow();

    expect(api.calls, ['end']);
    expect(api.batches, isEmpty, reason: 'the batch matches by ClientId and cannot see this shift');
    expect(repo.isPending('f'), isFalse);
    expect(applied, 1);
  });

  test('Pausa => break/start; Ripresa => break/end, in tap order', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _cmd('p', 'pausa', _t0.add(const Duration(hours: 1))),
      _cmd('r', 'ripresa', _t0.add(const Duration(hours: 1, minutes: 20))),
    ]);
    await svc(repo).syncNow();

    expect(api.calls, ['break/start', 'break/end']);
    expect(repo.isPending('p') || repo.isPending('r'), isFalse);
  });

  test('a backfilled (marked) pausa is not a command; only the tap after it is', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _remoteMarked('bp', 'pausa', _t0.add(const Duration(hours: 1))),
      _cmd('r', 'ripresa', _t0.add(const Duration(hours: 2))),
    ]);
    await svc(repo).syncNow();
    expect(api.calls, ['break/end']);
  });

  test('offline tap stays queued, then executes once on the next sync', () async {
    final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _t0.add(const Duration(hours: 2)))]);
    api.error = _offline;
    await svc(repo).syncNow();

    expect(repo.isPending('f'), isTrue);
    expect(applied, 0);

    api.error = null;
    await svc(repo).syncNow();
    expect(api.calls, ['end', 'end']); // first attempt failed, second succeeded
    expect(repo.isPending('f'), isFalse);
    await svc(repo).syncNow();
    expect(api.calls, hasLength(2), reason: 'a synced command is never replayed');
  });

  for (final code in [500, 503, 401, 408, 429]) {
    test('HTTP $code is transient: stays queued and later commands wait behind it', () async {
      final repo = _Repo([
        _remoteIngresso(),
        _cmd('p', 'pausa', _t0.add(const Duration(hours: 1))),
        _cmd('r', 'ripresa', _t0.add(const Duration(hours: 2))),
      ]);
      api.error = _status(code);
      await svc(repo).syncNow();

      expect(api.calls, ['break/start'], reason: 'order matters: stop at the first transient failure');
      expect(repo.isPending('p'), isTrue);
      expect(repo.isPending('r'), isTrue);
    });
  }

  for (final code in [400, 404, 409, 422]) {
    test('HTTP $code is permanent: dropped (not looped) and the reconciler is asked to converge', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _t0.add(const Duration(hours: 2)))]);
      api.error = _status(code);
      await svc(repo).syncNow();

      expect(repo.isPending('f'), isFalse);
      expect(applied, 1);

      await svc(repo).syncNow();
      expect(api.calls, ['end'], reason: 'no retry loop');
    });
  }

  test('a locally started shift keeps using the mobile batch, never the REST endpoints', () async {
    final repo = _Repo([
      _cmd('i', 'ingresso', _t0),
      _cmd('p', 'pausa', _t0.add(const Duration(hours: 1))),
      _cmd('f', 'fine', _t0.add(const Duration(hours: 2))),
    ]);
    await svc(repo).syncNow();

    expect(api.calls, isEmpty);
    expect(api.batches, hasLength(1));
    expect(applied, 0);
  });

  test('remote shift ended by a tap, then a NEW local shift: REST for the first, batch for the second', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _cmd('f', 'fine', _t0.add(const Duration(hours: 2))),
      _cmd('i2', 'ingresso', _t0.add(const Duration(hours: 3))),
    ]);
    await svc(repo).syncNow();

    expect(api.calls, ['end']);
    expect(api.batches.single.single.clientId, 'i2');
  });

  test('a still-queued remote command is not marked synced by the batch path', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _cmd('f', 'fine', _t0.add(const Duration(hours: 2))),
      _cmd('i2', 'ingresso', _t0.add(const Duration(hours: 3))),
    ]);
    api.error = _offline;
    await svc(repo).syncNow();

    expect(repo.isPending('f'), isTrue, reason: 'the offline Fine must survive the batch pass');
  });
}
