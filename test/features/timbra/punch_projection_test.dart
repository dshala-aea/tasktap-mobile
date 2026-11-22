import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/punch_snapshot.dart';
import 'package:tasktap_mobile/features/timbra/punch_projection.dart';

/// The phone never infers the state of the shift: it shows the server's last answer, with the taps
/// the server has not answered yet laid on top (EPIC 29 design §6). A pure function, no I/O.
void main() {
  DateTime at(int h, [int m = 0]) => DateTime.utc(2026, 11, 22, h, m);
  PunchTap tap(String type, DateTime when) => PunchTap(type, when);

  PunchProjection project(PunchSnapshot s, List<PunchTap> t) => projectPunchState(s, t)!;

  PunchSnapshot idle({DateTime? head}) => PunchSnapshot(status: PunchStatus.idle, headAtUtc: head);
  PunchSnapshot working(DateTime since, {DateTime? head}) =>
      PunchSnapshot(status: PunchStatus.working, shiftStartedAtUtc: since, headAtUtc: head);
  PunchSnapshot onBreak(DateTime since, DateTime breakSince, {DateTime? head}) => PunchSnapshot(
    status: PunchStatus.onBreak,
    shiftStartedAtUtc: since,
    breakStartedAtUtc: breakSince,
    headAtUtc: head,
  );

  group('the server state alone', () {
    test('idle', () {
      final p = project(idle(), const []);
      expect(p.isOnShift, isFalse);
      expect(p.isOnPause, isFalse);
    });

    test('working carries when the shift started', () {
      final p = project(working(at(8, 5)), const []);
      expect(p.isOnShift, isTrue);
      expect(p.isOnPause, isFalse);
      expect(p.shiftStartTime, at(8, 5));
    });

    test('on break carries both instants', () {
      final p = project(onBreak(at(8), at(12)), const []);
      expect(p.isOnShift, isTrue);
      expect(p.isOnPause, isTrue);
      expect(p.shiftStartTime, at(8));
      expect(p.pauseStartTime, at(12));
    });
  });

  group('taps the server has not answered yet are replayed on top', () {
    test('a pending clock-in starts a shift the server does not know yet', () {
      final p = project(idle(), [tap('ingresso', at(8))]);
      expect(p.isOnShift, isTrue);
      expect(p.shiftStartTime, at(8));
    });

    test('a pending break and resume on a running shift end back at working', () {
      final p = project(working(at(8)), [tap('pausa', at(12)), tap('ripresa', at(12, 30))]);
      expect(p.isOnShift, isTrue);
      expect(p.isOnPause, isFalse);
    });

    test('a pending break puts a working shift on break', () {
      final p = project(working(at(8)), [tap('pausa', at(12))]);
      expect(p.isOnPause, isTrue);
      expect(p.pauseStartTime, at(12));
    });

    test('a pending clock-out ends the shift, closing a break with it', () {
      final p = project(onBreak(at(8), at(12)), [tap('fine', at(13))]);
      expect(p.isOnShift, isFalse);
      expect(p.isOnPause, isFalse);
    });

    test('taps are replayed oldest first whatever order they arrive in', () {
      final p = project(idle(), [tap('fine', at(15)), tap('ingresso', at(8))]);
      expect(p.isOnShift, isFalse);
    });
  });

  group('what the server would refuse or ignore changes nothing', () {
    test('a clock-in on a shift that already runs keeps the original start', () {
      final p = project(working(at(8)), [tap('ingresso', at(9))]);
      expect(p.shiftStartTime, at(8));
    });

    test('a break while not clocked in is ignored', () {
      final p = project(idle(), [tap('pausa', at(12))]);
      expect(p.isOnShift, isFalse);
      expect(p.isOnPause, isFalse);
    });

    test('a resume while not on a break is ignored', () {
      final p = project(working(at(8)), [tap('ripresa', at(12))]);
      expect(p.isOnPause, isFalse);
      expect(p.isOnShift, isTrue);
    });

    test('a clock-out while idle is ignored', () {
      expect(project(idle(), [tap('fine', at(17))]).isOnShift, isFalse);
    });

    test('a tap older than the head of the server timeline is superseded and ignored', () {
      final p = project(working(at(8), head: at(10)), [tap('fine', at(9))]);
      expect(p.isOnShift, isTrue, reason: 'the server already holds a later event: it would reject this one');
    });

    test('a tap exactly at the head is still replayed (an end and a start may coincide)', () {
      final p = project(working(at(8), head: at(10)), [tap('fine', at(10))]);
      expect(p.isOnShift, isFalse);
    });
  });

  test('without a snapshot there is nothing to project (the caller keeps the local log)', () {
    expect(projectPunchState(null, [tap('ingresso', at(8))]), isNull);
  });
}
