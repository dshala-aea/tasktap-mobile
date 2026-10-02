// dart format width=100
// WorkLogReconciler against the REAL shape of GET /api/worklog/active.
//
// The reconciler used to read the open session's start from GET /worklog/mobile/today, whose
// `startTime` is a bare "HH:mm:ss" TimeSpan that `DateTime.parse` throws on — so the backfill
// silently no-oped and a clock started on another device never appeared here. /worklog/active
// carries true-UTC instants plus the attendance state, and is the single source now.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart' show deriveShiftState;

import '../../support/active_tracker_fixtures.dart';

class _Repo implements IWorkSessionRepository {
  @override
  Future<void> markSyncFailed(String id) async {}

  _Repo(this.sessions);
  final List<WorkSession> sessions;

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
    sessions.sort((a, b) => a.eventTime.compareTo(b.eventTime));
  }

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

  @override
  Future<List<WorkSession>> getTodaySessions() async => List.of(sessions);
  @override
  Stream<List<WorkSession>> watchTodaySessions() => Stream.value(sessions);
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
  Future<void> clearToday() async {}
}

WorkSession _synced(String id, String type, DateTime t) =>
    WorkSession(id: id, eventType: type, eventTime: t, isPendingSync: false);
WorkSession _pending(String id, String type, DateTime t) =>
    WorkSession(id: id, eventType: type, eventTime: t, isPendingSync: true);

final _shift = DateTime.utc(2026, 9, 30, 8, 23, 45);
// The fixtures are anchored on 2026-09-30; the reconciler clamps a start earlier than local
// midnight "today", so tests using them must pin the clock (see [pinToFixtureDay]) or they rot
// the day after the fixture. Tests built on DateTime.now() keep the real clock.
final _fixtureNow = DateTime.utc(2026, 9, 30, 13);
final _break = DateTime.utc(2026, 9, 30, 11, 2, 10);

void main() {
  late List<ActiveTracker> server;
  Object? fetchError;
  var fetchCalls = 0;
  DateTime Function() clock = DateTime.now;
  void pinToFixtureDay() => clock = () => _fixtureNow;

  WorkLogReconciler make(_Repo repo) => WorkLogReconciler(
    repo: repo,
    clock: () => clock(),
    fetchActive: () async {
      fetchCalls++;
      if (fetchError != null) throw fetchError!;
      return server;
    },
  );

  setUp(() {
    server = const [];
    fetchError = null;
    fetchCalls = 0;
    clock = DateTime.now;
  });

  group('wire shape', () {
    test('parses state and shiftStartedAtUtc, incl. a 7-digit .NET fraction', () {
      final t = trackersFromWire([attendanceWorkingJson]).single;
      expect(t.kind, ActiveTrackerKind.attendance);
      expect(t.state, ActiveTrackerState.working);
      expect(t.startedAtUtc.isUtc, isTrue);
      expect(t.shiftStartedAtUtc, DateTime.utc(2026, 9, 30, 8, 23, 45, 123, 456));
    });

    test('OnBreak: startedAtUtc is the break start, shiftStartedAtUtc the day start', () {
      final t = trackersFromWire([attendanceOnBreakJson]).single;
      expect(t.state, ActiveTrackerState.onBreak);
      expect(t.startedAtUtc, _break);
      expect(t.shiftStartedAtUtc, _shift);
    });

    test('cantiere carries a null state and null shiftStartedAtUtc', () {
      final t = trackersFromWire([cantiereJson]).single;
      expect(t.state, isNull);
      expect(t.shiftStartedAtUtc, isNull);
      expect(jsonDecode(cantiereJson)['state'], isNull);
    });
  });

  group('ServerWorkLogSnapshot.fromActiveTrackers', () {
    test('no attendance row (only a cantiere) means not on shift', () {
      final s = ServerWorkLogSnapshot.fromActiveTrackers(trackersFromWire([cantiereJson]));
      expect(s.isOnShift, isFalse);
    });

    test('Working uses shiftStartedAtUtc, falling back to startedAtUtc', () {
      final s = ServerWorkLogSnapshot.fromActiveTrackers(trackersFromWire([attendanceWorkingJson]));
      expect(s.isOnShift, isTrue);
      expect(s.isOnPause, isFalse);
      final legacy = ServerWorkLogSnapshot.fromActiveTrackers([
        ActiveTracker(
          kind: ActiveTrackerKind.attendance,
          id: 'x',
          startedAtUtc: _shift,
          state: ActiveTrackerState.working,
        ),
      ]);
      expect(legacy.activeStartTime, _shift);
    });

    test('OnBreak exposes the break start separately from the shift start', () {
      final s = ServerWorkLogSnapshot.fromActiveTrackers(trackersFromWire([attendanceOnBreakJson]));
      expect(s.isOnPause, isTrue);
      expect(s.activeStartTime, _shift);
      expect(s.breakStartTime, _break);
    });
  });

  group('server open, local unaware (started on another device)', () {
    test('Working: backfills ingresso at the shift start, marked so it is never re-uploaded', () async {
      pinToFixtureDay();
      server = trackersFromWire([attendanceWorkingJson, cantiereJson]);
      final repo = _Repo([]);
      await make(repo).reconcile();

      expect(repo.sessions.map((s) => s.eventType), ['ingresso']);
      expect(repo.sessions.single.eventTime, DateTime.utc(2026, 9, 30, 8, 23, 45, 123, 456));
      expect(repo.sessions.single.notes, reconciledOrphanMarker);
      expect(deriveShiftState(repo.sessions).isOnShift, isTrue);
    });

    test('OnBreak: backfills ingresso AND pausa so local == OnBreak', () async {
      pinToFixtureDay();
      server = trackersFromWire([attendanceOnBreakJson]);
      final repo = _Repo([]);
      await make(repo).reconcile();

      expect(repo.sessions.map((s) => s.eventType), ['ingresso', 'pausa']);
      expect(repo.sessions.every((s) => s.notes == reconciledOrphanMarker), isTrue);
      final local = deriveShiftState(repo.sessions);
      expect(local.isOnShift, isTrue);
      expect(local.isOnPause, isTrue);
      expect(local.shiftStartTime, _shift);
      expect(local.pauseStartTime, _break);
    });

    test('is idempotent: a second reconcile adds nothing', () async {
      pinToFixtureDay();
      server = trackersFromWire([attendanceOnBreakJson]);
      final repo = _Repo([]);
      final r = make(repo);
      await r.reconcile();
      await r.reconcile();
      expect(repo.sessions, hasLength(2));
    });

    test('a pending local "fine" (offline stop) is not overwritten by the server view', () async {
      server = trackersFromWire([attendanceWorkingJson]);
      final repo = _Repo([
        _synced('i', 'ingresso', _shift),
        _pending('f', 'fine', DateTime.utc(2026, 9, 30, 9)),
      ]);
      await make(repo).reconcile();
      expect(repo.sessions, hasLength(2));
    });
  });

  group('server open, local open', () {
    test('server Working, local OnBreak (synced): break ended elsewhere -> marked ripresa', () async {
      server = trackersFromWire([attendanceWorkingJson]);
      final repo = _Repo([
        _synced('i', 'ingresso', _shift),
        _synced('p', 'pausa', _break),
      ]);
      await make(repo).reconcile();

      expect(repo.sessions.last.eventType, 'ripresa');
      expect(repo.sessions.last.notes, reconciledOrphanMarker);
      expect(deriveShiftState(repo.sessions).isOnPause, isFalse);
    });

    test('server OnBreak, local Working (synced): break started elsewhere -> marked pausa', () async {
      server = trackersFromWire([attendanceOnBreakJson]);
      final repo = _Repo([_synced('i', 'ingresso', _shift)]);
      await make(repo).reconcile();

      expect(repo.sessions.last.eventType, 'pausa');
      expect(repo.sessions.last.eventTime, _break);
      expect(repo.sessions.last.notes, reconciledOrphanMarker);
    });

    test('pending local events win: an offline ripresa is not undone by a stale OnBreak', () async {
      server = trackersFromWire([attendanceOnBreakJson]);
      final repo = _Repo([
        _synced('i', 'ingresso', _shift),
        _synced('p', 'pausa', _break),
        _pending('r', 'ripresa', DateTime.utc(2026, 9, 30, 11, 30)),
      ]);
      await make(repo).reconcile();
      expect(repo.sessions, hasLength(3));
    });
  });

  group('server has no open attendance, local open', () {
    test('synced local shift is closed and its opener marked (existing rule)', () async {
      server = trackersFromWire([cantiereJson]);
      final repo = _Repo([_synced('i', 'ingresso', _shift)]);
      await make(repo).reconcile();

      expect(repo.sessions.last.eventType, 'fine');
      expect(repo.sessions.first.notes, reconciledOrphanMarker);
      expect(deriveShiftState(repo.sessions).isOnShift, isFalse);
    });

    test('a shift punched offline (still pending) is NOT closed by an empty server view', () async {
      server = const [];
      final repo = _Repo([_pending('i', 'ingresso', _shift)]);
      await make(repo).reconcile();

      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.single.notes, isNull);
    });
  });

  group('backfill placement', () {
    test('an overnight shift (server start before local midnight) is anchored at local midnight', () async {
      // Rome midnight of 2026-09-30 is 2026-09-29T22:00Z, whatever the device zone.
      pinToFixtureDay();
      final midnight = DateTime.utc(2026, 9, 29, 22);
      final started = midnight.subtract(const Duration(hours: 3));
      server = [
        ActiveTracker(
          kind: ActiveTrackerKind.attendance,
          id: 'wl',
          startedAtUtc: started,
          state: ActiveTrackerState.working,
          shiftStartedAtUtc: started,
        ),
      ];
      final repo = _Repo([]);
      await make(repo).reconcile();

      expect(repo.sessions.single.eventTime, midnight);
    });

    ActiveTracker overnight(DateTime started) => ActiveTracker(
      kind: ActiveTrackerKind.attendance,
      id: 'wl',
      startedAtUtc: started,
      state: ActiveTrackerState.working,
      shiftStartedAtUtc: started,
    );

    test('start 22:00 Rome the evening before, clock 08:00 Rome: anchored at Rome midnight', () async {
      server = [overnight(DateTime.utc(2026, 9, 29, 20))];
      clock = () => DateTime.utc(2026, 9, 30, 6);
      final repo = _Repo([]);
      await make(repo).reconcile();
      expect(repo.sessions.single.eventTime, DateTime.utc(2026, 9, 29, 22));
    });

    test('business zone Los Angeles anchors at the Los Angeles midnight', () async {
      // 05:00 in LA on 2026-09-30; the shift started 19:00 LA the evening before.
      server = [overnight(DateTime.utc(2026, 9, 30, 2))];
      final repo = _Repo([]);
      final r = WorkLogReconciler(
        repo: repo,
        businessTime: BusinessTime('America/Los_Angeles', clock: () => DateTime.utc(2026, 9, 30, 12)),
        fetchActive: () async => server,
      );
      await r.reconcile();
      expect(repo.sessions.single.eventTime, DateTime.utc(2026, 9, 30, 7));
    });

    test('a server start after the business midnight is untouched', () async {
      server = [overnight(DateTime.utc(2026, 9, 29, 23))];
      clock = () => DateTime.utc(2026, 9, 30, 6);
      final repo = _Repo([]);
      await make(repo).reconcile();
      expect(repo.sessions.single.eventTime, DateTime.utc(2026, 9, 29, 23));
    });

    test('a Fine the server refused (shift still open) re-opens the shift AFTER that stop', () async {
      final stop = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final started = stop.subtract(const Duration(hours: 2));
      server = [
        ActiveTracker(
          kind: ActiveTrackerKind.attendance,
          id: 'wl',
          startedAtUtc: started,
          state: ActiveTrackerState.working,
          shiftStartedAtUtc: started,
        ),
      ];
      final repo = _Repo([
        WorkSession(
          id: 'i',
          eventTime: started,
          eventType: 'ingresso',
          notes: reconciledOrphanMarker,
          isPendingSync: true,
        ),
        _synced('f', 'fine', stop), // retired after a permanent refusal
      ]);
      await make(repo).reconcile();

      expect(deriveShiftState(repo.sessions).isOnShift, isTrue);
    });

    test('a batch-synced local stop is NOT overridden by a stale server view', () async {
      final stop = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final started = stop.subtract(const Duration(hours: 2));
      server = [
        ActiveTracker(
          kind: ActiveTrackerKind.attendance,
          id: 'wl',
          startedAtUtc: started,
          state: ActiveTrackerState.working,
          shiftStartedAtUtc: started,
        ),
      ];
      final repo = _Repo([_synced('i', 'ingresso', started), _synced('f', 'fine', stop)]);
      await make(repo).reconcile();

      expect(deriveShiftState(repo.sessions).isOnShift, isFalse);
    });
  });

  group('convergence: repeated reconciles with unchanged inputs add ZERO rows', () {
    ActiveTracker att(ActiveTrackerState st, DateTime shift, {DateTime? started}) => ActiveTracker(
      kind: ActiveTrackerKind.attendance,
      id: 'wl',
      startedAtUtc: started ?? shift,
      state: st,
      shiftStartedAtUtc: shift,
    );

    Future<void> converges(_Repo repo, {int extraRuns = 3}) async {
      final r = make(repo);
      await r.reconcile();
      final after = repo.sessions.length;
      for (var i = 0; i < extraRuns; i++) {
        await r.reconcile();
      }
      expect(repo.sessions.length, after, reason: 'a repeat reconcile inserted rows');
    }

    test('refused Ripresa (server stays OnBreak, local retired the command)', () async {
      final b = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final started = b.subtract(const Duration(hours: 2));
      server = [att(ActiveTrackerState.onBreak, started, started: b)];
      final repo = _Repo([
        WorkSession(id: 'i', eventTime: started, eventType: 'ingresso', notes: reconciledOrphanMarker, isPendingSync: true),
        WorkSession(id: 'p', eventTime: b, eventType: 'pausa', notes: reconciledOrphanMarker, isPendingSync: true),
        _synced('r', 'ripresa', b.add(const Duration(minutes: 10))), // retired after a refusal
      ]);
      await converges(repo);

      final local = deriveShiftState(repo.sessions);
      expect(local.isOnShift, isTrue);
      expect(local.isOnPause, isTrue, reason: 'local reverted to the server truth');
    });

    test('clock skew: phone behind the server (local event AFTER the server break start)', () async {
      final b = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final started = b.subtract(const Duration(hours: 2));
      server = [att(ActiveTrackerState.onBreak, started, started: b)];
      final repo = _Repo([_synced('i', 'ingresso', b.add(const Duration(seconds: 5)))]);
      await converges(repo);
      expect(deriveShiftState(repo.sessions).isOnPause, isTrue);
    });

    test('stale post-Fine server view: local batch-synced stop, server still Working', () async {
      final stop = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final started = stop.subtract(const Duration(hours: 2));
      server = [att(ActiveTrackerState.working, started)];
      final repo = _Repo([_synced('i', 'ingresso', started), _synced('f', 'fine', stop)]);
      await converges(repo);
      expect(repo.sessions, hasLength(2), reason: 'no ghost shift, no rows at all');
      expect(deriveShiftState(repo.sessions).isOnShift, isFalse);
    });

    test('server Working, local OnBreak with a skewed clock: ripresa is placed last', () async {
      final started = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      server = [att(ActiveTrackerState.working, started)];
      final future = DateTime.now().toUtc().add(const Duration(minutes: 3)); // phone ahead
      final repo = _Repo([_synced('i', 'ingresso', started), _synced('p', 'pausa', future)]);
      await converges(repo);
      expect(deriveShiftState(repo.sessions).isOnPause, isFalse);
    });

    test('server has nothing, local synced shift with a future-stamped opener: fine is placed last', () async {
      server = const [];
      final future = DateTime.now().toUtc().add(const Duration(minutes: 3));
      final repo = _Repo([_synced('i', 'ingresso', future)]);
      await converges(repo);
      expect(deriveShiftState(repo.sessions).isOnShift, isFalse);
    });
  });

  group('stale fetch race (local snapshot read BEFORE the network call)', () {
    test('a sync that lands while the fetch is in flight makes the fetch stale: no close, then re-run', () async {
      final started = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final repo = _Repo([_pending('i', 'ingresso', started)]);
      var calls = 0;
      final r = WorkLogReconciler(
        repo: repo,
        fetchActive: () async {
          calls++;
          if (calls == 1) {
            // The concurrent sync pushed the shift and marked it synced while we were waiting;
            // the answer we are about to return was computed before the server saw it.
            await repo.markSynced(['i']);
            return const [];
          }
          return [
            ActiveTracker(
              kind: ActiveTrackerKind.attendance,
              id: 'wl',
              startedAtUtc: started,
              state: ActiveTrackerState.working,
              shiftStartedAtUtc: started,
            ),
          ];
        },
      );
      await r.reconcile();

      expect(calls, 2, reason: 'the stale answer was discarded and re-fetched');
      expect(repo.sessions.map((s) => s.eventType), ['ingresso'], reason: 'the shift was not closed');
    });
  });

  group('events held after a refused batch (still pending, unmarked)', () {
    test('count as unsynced: the phone\'s own view wins and stays visible (safe payroll direction)', () async {
      final started = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      // Server says nothing is running — but our punch was refused and is being held.
      server = const [];
      final repo = _Repo([_pending('i', 'ingresso', started)]);
      await make(repo).reconcile();
      await make(repo).reconcile();

      expect(repo.sessions, hasLength(1), reason: 'no fine appended, nothing retired');
      expect(deriveShiftState(repo.sessions).isOnShift, isTrue);
    });
  });

  group('a Fine dropped by the TTL', () {
    test('the shift is still open on the server: the reconciler re-opens it', () async {
      final stop = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      final started = stop.subtract(const Duration(hours: 2));
      server = [
        ActiveTracker(
          kind: ActiveTrackerKind.attendance,
          id: 'wl',
          startedAtUtc: started,
          state: ActiveTrackerState.working,
          shiftStartedAtUtc: started,
        ),
      ];
      final repo = _Repo([
        WorkSession(id: 'i', eventTime: started, eventType: 'ingresso', notes: reconciledOrphanMarker, isPendingSync: true),
        _synced('f', 'fine', stop), // dropped by the TTL: retired without being sent
      ]);
      await make(repo).reconcile();
      expect(deriveShiftState(repo.sessions).isOnShift, isTrue);
    });
  });

  group('failure and concurrency', () {
    test('a failed fetch changes nothing', () async {
      fetchError = Exception('offline');
      final repo = _Repo([_synced('i', 'ingresso', _shift)]);
      await make(repo).reconcile();
      expect(repo.sessions, hasLength(1));
    });

    test('a request arriving mid-run is re-run afterwards, not dropped', () async {
      server = const [];
      final repo = _Repo([]);
      final r = make(repo);
      final first = r.reconcile();
      final second = r.reconcile(); // arrives while the first is in flight
      await Future.wait([first, second]);
      // The second call must have caused a second fetch: a WorkLogChanged event that lands during
      // a run describes a change the in-flight fetch may already have missed.
      await pumpEventQueue();
      expect(fetchCalls, 2);
    });
  });
}
