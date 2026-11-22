// dart format width=100
import '../../data/timbratura/punch_snapshot.dart';

/// One tap the server has not answered yet (a pending outbox row): `ingresso | pausa | ripresa |
/// fine` at the instant the technician made it.
class PunchTap {
  const PunchTap(this.type, this.atUtc);
  final String type;
  final DateTime atUtc;
}

/// The shift as the Timbra screen shows it.
class PunchProjection {
  const PunchProjection({
    required this.isOnShift,
    required this.isOnPause,
    this.shiftStartTime,
    this.pauseStartTime,
  });

  final bool isOnShift;
  final bool isOnPause;
  final DateTime? shiftStartTime;
  final DateTime? pauseStartTime;
}

/// The state the phone shows: the server's last [snapshot] with the [pending] taps replayed on
/// top, oldest first. Null when there is no snapshot yet (the caller keeps showing the local log).
///
/// It mirrors what the server will do with each tap, so the screen answers instantly and the
/// server's reply confirms it instead of replacing it with a surprise:
/// - a clock-in on a running shift changes nothing (the server answers NoOp), keeping the real start;
/// - a break while not clocked in, a resume while not on a break, a clock-out while idle: nothing;
/// - a tap older than the head of the server's timeline is superseded: the server will refuse it,
///   so it is not shown (a tap exactly at the head is kept: an end and a start may coincide).
/// Pure: no I/O, no clock.
PunchProjection? projectPunchState(PunchSnapshot? snapshot, List<PunchTap> pending) {
  if (snapshot == null) return null;

  var onShift = snapshot.status != PunchStatus.idle;
  var onPause = snapshot.status == PunchStatus.onBreak;
  DateTime? shiftStart = onShift ? snapshot.shiftStartedAtUtc : null;
  DateTime? pauseStart = onPause ? snapshot.breakStartedAtUtc : null;

  final ordered = [...pending]..sort((a, b) => a.atUtc.compareTo(b.atUtc));
  for (final tap in ordered) {
    final head = snapshot.headAtUtc;
    if (head != null && tap.atUtc.isBefore(head)) continue;

    switch (tap.type) {
      case 'ingresso':
        if (!onShift) {
          onShift = true;
          shiftStart = tap.atUtc;
        }
      case 'pausa':
        if (onShift && !onPause) {
          onPause = true;
          pauseStart = tap.atUtc;
        }
      case 'ripresa':
        if (onPause) {
          onPause = false;
          pauseStart = null;
        }
      case 'fine':
        if (onShift) {
          onShift = false;
          onPause = false;
          shiftStart = null;
          pauseStart = null;
        }
    }
  }

  return PunchProjection(
    isOnShift: onShift,
    isOnPause: onPause,
    shiftStartTime: shiftStart,
    pauseStartTime: pauseStart,
  );
}
