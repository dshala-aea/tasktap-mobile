// Unit tests for TimbraSessionAssembler.
//
// Verifies:
// - Empty session list → no intervals
// - ingresso alone → one active interval (endTime null)
// - ingresso → fine → one closed interval
// - ingresso → pausa → one closed interval
// - ingresso → pausa → ripresa → two intervals (first closed, second active)
// - ingresso → pausa → ripresa → fine → two intervals (both closed)
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
      final intervals = assembleIntervals([_ws('id-1', 'ingresso', t1), _ws('id-2', 'fine', t2)]);
      expect(intervals.length, 1);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
    });

    test('ingresso → pausa → one closed interval', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 12);
      final intervals = assembleIntervals([_ws('id-1', 'ingresso', t1), _ws('id-2', 'pausa', t2)]);
      expect(intervals.length, 1);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
    });

    test('ingresso → pausa → ripresa → two intervals, second active', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 12);
      final t3 = DateTime.utc(2026, 6, 23, 13);
      final intervals = assembleIntervals([
        _ws('id-1', 'ingresso', t1),
        _ws('id-2', 'pausa', t2),
        _ws('id-3', 'ripresa', t3),
      ]);
      expect(intervals.length, 2);
      // First interval: ingresso→pausa
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
      // Second interval: ripresa→open
      expect(intervals[1].clientId, 'id-3');
      expect(intervals[1].startTime, t3);
      expect(intervals[1].endTime, isNull);
    });

    test('ingresso → pausa → ripresa → fine → two closed intervals', () {
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
      expect(intervals.length, 2);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
      expect(intervals[1].clientId, 'id-3');
      expect(intervals[1].startTime, t3);
      expect(intervals[1].endTime, t4);
    });

    test('clientId is stable (equals opener event id)', () {
      final t = DateTime.utc(2026, 6, 23, 9);
      final intervals = assembleIntervals([_ws('stable-uuid-abc', 'ingresso', t)]);
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

      test("closing event's own GPS is ignored — only the opener's position is carried", () {
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
      });

      test('each interval after a ripresa carries its own opener\'s position, not the first\'s', () {
        final t1 = DateTime.utc(2026, 6, 23, 8);
        final t2 = DateTime.utc(2026, 6, 23, 12);
        final t3 = DateTime.utc(2026, 6, 23, 13);
        final intervals = assembleIntervals([
          _ws('id-1', 'ingresso', t1, latitude: 45.0, longitude: 9.0),
          _ws('id-2', 'pausa', t2),
          _ws('id-3', 'ripresa', t3, latitude: 45.5, longitude: 9.5),
        ]);
        expect(intervals.length, 2);
        expect(intervals[0].latitude, 45.0);
        expect(intervals[1].latitude, 45.5);
        expect(intervals[1].longitude, 9.5);
      });
    });

    // ── GPS accuracy (item 10c) ────────────────────────────────────────────────
    //
    // Same "opener only" carry-through as latitude/longitude — see WorkInterval.gpsAccuracyMeters.

    group('GPS accuracy (opener event only)', () {
      test('ingresso with accuracy → interval carries it', () {
        final t = DateTime.utc(2026, 6, 23, 8);
        final intervals = assembleIntervals([
          _ws('id-1', 'ingresso', t, latitude: 45.4654, longitude: 9.1859, gpsAccuracyMeters: 12.0),
        ]);
        expect(intervals[0].gpsAccuracyMeters, 12.0);
      });

      test('ingresso with no accuracy reported → interval accuracy is null', () {
        final t = DateTime.utc(2026, 6, 23, 8);
        final intervals = assembleIntervals([_ws('id-1', 'ingresso', t)]);
        expect(intervals[0].gpsAccuracyMeters, isNull);
      });
    });
  });
}
