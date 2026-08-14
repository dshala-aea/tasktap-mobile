// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart';

/// The dashboard's running clocks.
///
/// Two things here are worth pinning, and "it renders" is neither.
///
/// The elapsed time has to be right. It is computed on the device from `startedAtUtc`, and the
/// classic way to get it wrong is to read the server's instant as local time — on an Italian
/// summer afternoon that is two hours of work nobody did, on a number a customer is invoiced from.
///
/// And every running tracker has to appear. Attendance, cantiere and ticket time are three
/// independent clocks that can all run at once; a panel showing one hides exactly the timer that
/// gets left going overnight.
void main() {
  group('ActiveTracker', () {
    test('reads the start instant as UTC, whatever the device thinks the time is', () {
      final tracker = ActiveTracker.fromJson(const {
        'kind': 'Attendance',
        'id': 'wl-1',
        'startedAtUtc': '2026-08-14T06:30:00',
        'label': null,
        'entityId': null,
      });

      expect(tracker.startedAtUtc.isUtc, isTrue);
      expect(
        tracker.elapsedAt(DateTime.utc(2026, 8, 14, 8, 0)),
        const Duration(hours: 1, minutes: 30),
      );
    });

    test('an explicit Z offset means the same instant', () {
      final tracker = ActiveTracker.fromJson(const {
        'kind': 'Attendance',
        'id': 'wl-1',
        'startedAtUtc': '2026-08-14T06:30:00Z',
      });

      expect(tracker.elapsedAt(DateTime.utc(2026, 8, 14, 8, 0)),
          const Duration(hours: 1, minutes: 30));
    });

    /// An explicit offset is a zone too.
    ///
    /// The end-of-string anchor in the zone check was written `\$` inside a raw string, which
    /// matches a literal dollar sign rather than the end of the input — so an offset went
    /// undetected, a Z was appended to a string that already had a zone, and parsing threw.
    test('an offset-bearing instant parses and means what it says', () {
      final tracker = ActiveTracker.fromJson(const {
        'kind': 'Cantiere',
        'id': 'cw-1',
        'startedAtUtc': '2026-08-14T08:30:00+02:00',
      });

      // 08:30+02:00 is 06:30 UTC.
      expect(tracker.startedAtUtc, DateTime.utc(2026, 8, 14, 6, 30));
      expect(tracker.elapsedAt(DateTime.utc(2026, 8, 14, 7, 0)), const Duration(minutes: 30));
    });

    /// Phone clocks drift. A start instant slightly in the future must not read as a countdown.
    test('a start in the future floors at zero', () {
      final tracker = ActiveTracker.fromJson(const {
        'kind': 'Ticket',
        'id': 'tw-1',
        'startedAtUtc': '2026-08-14T08:00:05Z',
      });

      expect(tracker.elapsedAt(DateTime.utc(2026, 8, 14, 8, 0)), Duration.zero);
    });

    test('each kind keeps what it is against', () {
      final cantiere = ActiveTracker.fromJson(const {
        'kind': 'Cantiere',
        'id': 'cw-1',
        'startedAtUtc': '2026-08-14T08:00:00Z',
        'label': 'Cantiere Via Roma',
        'entityId': 'c-1',
      });

      expect(cantiere.kind, ActiveTrackerKind.cantiere);
      expect(cantiere.label, 'Cantiere Via Roma');
      expect(cantiere.entityId, 'c-1');
    });

    /// Attendance is against the day, not a thing — a label would have to be invented.
    test('attendance names nothing', () {
      final attendance = ActiveTracker.fromJson(const {
        'kind': 'Attendance',
        'id': 'wl-1',
        'startedAtUtc': '2026-08-14T08:00:00Z',
      });

      expect(attendance.kind, ActiveTrackerKind.attendance);
      expect(attendance.label, isNull);
      expect(attendance.entityId, isNull);
    });

    test('an unfamiliar kind still produces a usable row', () {
      final unknown = ActiveTracker.fromJson(const {
        'kind': 'SomethingNewer',
        'id': 'x-1',
        'startedAtUtc': '2026-08-14T08:00:00Z',
      });

      expect(unknown.elapsedAt(DateTime.utc(2026, 8, 14, 9)), const Duration(hours: 1));
    });
  });

  group('formatElapsed', () {
    test('drops the hour segment below an hour', () {
      expect(formatElapsed(const Duration(minutes: 5, seconds: 7)), '05:07');
    });

    test('keeps hours unpadded past the hour', () {
      expect(formatElapsed(const Duration(minutes: 90)), '1:30:00');
    });

    /// A shift left running overnight reads as its real length, not a wrapped clock.
    test('does not wrap at 24 hours', () {
      expect(formatElapsed(const Duration(hours: 26)), '26:00:00');
    });
  });
}
