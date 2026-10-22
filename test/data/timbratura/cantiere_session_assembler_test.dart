// Unit tests for CantiereSessionAssembler.
//
// Mirrors timbra_session_assembler_test.dart's coverage for the cantiere ('ingresso'/'uscita')
// vocabulary, plus the site-context carry-through (cantiereId/customerId/ticketId/description)
// that the personal-timbra assembler doesn't need.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_assembler.dart';

CantierePunche _cp(
  String id,
  String type,
  DateTime time, {
  String? cantiereId,
  String? customerId,
  String? ticketId,
  String? description,
  double? latitude,
  double? longitude,
  String? safetyNotes,
  double? departureLatitude,
  double? departureLongitude,
}) => CantierePunche(
  id: id,
  eventType: type,
  eventTime: time,
  isPendingSync: true,
  cantiereId: cantiereId,
  customerId: customerId,
  ticketId: ticketId,
  description: description,
  latitude: latitude,
  longitude: longitude,
  safetyNotes: safetyNotes,
  departureLatitude: departureLatitude,
  departureLongitude: departureLongitude,
);

void main() {
  group('assembleCantiereIntervals', () {
    test('empty events → empty intervals', () {
      expect(assembleCantiereIntervals([]), isEmpty);
    });

    test('ingresso only → one active interval carrying its site context', () {
      final t = DateTime.utc(2026, 6, 23, 8);
      final intervals = assembleCantiereIntervals([
        _cp('id-1', 'ingresso', t, cantiereId: 'cant-1', customerId: 'cust-1', ticketId: 'tick-1'),
      ]);
      expect(intervals.length, 1);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].cantiereId, 'cant-1');
      expect(intervals[0].customerId, 'cust-1');
      expect(intervals[0].ticketId, 'tick-1');
      expect(intervals[0].startTime, t);
      expect(intervals[0].endTime, isNull);
    });

    test('ingresso → uscita → one closed interval', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final intervals = assembleCantiereIntervals([
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('id-2', 'uscita', t2),
      ]);
      expect(intervals.length, 1);
      expect(intervals[0].clientId, 'id-1');
      expect(intervals[0].startTime, t1);
      expect(intervals[0].endTime, t2);
    });

    test('description carried from the opener', () {
      final t = DateTime.utc(2026, 6, 23, 8);
      final intervals = assembleCantiereIntervals([
        _cp(
          'id-1',
          'ingresso',
          t,
          cantiereId: 'cant-1',
          customerId: 'cust-1',
          description: 'sostituzione pompa',
        ),
      ]);
      expect(intervals[0].description, 'sostituzione pompa');
    });

    test('GPS position carried from the opener, ignored on uscita', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);
      final intervals = assembleCantiereIntervals([
        _cp(
          'id-1',
          'ingresso',
          t1,
          cantiereId: 'cant-1',
          customerId: 'cust-1',
          latitude: 45.4654,
          longitude: 9.1859,
        ),
        _cp('id-2', 'uscita', t2, latitude: 46.0, longitude: 10.0),
      ]);
      expect(intervals[0].latitude, 45.4654);
      expect(intervals[0].longitude, 9.1859);
    });

    test('uscita with no open ingresso → ignored, no interval', () {
      final t = DateTime.utc(2026, 6, 23, 8);
      expect(assembleCantiereIntervals([_cp('id-1', 'uscita', t)]), isEmpty);
    });

    test('ingresso missing cantiereId/customerId (malformed row) → defensively ignored', () {
      final t = DateTime.utc(2026, 6, 23, 8);
      expect(assembleCantiereIntervals([_cp('id-1', 'ingresso', t)]), isEmpty);
    });

    test('two full visits produce two closed intervals, each with its own context', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 12);
      final t3 = DateTime.utc(2026, 6, 23, 13);
      final t4 = DateTime.utc(2026, 6, 23, 17);
      final intervals = assembleCantiereIntervals([
        _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
        _cp('id-2', 'uscita', t2),
        _cp('id-3', 'ingresso', t3, cantiereId: 'cant-2', customerId: 'cust-2'),
        _cp('id-4', 'uscita', t4),
      ]);
      expect(intervals.length, 2);
      expect(intervals[0].cantiereId, 'cant-1');
      expect(intervals[1].cantiereId, 'cant-2');
    });

    test('clientId is stable (equals opener event id)', () {
      final t = DateTime.utc(2026, 6, 23, 9);
      final intervals = assembleCantiereIntervals([
        _cp('stable-uuid-abc', 'ingresso', t, cantiereId: 'cant-1', customerId: 'cust-1'),
      ]);
      expect(intervals[0].clientId, 'stable-uuid-abc');
    });

    group('the clock-out screen\'s own fields', () {
      final t1 = DateTime.utc(2026, 6, 23, 8);
      final t2 = DateTime.utc(2026, 6, 23, 17);

      test('safety note and departure GPS are carried from the uscita', () {
        final intervals = assembleCantiereIntervals([
          _cp('id-1', 'ingresso', t1, cantiereId: 'cant-1', customerId: 'cust-1'),
          _cp(
            'id-2',
            'uscita',
            t2,
            safetyNotes: 'area recintata',
            departureLatitude: 45.4660,
            departureLongitude: 9.1880,
          ),
        ]);
        expect(intervals[0].safetyNotes, 'area recintata');
        expect(intervals[0].departureLatitude, 45.4660);
        expect(intervals[0].departureLongitude, 9.1880);
      });

      test('a description typed on leaving wins over the arrival note — the online end route '
          'overwrites the row with it, so an offline close must produce the same record', () {
        final intervals = assembleCantiereIntervals([
          _cp(
            'id-1',
            'ingresso',
            t1,
            cantiereId: 'cant-1',
            customerId: 'cust-1',
            description: 'arrivo in cantiere',
          ),
          _cp('id-2', 'uscita', t2, description: 'sostituito il quadro'),
        ]);
        expect(intervals[0].description, 'sostituito il quadro');
      });

      test('an uscita with no note keeps the arrival description', () {
        final intervals = assembleCantiereIntervals([
          _cp(
            'id-1',
            'ingresso',
            t1,
            cantiereId: 'cant-1',
            customerId: 'cust-1',
            description: 'arrivo in cantiere',
          ),
          _cp('id-2', 'uscita', t2),
        ]);
        expect(intervals[0].description, 'arrivo in cantiere');
      });

      test('a still-open interval carries no clock-out fields, even if its opener has the columns '
          'set (they belong to the uscita only)', () {
        final intervals = assembleCantiereIntervals([
          _cp(
            'id-1',
            'ingresso',
            t1,
            cantiereId: 'cant-1',
            customerId: 'cust-1',
            safetyNotes: 'nota impossibile',
          ),
        ]);
        expect(intervals[0].endTime, isNull);
        expect(intervals[0].safetyNotes, isNull);
      });
    });
  });
}
