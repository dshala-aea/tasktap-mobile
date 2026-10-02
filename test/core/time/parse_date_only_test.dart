import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';

void main() {
  final expected = DateTime.utc(2026, 7, 10);

  test('plain date', () => expect(parseDateOnly('2026-07-10'), expected));
  test('UTC timestamp',
      () => expect(parseDateOnly('2026-07-10T00:00:00Z'), expected));
  test('offset is ignored on purpose',
      () => expect(parseDateOnly('2026-07-10T23:30:00-05:00'), expected));
  test('naive timestamp',
      () => expect(parseDateOnly('2026-07-10T00:00:00'), expected));
  test('result is UTC-flagged', () {
    expect(parseDateOnly('2026-07-10')!.isUtc, isTrue);
  });

  test('invalid calendar date', () {
    expect(parseDateOnly('2026-02-30'), isNull);
    expect(parseDateOnly('2026-13-01'), isNull);
  });

  test('leap day valid only in leap years', () {
    expect(parseDateOnly('2028-02-29'), DateTime.utc(2028, 2, 29));
    expect(parseDateOnly('2027-02-29'), isNull);
  });

  test('garbage and non-strings', () {
    expect(parseDateOnly('abc'), isNull);
    expect(parseDateOnly(''), isNull);
    expect(parseDateOnly(null), isNull);
    expect(parseDateOnly(12345), isNull);
    expect(parseDateOnly('2026/07/10'), isNull);
    expect(parseDateOnly('2026-7-10x'), isNull);
  });
}
