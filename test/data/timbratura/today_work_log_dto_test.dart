// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

Map<String, dynamic> _json(String start, [String? end]) => {
  'id': 'w1',
  'clientId': 'c1',
  'startTime': start,
  'endTime': end,
  'isActive': end == null,
};

void main() {
  test('a bare TimeSpan is Rome wall-clock on the Rome date, not the tenant zone or date', () {
    final bt = BusinessTime('America/New_York', clock: () => DateTime.utc(2026, 9, 30, 8));
    final dto = TodayWorkLogDto.fromJson(_json('10:23:45'), businessTime: bt);
    // 10:23:45 Rome (CEST, UTC+2) on 2026-09-30.
    expect(dto.startTime, DateTime.utc(2026, 9, 30, 8, 23, 45));
    expect(dto.endTime, isNull);
  });

  test('the date is the Rome date of the clock (after Rome midnight it is already tomorrow)', () {
    // 2026-09-30T23:30Z is 2026-10-01 01:30 in Rome.
    final bt = BusinessTime('America/New_York', clock: () => DateTime.utc(2026, 9, 30, 23, 30));
    final dto = TodayWorkLogDto.fromJson(_json('10:23:45', '12:00'), businessTime: bt);
    expect(dto.startTime, DateTime.utc(2026, 10, 1, 8, 23, 45));
    expect(dto.endTime, DateTime.utc(2026, 10, 1, 10));
  });

  test('a full ISO instant is still parsed as before', () {
    final bt = BusinessTime.fallback(clock: () => DateTime.utc(2026, 1, 1));
    final dto = TodayWorkLogDto.fromJson(
      _json('2026-09-30T08:23:45Z', '2026-09-30T12:00:00Z'),
      businessTime: bt,
    );
    expect(dto.startTime, DateTime.utc(2026, 9, 30, 8, 23, 45));
    expect(dto.endTime, DateTime.utc(2026, 9, 30, 12));
  });
}
