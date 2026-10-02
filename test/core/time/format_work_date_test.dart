import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('it'));

  test('a UTC-midnight label formats its own y/m/d, whatever the device zone', () {
    expect(formatWorkDate(DateTime.utc(2026, 1, 1), 'dd/MM/yyyy'), '01/01/2026');
  });

  test('a local-flagged twin gives the same text', () {
    expect(formatWorkDate(DateTime(2026, 1, 1), 'dd/MM/yyyy'), '01/01/2026');
  });

  test('Italian weekday and month for 10 July 2026', () {
    final s = formatWorkDate(DateTime.utc(2026, 7, 10), 'EEE d MMM', locale: 'it');
    expect(s.toLowerCase(), 'ven 10 lug');
  });

  test('parseDateOnly of a full timestamp label keeps the label day', () {
    final d = parseDateOnly('2026-07-10T00:00:00Z')!;
    expect(formatWorkDate(d, 'dd/MM/yyyy'), '10/07/2026');
  });
}
