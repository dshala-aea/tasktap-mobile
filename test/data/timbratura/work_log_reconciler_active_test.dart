// dart format width=100
// WorkLogReconciler against the REAL shape of GET /api/worklog/active.
//
// The reconciler used to read the open session's start from GET /worklog/mobile/today, whose
// `startTime` is a bare "HH:mm:ss" TimeSpan that `DateTime.parse` throws on — so the backfill
// silently no-oped and a clock started on another device never appeared here. /worklog/active
// carries true-UTC instants plus the attendance state, and is the single source now.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart' show deriveShiftState;

import '../../support/active_tracker_fixtures.dart';

class _Repo implements IWorkSessionRepository {
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
  Future<void> markSynced(List<String> ids) async {}
  @override
  Future<void> clearToday() async {}
}

WorkSession _synced(String id, String type, DateTime t) =>
    WorkSession(id: id, eventType: type, eventTime: t, isPendingSync: false);
WorkSession _pending(String id, String type, DateTime t) =>
    WorkSession(id: id, eventType: type, eventTime: t, isPendingSync: true);

final _shift = DateTime.utc(2026, 9, 30, 8, 23, 45);
final _break = DateTime.utc(2026, 9, 30, 11, 2, 10);

void main() {
  late List<ActiveTracker> server;
  Object? fetchError;
  var fetchCalls = 0;

  WorkLogReconciler make(_Repo repo) => WorkLogReconciler(
    repo: repo,
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
      server = trackersFromWire([attendanceWorkingJson, cantiereJson]);
      final repo = _Repo([]);
      await make(repo).reconcile();

      expect(repo.sessions.map((s) => s.eventType), ['ingresso']);
      expect(repo.sessions.single.eventTime, DateTime.utc(2026, 9, 30, 8, 23, 45, 123, 456));
      expect(repo.sessions.single.notes, reconciledOrphanMarker);
      expect(deriveShiftState(repo.sessions).isOnShift, isTrue);
    });

    test('OnBreak: backfills ingresso AND pausa so local == OnBreak', () async {
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
