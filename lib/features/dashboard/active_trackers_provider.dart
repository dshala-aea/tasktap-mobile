// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';
import '../../data/local/app_database.dart' show WorkSession;
import '../../data/timbratura/work_session_repository.dart' show reconciledOrphanMarker;
import '../../data/worklogs/active_tracker_api_client.dart';
import '../timbra/timbra_providers.dart';

/// What the signed-in user is currently tracking.
///
/// Polled rather than pushed, and only once a minute: the elapsed time is computed on the device
/// from `startedAtUtc`, so the display stays correct between fetches without asking anything. What
/// a refetch actually catches is a *stop* performed elsewhere — the office web, another device.
/// A minute of showing a timer that has already stopped is a small wrong; a request per second to
/// avoid it, from a phone on mobile data in a basement, is not.
/// autoDispose with an explicit cancel, rather than a bare `Stream.periodic`: a poll that outlives
/// the screen keeps a timer — and a request — alive after the user has left, and in a widget test
/// it fails the tree teardown outright ("A Timer is still pending even after the widget tree was
/// disposed"). The dashboard is the only listener; when it goes, so does the polling.
final activeTrackersProvider = StreamProvider.autoDispose<List<ActiveTracker>>((ref) {
  final client = ActiveTrackerApiClient(ref.watch(dioProvider));
  final controller = StreamController<List<ActiveTracker>>();
  Timer? timer;
  var answered = false;

  Future<void> poll() async {
    try {
      final trackers = await client.getActive();
      if (!controller.isClosed) {
        answered = true;
        controller.add(trackers);
      }
    } catch (_) {
      // A LATER failure is not worth blanking a running timer over: the elapsed time on screen is
      // computed locally and stays right, so keep the last answer and try again next minute.
      //
      // The FIRST failure is different. Saying nothing leaves the provider loading forever, and
      // the dashboard shows a spinner that never resolves — which is what a technician with no
      // signal would stare at. An empty list falls through to the calendar view instead.
      if (!answered && !controller.isClosed) {
        answered = true;
        controller.add(const []);
      }
    }
  }

  unawaited(poll());
  timer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(poll()));

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// A clock that ticks once a second, for widgets showing a running duration.
///
/// One timer for the whole screen rather than one per card, and it stops the moment nothing is
/// listening — an idle dashboard does no work.
final nowProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final controller = StreamController<DateTime>();

  controller.add(DateTime.now().toUtc());
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!controller.isClosed) controller.add(DateTime.now().toUtc());
  });

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

/// `H:MM:SS`, or `MM:SS` under an hour — a leading `0:` on a five-minute job is noise.
String formatElapsed(Duration elapsed) {
  final total = elapsed.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// What to show as running: the server's list, corrected by what this device knows for certain.
///
/// Attendance has two sources and they answer different questions:
///
/// - The SERVER's row is the authority for a clock started, paused or stopped on ANOTHER device
///   (the office web, a second handset). It also carries `state` (Working | OnBreak).
/// - The LOCAL timbratura state is instant and correct offline, and knows about punches the server
///   has not received yet.
///
/// The rule: local wins only while it holds events the server has not seen (pending sync) — that
/// is the technician's own fresh punch, which must show at once and must not be overwritten by a
/// stale server view. Otherwise the server's row wins, so a clock started elsewhere appears here
/// even though this phone never punched. With no server row (offline, or nothing running) a
/// locally running shift is still shown.
///
/// One more guard closes a race: right after a local, already-synced clock-out the server list can
/// still show the old shift until the next refetch. A server row that began at or before this
/// device's last local 'fine' is that stale view and is hidden; a shift that began AFTER the
/// stop is a new one, started elsewhere, and is shown.
///
/// The local row reuses the server's id when there is one, so the two never render as two clocks.
/// Cantiere and ticket clocks have no local mirror and always come from the server.
final visibleTrackersProvider = Provider.autoDispose<List<ActiveTracker>>((ref) {
  final remote = ref.watch(activeTrackersProvider).valueOrNull ?? const <ActiveTracker>[];
  final timbra = ref.watch(timbraStateProvider);
  final sessions = ref.watch(todaySessionsProvider).valueOrNull ?? const <WorkSession>[];

  final others = remote.where((t) => t.kind != ActiveTrackerKind.attendance).toList();
  final serverAttendance = remote.where((t) => t.kind == ActiveTrackerKind.attendance).firstOrNull;

  final hasUnsynced = sessions.any((s) => s.isPendingSync && s.notes != reconciledOrphanMarker);

  ActiveTracker? localRow() {
    if (!timbra.isOnShift || timbra.shiftStartTime == null) return null;
    final onBreak = timbra.isOnPause;
    return ActiveTracker(
      kind: ActiveTrackerKind.attendance,
      id: serverAttendance?.id ?? 'local-attendance',
      // Same convention as the server row: on a break the timer counts the break.
      startedAtUtc: (onBreak ? timbra.pauseStartTime ?? timbra.shiftStartTime! : timbra.shiftStartTime!)
          .toUtc(),
      shiftStartedAtUtc: timbra.shiftStartTime!.toUtc(),
      state: onBreak ? ActiveTrackerState.onBreak : ActiveTrackerState.working,
      label: serverAttendance?.label,
      entityId: serverAttendance?.entityId,
    );
  }

  ActiveTracker? attendance;
  if (hasUnsynced) {
    attendance = localRow();
  } else if (serverAttendance != null && !_supersededByLocalStop(serverAttendance, sessions)) {
    attendance = serverAttendance;
  } else {
    attendance = localRow();
  }

  return [?attendance, ...others];
});

/// True when this device stopped the day AFTER the server's open shift began — the server row is
/// then a stale view that has not caught up with the local clock-out yet.
bool _supersededByLocalStop(ActiveTracker server, List<WorkSession> sessions) {
  DateTime? lastFine;
  for (final s in sessions) {
    if (s.eventType == 'fine') lastFine = s.eventTime;
  }
  if (lastFine == null) return false;
  final shiftStart = server.shiftStartedAtUtc ?? server.startedAtUtc;
  return !shiftStart.isAfter(lastFine);
}
