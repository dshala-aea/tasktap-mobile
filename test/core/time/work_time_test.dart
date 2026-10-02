import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/work_time.dart';

void main() {
  group('parseTimeSpan', () {
    test('accepted shapes', () {
      expect(parseTimeSpan('08:00:00'), const Duration(hours: 8));
      expect(parseTimeSpan('8:05'), const Duration(hours: 8, minutes: 5));
      expect(
        parseTimeSpan('20:02:30.1234567'),
        const Duration(hours: 20, minutes: 2, seconds: 30),
      );
      expect(
        parseTimeSpan('1.02:03:04'),
        const Duration(hours: 26, minutes: 3, seconds: 4),
      );
      expect(parseTimeSpan('00:00:00'), Duration.zero);
    });

    test('rejects null, empty, non-string, malformed, timestamps', () {
      for (final bad in <Object?>[
        null,
        '',
        'abc',
        '25:99:99',
        '8',
        '2026-09-30T08:23:45Z',
        42,
        '-08:00:00',
        '08:60:00',
        '08:00:60',
        '24:00:00',
        '08:00:00.',
      ]) {
        expect(parseTimeSpan(bad), isNull, reason: '$bad');
      }
    });
  });

  group('formatTimeSpan', () {
    test('values', () {
      expect(formatTimeSpan(const Duration(hours: 8, minutes: 5)), '08:05:00');
      expect(
        formatTimeSpan(const Duration(hours: 23, minutes: 59, seconds: 59)),
        '23:59:59',
      );
      expect(formatTimeSpan(const Duration(hours: 24)), '1.00:00:00');
      expect(
        formatTimeSpan(const Duration(hours: 26, minutes: 3, seconds: 4)),
        '1.02:03:04',
      );
      expect(
        formatTimeSpan(const Duration(hours: 1, milliseconds: 999)),
        '01:00:00',
      );
    });

    test('negative throws', () {
      expect(
        () => formatTimeSpan(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('round trip', () {
      const table = <Duration>[
        Duration.zero,
        Duration(seconds: 1),
        Duration(minutes: 1),
        Duration(hours: 1),
        Duration(hours: 8),
        Duration(hours: 8, minutes: 5),
        Duration(hours: 12, minutes: 30, seconds: 15),
        Duration(hours: 20, minutes: 2, seconds: 30),
        Duration(hours: 23, minutes: 59, seconds: 59),
        Duration(hours: 24),
        Duration(hours: 26),
        Duration(days: 3, hours: 4, minutes: 5, seconds: 6),
      ];
      for (final d in table) {
        expect(parseTimeSpan(formatTimeSpan(d)), d, reason: '$d');
      }
    });
  });

  group('combineWorkDate', () {
    test('utc date plus time', () {
      final r = combineWorkDate(
        DateTime.utc(2026, 8, 31),
        const Duration(hours: 8),
      );
      expect(r, DateTime.utc(2026, 8, 31, 8));
      expect(r.isUtc, isTrue);
    });

    test('local-flagged date gives the identical value', () {
      final r = combineWorkDate(
        DateTime(2026, 8, 31),
        const Duration(hours: 8),
      );
      expect(r, DateTime.utc(2026, 8, 31, 8));
      expect(r.isUtc, isTrue);
    });

    test('no DST shift across the Rome autumn change', () {
      expect(
        combineWorkDate(DateTime.utc(2026, 10, 25), const Duration(hours: 3)),
        DateTime.utc(2026, 10, 25, 3),
      );
    });

    test('26 h rolls to next day 02:00', () {
      expect(
        combineWorkDate(DateTime.utc(2026, 8, 31), const Duration(hours: 26)),
        DateTime.utc(2026, 9, 1, 2),
      );
    });
  });
}
