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
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';

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
  Future<void> markReconciledOrphan(String id) async {
    final i = sessions.indexWhere((s) => s.id == id);
    final s = sessions[i];
    sessions[i] = WorkSession(
      id: s.id,
      eventTime: s.eventTime,
      eventType: s.eventType,
      notes: reconciledOrphanMarker,
      isPendingSync: s.isPendingSync,
    );
  }
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

// The clock the service sees. Taps are stamped just before it (TTL is 2 minutes, state checks kick
// in after 20 seconds), the shift opener long before.
final _now = DateTime.utc(2026, 9, 30, 10);
final _t0 = DateTime.utc(2026, 9, 30, 8);
DateTime _ago(int seconds) => _now.subtract(Duration(seconds: seconds));
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
ActiveTracker _srv(ActiveTrackerState? state, DateTime shiftStart, {DateTime? startedAt}) =>
    ActiveTracker(
      kind: ActiveTrackerKind.attendance,
      id: 'wl-web',
      startedAtUtc: startedAt ?? shiftStart,
      state: state,
      shiftStartedAtUtc: shiftStart,
    );

WorkSession _cmd(String id, String type, DateTime t) =>
    WorkSession(id: id, eventTime: t, eventType: type, isPendingSync: true);

void main() {
  late _Api api;
  var applied = 0;
  final notices = <String>[];
  var clock = _now;
  List<ActiveTracker>? active; // what GET /worklog/active answers; null => request fails
  TimbraSyncService svc(_Repo r) => TimbraSyncService(
    repo: r,
    apiClient: api,
    onRemoteCommandsApplied: () => applied++,
    onNotice: notices.add,
    clock: () => clock,
    fetchActive: () async => active ?? (throw _offline),
  );

  setUp(() {
    api = _Api();
    applied = 0;
    notices.clear();
    clock = _now;
    active = null;
  });

  test('Fine on a backfilled shift => POST /worklog/end, event synced, refresh requested', () async {
    final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(3))]);
    await svc(repo).syncNow();

    expect(api.calls, ['end']);
    expect(api.batches, isEmpty, reason: 'the batch matches by ClientId and cannot see this shift');
    expect(repo.isPending('f'), isFalse);
    expect(applied, 1);
  });

  test('Pausa alone => break/start', () async {
    final repo = _Repo([_remoteIngresso(), _cmd('p', 'pausa', _ago(3))]);
    await svc(repo).syncNow();
    expect(api.calls, ['break/start']);
    expect(repo.isPending('p'), isFalse);
  });

  test('a Pausa and a Ripresa queued together are never sent (they cancel out)', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _cmd('p', 'pausa', _ago(8)),
      _cmd('r', 'ripresa', _ago(3)),
    ]);
    await svc(repo).syncNow();

    expect(api.calls, isEmpty, reason: 'a zero-length paid break must never reach the server');
    expect(repo.isPending('p') || repo.isPending('r'), isFalse);
    expect(applied, 1, reason: 'reconcile converges to whatever the server actually holds');
  });

  test('a backfilled (marked) pausa is not a command; only the tap after it is', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _remoteMarked('bp', 'pausa', _t0.add(const Duration(hours: 1))),
      _cmd('r', 'ripresa', _ago(3)),
    ]);
    await svc(repo).syncNow();
    expect(api.calls, ['break/end']);
  });

  test('offline tap stays queued, then executes once on the next sync', () async {
    final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(3))]);
    final service = svc(repo);
    api.error = _offline;
    await service.syncNow();

    expect(repo.isPending('f'), isTrue);
    expect(applied, 0);

    api.error = null;
    active = [_srv(ActiveTrackerState.working, _t0)]; // the retry re-checks server state first
    await service.syncNow();
    expect(api.calls, ['end', 'end']); // first attempt failed, second succeeded
    expect(repo.isPending('f'), isFalse);
    await service.syncNow();
    expect(api.calls, hasLength(2), reason: 'a synced command is never replayed');
  });

  for (final code in [500, 503, 401, 408, 429]) {
    test('HTTP $code is transient: stays queued and later commands wait behind it', () async {
      final repo = _Repo([
        _remoteIngresso(),
        _cmd('p', 'pausa', _ago(8)),
        _cmd('r', 'fine', _ago(3)),
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
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(3))]);
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
      _cmd('p', 'pausa', _ago(8)),
      _cmd('f', 'fine', _ago(3)),
    ]);
    await svc(repo).syncNow();

    expect(api.calls, isEmpty);
    expect(api.batches, hasLength(1));
    expect(applied, 0);
  });

  test('remote shift ended by a tap, then a NEW local shift: REST for the first, batch for the second', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _cmd('f', 'fine', _ago(3)),
      _cmd('i2', 'ingresso', _ago(1)),
    ]);
    await svc(repo).syncNow();

    expect(api.calls, ['end']);
    expect(api.batches.single.single.clientId, 'i2');
  });

  test('a still-queued remote command is not marked synced by the batch path', () async {
    final repo = _Repo([
      _remoteIngresso(),
      _cmd('f', 'fine', _ago(3)),
      _cmd('i2', 'ingresso', _ago(1)),
    ]);
    api.error = _offline;
    await svc(repo).syncNow();

    expect(repo.isPending('f'), isTrue, reason: 'the offline Fine must survive the batch pass');
  });

  group('command TTL (2 minutes from the tap)', () {
    test('a command still inside the TTL is retried', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(100))]);
      api.error = _offline;
      final service = svc(repo);
      await service.syncNow();
      expect(repo.isPending('f'), isTrue);
      expect(notices, isEmpty);
    });

    test('past the TTL it is dropped with a visible message and the reconciler is asked to converge', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(121))]);
      await svc(repo).syncNow();

      expect(api.calls, isEmpty, reason: 'the server clock would stamp a stale tap with "now"');
      expect(repo.isPending('f'), isFalse);
      expect(notices, ['Timbratura non inviata, riprova']);
      expect(applied, 1);
    });
  });

  group('state check before a retry (lost response must not double-deliver)', () {
    test('a newer shift started elsewhere is NOT ended by a retried Fine', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(3))]);
      final service = svc(repo);
      api.error = _offline; // response lost: unknown whether the server applied it
      await service.syncNow();
      expect(api.calls, ['end']);

      api.error = null;
      // Meanwhile our shift was ended (by that first call) and ANOTHER one began on the web.
      active = [_srv(ActiveTrackerState.working, _t0.add(const Duration(hours: 2)))];
      await service.syncNow();

      expect(api.calls, ['end'], reason: 'must not end the newer shift');
      expect(repo.isPending('f'), isFalse);
      expect(applied, 1);
    });

    test('Fine whose server shift is already gone counts as done', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(30))]); // older than 20s
      active = const [];
      await svc(repo).syncNow();
      expect(api.calls, isEmpty);
      expect(repo.isPending('f'), isFalse);
      expect(applied, 1);
    });

    test('a command older than 20s is sent only when the state matches', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('p', 'pausa', _ago(30))]);
      active = [_srv(ActiveTrackerState.working, _t0)];
      await svc(repo).syncNow();
      expect(api.calls, ['break/start']);
    });

    test('Pausa when the server is already OnBreak is done, not repeated', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('p', 'pausa', _ago(30))]);
      active = [_srv(ActiveTrackerState.onBreak, _t0, startedAt: _ago(40))];
      await svc(repo).syncNow();
      expect(api.calls, isEmpty);
      expect(repo.isPending('p'), isFalse);
    });

    test('Ripresa needs the server OnBreak; already Working means done', () async {
      final base = [
        _remoteIngresso(),
        _remoteMarked('bp', 'pausa', _t0.add(const Duration(hours: 1))),
        _cmd('r', 'ripresa', _ago(30)),
      ];
      final sendRepo = _Repo(List.of(base));
      active = [_srv(ActiveTrackerState.onBreak, _t0, startedAt: _ago(3000))];
      await svc(sendRepo).syncNow();
      expect(api.calls, ['break/end']);

      final doneRepo = _Repo(List.of(base));
      active = [_srv(ActiveTrackerState.working, _t0)];
      await svc(doneRepo).syncNow();
      expect(api.calls, ['break/end'], reason: 'second run sent nothing');
      expect(doneRepo.isPending('r'), isFalse);
    });

    test('if the state cannot be read the command stays queued (never sent blind)', () async {
      final repo = _Repo([_remoteIngresso(), _cmd('f', 'fine', _ago(30))]);
      active = null; // GET /worklog/active fails
      await svc(repo).syncNow();
      expect(api.calls, isEmpty);
      expect(repo.isPending('f'), isTrue);
    });
  });

  group('a permanently failing batch (e.g. 409 active_session_exists)', () {
    test('retires the dead events, tells the user, and hands the shift to the REST path', () async {
      final repo = _Repo([_cmd('i', 'ingresso', _ago(10))]);
      final failing = _FailingBatchApi(_status(409));
      final service = TimbraSyncService(
        repo: repo,
        apiClient: failing,
        onRemoteCommandsApplied: () => applied++,
        onNotice: notices.add,
        clock: () => _now,
      );
      await service.syncNow();

      expect(repo.isPending('i'), isFalse, reason: 'no longer blocks the reconciler (hasUnsynced)');
      expect(repo.sessions.single.notes, reconciledOrphanMarker);
      expect(notices, ['Timbratura non sincronizzata: esiste già un turno aperto su un altro dispositivo']);
      expect(applied, 1);
      expect(failing.batchCalls, 1);

      await service.syncNow();
      expect(failing.batchCalls, 1, reason: 'no retry loop');
    });

    test('a transient batch failure (no response) is untouched', () async {
      final repo = _Repo([_cmd('i', 'ingresso', _ago(10))]);
      final failing = _FailingBatchApi(_offline);
      await TimbraSyncService(repo: repo, apiClient: failing, onNotice: notices.add).syncNow();
      expect(repo.isPending('i'), isTrue);
      expect(notices, isEmpty);
    });
  });
}

class _FailingBatchApi extends WorklogApiClient {
  _FailingBatchApi(this.error) : super(Dio());
  final Object error;
  int batchCalls = 0;
  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> s) async {
    batchCalls++;
    throw error;
  }
}
