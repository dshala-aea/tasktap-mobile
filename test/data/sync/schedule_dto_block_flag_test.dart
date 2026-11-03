import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

/// The two leaves a multi-day plan puts on a schedule: whether the day belongs to a plan rather
/// than to a job scheduled on its own, and the absence request a materialised absence came from.
///
/// Both are read defensively. An older backend sends neither key, and the honest reading of a row
/// written before they existed is "not occupied, no absence request" — the behaviour of every
/// build before this one. Guessing the other way would hide the edit affordance on every ordinary
/// day, or claim an absence request for a job.
void main() {
  Map<String, dynamic> json({
    Object? isBlockOccupied = #absent,
    Object? absenceRequestId = #absent,
  }) => {
    'id': 's1',
    'tenantId': 'tenant1',
    'createdAt': '2026-11-03T00:00:00Z',
    'activityDate': '2026-11-03T00:00:00Z',
    'timeStart': '08:00:00',
    'timeEnd': '17:00:00',
    'userId': 'u1',
    'statusId': 1,
    'locationId': 'loc-1',
    'allDay': false,
    'title': 'Cantiere',
    'description': '',
    if (isBlockOccupied != #absent) 'isBlockOccupied': isBlockOccupied,
    if (absenceRequestId != #absent) 'absenceRequestId': absenceRequestId,
  };

  group('ScheduleDto.isBlockOccupied', () {
    test('parses a day an occupancy row reserves', () {
      expect(ScheduleDto.fromJson(json(isBlockOccupied: true)).isBlockOccupied, isTrue);
    });

    test('a normal job reads as not occupied', () {
      expect(ScheduleDto.fromJson(json(isBlockOccupied: false)).isBlockOccupied, isFalse);
    });

    // An older backend does not send the key at all. Reading it true would lock every ordinary
    // day; false is the behaviour every build before the flag had.
    test('is false when the key is absent (older backend)', () {
      expect(ScheduleDto.fromJson(json()).isBlockOccupied, isFalse);
    });

    test('is false when the server sends an explicit null', () {
      expect(ScheduleDto.fromJson(json(isBlockOccupied: null)).isBlockOccupied, isFalse);
    });
  });

  group('ScheduleDto.absenceRequestId', () {
    test('parses the absence request a materialised absence came from', () {
      expect(
        ScheduleDto.fromJson(json(absenceRequestId: 'req-1')).absenceRequestId,
        'req-1',
      );
    });

    test('is null when the key is absent (older backend)', () {
      expect(ScheduleDto.fromJson(json()).absenceRequestId, isNull);
    });

    test('is null when the server sends an explicit null', () {
      expect(ScheduleDto.fromJson(json(absenceRequestId: null)).absenceRequestId, isNull);
    });

    // A multi-day block is not an absence, and an ordinary job has no request either.
    test('an occupied day carries no absence request id', () {
      expect(ScheduleDto.fromJson(json(isBlockOccupied: true)).absenceRequestId, isNull);
    });
  });
}
