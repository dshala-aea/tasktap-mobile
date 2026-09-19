// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';
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
/// [activeTrackersProvider] polls once a minute, which is right for catching a stop performed on
/// the office web or another handset — and wrong for the technician's own punch, which took up to
/// sixty seconds to appear on the dashboard and another sixty to disappear. A clock the device
/// itself started should not need a round trip to become visible.
///
/// So attendance is taken from the local timbratura state, which is instant and correct offline,
/// and the server's own attendance row is dropped in its favour. Cantiere and ticket clocks have
/// no local mirror and keep coming from the poll.
///
/// The local row reuses the server's id when there is one, so the two never render as two clocks
/// during the window where both agree.
final visibleTrackersProvider = Provider.autoDispose<List<ActiveTracker>>((ref) {
  final remote = ref.watch(activeTrackersProvider).valueOrNull ?? const <ActiveTracker>[];
  final timbra = ref.watch(timbraStateProvider);

  final others = remote.where((t) => t.kind != ActiveTrackerKind.attendance).toList();

  if (!timbra.isOnShift || timbra.shiftStartTime == null) {
    // Punched out locally: drop the attendance row now rather than after the next poll.
    return others;
  }

  final serverAttendance = remote.where((t) => t.kind == ActiveTrackerKind.attendance).firstOrNull;

  return [
    ActiveTracker(
      kind: ActiveTrackerKind.attendance,
      id: serverAttendance?.id ?? 'local-attendance',
      startedAtUtc: timbra.shiftStartTime!.toUtc(),
      label: serverAttendance?.label,
      entityId: serverAttendance?.entityId,
    ),
    ...others,
  ];
});
