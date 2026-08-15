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

WorkSession _ws(String id, String type, DateTime time) =>
    WorkSession(id: id, eventType: type, eventTime: time, isPendingSync: true);

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
  });
}
