// Unit tests for TimbraSessionAssembler.
//
// Verifies:
// - Empty session list → no intervals
// - ingresso alone → one active interval (endTime null)
// - ingresso → fine → one closed interval
// - ingresso → pausa → one closed ordinary interval; the open break is not sent until it closes
// - ingresso → pausa → ripresa → ordinary, break, ordinary (break closed, second ordinary active)
// - ingresso → pausa → ripresa → fine → ordinary, break, ordinary (all closed)
// - pausa is its own interval: a break is sent to the server, not left as an invisible gap
// - clientId is stable (equals opener event id)
// - startTime is UTC

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_session_assembler.dart';

WorkSession _ws(
  String id,
  String type,
  DateTime time, {
  double? latitude,
  double? longitude,
  double? gpsAccuracyMeters,
}) => WorkSession(
  id: id,
  eventType: type,
  eventTime: time,
  isPendingSync: true,
  latitude: latitude,
  longitude: longitude,
  gpsAccuracyMeters: gpsAccuracyMeters,
);

void main() {
  group('assembleIntervals', () {
    test('empty sessions → empty intervals', () {
      expect(assembleIntervals([]), isEmpty);
    });

    test('ingresso only → one active interval (endTime null)', () {
      final t = DateTime.utc(2026, 6, 23, 8);
      final intervals = assembleIntervals([_ws('id-1', 'ingresso', t)]);
      expect(intervals.length, 1);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t);
      expect(intervals[0].endTime, isNull);
    });

    test('ingresso → fine → one closed interval', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final intervals = assembleIntervals([
        _ws('id-1', 'ingresso', t1),
        _ws('id-2', 'fine', t2),
      ]);
      expect(intervals.length, 1);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
    });

    test(
      'ingresso → pausa → only the closed ordinary interval; the open break waits',
      () {
        final t1 = DateTime.utc(2026, 6, 23, 8);
        final t2 = DateTime.utc(2026, 6, 23, 12);
        final intervals = assembleIntervals([
          _ws('id-1', 'ingresso', t1),
          _ws('id-2', 'pausa', t2),
        ]);
        expect(intervals.length, 1);
        expect(intervals[0].clientId, 'id-1');
        expect(intervals[0].startTime, t1);
        expect(intervals[0].endTime, t2);
        expect(intervals[0].kind, WorkIntervalKind.ordinary);
      },
    );

    test('ingresso → pausa → ripresa → ordinary, break, ordinary', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 12);
      final t3 = DateTime.utc(2026, 6, 23, 13);
      final intervals = assembleIntervals([
        _ws('id-1', 'ingresso', t1),
        _ws('id-2', 'pausa', t2),
        _ws('id-3', 'ripresa', t3),
      ]);
      expect(intervals.length, 3);
      // First interval: ingresso→pausa
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
      expect(intervals[0].kind, WorkIntervalKind.ordinary);
      // Break: pausa→ripresa, client id is the pausa event
      expect(intervals[1].clientId, 'id-2');
      expect(intervals[1].startTime, t2);
      expect(intervals[1].endTime, t3);
      expect(intervals[1].kind, WorkIntervalKind.breakInterval);
      // Second ordinary interval: ripresa→open
      expect(intervals[2].clientId, 'id-3');
      expect(intervals[2].startTime, t3);
      expect(intervals[2].endTime, isNull);
      expect(intervals[2].kind, WorkIntervalKind.ordinary);
    });

    test(
      'ingresso → pausa → ripresa → fine → ordinary, break, ordinary (all closed)',
      () {
        final t1 = DateTime.utc(2026, 6, 23, 8);
        final t2 = DateTime.utc(2026, 6, 23, 12);
        final t3 = DateTime.utc(2026, 6, 23, 13);
        final t4 = DateTime.utc(2026, 6, 23, 17);
        final intervals = assembleIntervals([
          _ws('id-1', 'ingresso', t1),
          _ws('id-2', 'pausa', t2),
          _ws('id-3', 'ripresa', t3),
          _ws('id-4', 'fine', t4),
        ]);
        expect(intervals.length, 3);
        expect(intervals[0].clientId, 'id-1');
        expect(intervals[0].endTime, t2);
        expect(intervals[0].kind, WorkIntervalKind.ordinary);
        expect(intervals[1].clientId, 'id-2');
        expect(intervals[1].startTime, t2);
        expect(intervals[1].endTime, t3);
        expect(intervals[1].kind, WorkIntervalKind.breakInterval);
        expect(intervals[2].clientId, 'id-3');
        expect(intervals[2].startTime, t3);
        expect(intervals[2].endTime, t4);
        expect(intervals[2].kind, WorkIntervalKind.ordinary);
      },
    );

    test(
      'ending the shift from a break closes the break, with no ordinary interval after it',
      () {
        final t1 = DateTime.utc(2026, 6, 23, 8);
        final t2 = DateTime.utc(2026, 6, 23, 12);
        final t3 = DateTime.utc(2026, 6, 23, 12, 30);
        final intervals = assembleIntervals([
          _ws('id-1', 'ingresso', t1),
          _ws('id-2', 'pausa', t2),
          _ws('id-3', 'fine', t3),
        ]);
        expect(intervals.length, 2);
        expect(intervals[0].clientId, 'id-1');
        expect(intervals[0].endTime, t2);
        expect(intervals[0].kind, WorkIntervalKind.ordinary);
        expect(intervals[1].clientId, 'id-2');
        expect(intervals[1].startTime, t2);
        expect(intervals[1].endTime, t3);
        expect(intervals[1].kind, WorkIntervalKind.breakInterval);
      },
    );

    test(
      'an overnight break stays a gap instead of opening a row the next day collides with',
      () {
        DateTime at(int day, int hour, [int minute = 0]) =>
            DateTime.utc(2026, 6, day, hour, minute);
        DateTime businessDay(DateTime t) =>
            DateTime.utc(t.year, t.month, t.day);

        final intervals = assembleIntervals([
          _ws('in', 'ingresso', at(23, 22)),
          _ws('p', 'pausa', at(23, 23)),
          _ws('r', 'ripresa', at(24, 0, 30)),
          _ws('out', 'fine', at(24, 6)),
        ], businessDateOf: businessDay);

        // The two ordinary intervals are unchanged; the break across midnight is not sent as a
        // break row (the next-day ordinary would collide with an open break row on the server).
        expect(intervals.length, 2);
        expect(
          intervals.every((i) => i.kind == WorkIntervalKind.ordinary),
          isTrue,
        );
        expect(intervals[0].startTime, at(23, 22));
        expect(intervals[0].endTime, at(23, 23));
        expect(intervals[1].startTime, at(24, 0, 30));
        expect(intervals[1].endTime, at(24, 6));
      },
    );

    test(
      'two breaks produce two break intervals, each keyed by its own pausa',
      () {
        final base = DateTime.utc(2026, 6, 23, 8);
        DateTime at(int hours, [int minutes = 0]) =>
            DateTime.utc(2026, 6, 23, hours, minutes);
        final intervals = assembleIntervals([
          _ws('in', 'ingresso', base),
          _ws('p1', 'pausa', at(10)),
          _ws('r1', 'ripresa', at(10, 10)),
          _ws('p2', 'pausa', at(12)),
          _ws('r2', 'ripresa', at(12, 15)),
          _ws('fine', 'fine', at(17)),
        ]);
        expect(intervals.length, 5);
        expect(
          intervals
              .where((i) => i.kind == WorkIntervalKind.breakInterval)
              .map((i) => i.clientId),
          ['p1', 'p2'],
        );
        expect(intervals[1].startTime, at(10));
        expect(intervals[1].endTime, at(10, 10));
        expect(intervals[3].startTime, at(12));
        expect(intervals[3].endTime, at(12, 15));
      },
    );

    test('clientId is stable (equals opener event id)', () {
      final t = DateTime.utc(2026, 6, 23, 9);
      final intervals = assembleIntervals([
        _ws('stable-uuid-abc', 'ingresso', t),
      ]);
      expect(intervals[0].clientId, 'stable-uuid-abc');
    });

    test('startTime is UTC', () {
      final utcTime = DateTime.utc(2026, 6, 23, 7, 30);
      final intervals = assembleIntervals([_ws('id-x', 'ingresso', utcTime)]);
      expect(intervals[0].startTime.isUtc, isTrue);
    });

    test('pausa before ingresso → no interval created', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final intervals = assembleIntervals([_ws('id-1', 'pausa', t1)]);
      expect(intervals, isEmpty);
    });

    test('fine before ingresso → no interval created', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final intervals = assembleIntervals([_ws('id-1', 'fine', t1)]);
      expect(intervals, isEmpty);
    });

    // ── GPS capture (item 10b) ────────────────────────────────────────────────
    //
    // Backend's MobileSessionDto carries a single "GPS at punch time" lat/lng pair per interval,
    // so only the opener's (ingresso/ripresa) position is meaningful — this is what
    // TimbraSyncService reads off WorkInterval and forwards.

    group('GPS position (opener event only)', () {
      test('ingresso with GPS → interval carries that position', () {
        final t = DateTime.utc(2026, 6, 23, 8);
        final intervals = assembleIntervals([
          _ws('id-1', 'ingresso', t, latitude: 45.4654, longitude: 9.1859),
        ]);
        expect(intervals[0].latitude, 45.4654);
        expect(intervals[0].longitude, 9.1859);
      });

      test('ingresso with no GPS → interval position is null', () {
        final t = DateTime.utc(2026, 6, 23, 8);
        final intervals = assembleIntervals([_ws('id-1', 'ingresso', t)]);
        expect(intervals[0].latitude, isNull);
        expect(intervals[0].longitude, isNull);
      });

      test(
        "closing event's own GPS is ignored — only the opener's position is carried",
        () {
          final t1 = DateTime.utc(2026, 6, 23, 8);
          final t2 = DateTime.utc(2026, 6, 23, 17);
          final intervals = assembleIntervals([
            _ws('id-1', 'ingresso', t1, latitude: 45.0, longitude: 9.0),
            // A 'fine' event carrying coordinates would be unusual (PunchNotifier never captures
            // GPS for it), but the assembler must not let it clobber the opener's position anyway.
            _ws('id-2', 'fine', t2, latitude: 46.0, longitude: 10.0),
          ]);
          expect(intervals[0].latitude, 45.0);
          expect(intervals[0].longitude, 9.0);
        },
      );

      test(
        'each ordinary interval after a ripresa carries its own opener\'s position',
        () {
          final t1 = DateTime.utc(2026, 6, 23, 8);
          final t2 = DateTime.utc(2026, 6, 23, 12);
          final t3 = DateTime.utc(2026, 6, 23, 13);
          final intervals = assembleIntervals([
            _ws('id-1', 'ingresso', t1, latitude: 45.0, longitude: 9.0),
            _ws('id-2', 'pausa', t2),
            _ws('id-3', 'ripresa', t3, latitude: 45.5, longitude: 9.5),
          ]);
          expect(intervals.length, 3);
          expect(intervals[0].latitude, 45.0);
          // The break carries no position of its own.
          expect(intervals[1].kind, WorkIntervalKind.breakInterval);
          expect(intervals[1].latitude, isNull);
          expect(intervals[2].latitude, 45.5);
          expect(intervals[2].longitude, 9.5);
        },
      );
    });

    // ── GPS accuracy (item 10c) ────────────────────────────────────────────────
    //
    // Same "opener only" carry-through as latitude/longitude — see WorkInterval.gpsAccuracyMeters.

    group('GPS accuracy (opener event only)', () {
      test('ingresso with accuracy → interval carries it', () {
        final t = DateTime.utc(2026, 6, 23, 8);
        final intervals = assembleIntervals([
          _ws(
            'id-1',
            'ingresso',
            t,
            latitude: 45.4654,
            longitude: 9.1859,
            gpsAccuracyMeters: 12.0,
          ),
        ]);
        expect(intervals[0].gpsAccuracyMeters, 12.0);
      });

      test(
        'ingresso with no accuracy reported → interval accuracy is null',
        () {
          final t = DateTime.utc(2026, 6, 23, 8);
          final intervals = assembleIntervals([_ws('id-1', 'ingresso', t)]);
          expect(intervals[0].gpsAccuracyMeters, isNull);
        },
      );
    });
  });
}
