import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';

// Transition dates confirmed against IANA rules:
// Rome: last Sunday of March / October. LA: 2nd Sunday March, 1st Sunday Nov.
// Auckland: last Sunday Sept (forward), 1st Sunday April (back).
void main() {
  final cases = <(String, DateTime, int)>[
    ('Europe/Rome', DateTime.utc(2027, 3, 28), 23),
    ('Europe/Rome', DateTime.utc(2026, 10, 25), 25),
    ('America/Los_Angeles', DateTime.utc(2027, 3, 14), 23),
    ('America/Los_Angeles', DateTime.utc(2026, 11, 1), 25),
    ('Pacific/Auckland', DateTime.utc(2026, 9, 27), 23),
    ('Pacific/Auckland', DateTime.utc(2027, 4, 4), 25),
  ];
  for (final (zone, date, hours) in cases) {
    test('$zone ${date.toIso8601String()} is $hours h and tiles', () {
      final bt = BusinessTime(zone);
      final (s, e) = bt.utcRangeForBusinessDate(date);
      expect(e.difference(s), Duration(hours: hours));
      final prev = DateTime.utc(date.year, date.month, date.day - 1);
      final next = DateTime.utc(date.year, date.month, date.day + 1);
      expect(bt.utcRangeForBusinessDate(prev).$2, s);
      expect(bt.utcRangeForBusinessDate(next).$1, e);
    });
  }
}
