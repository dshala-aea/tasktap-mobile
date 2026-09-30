// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

void main() {
  test('a TimeSpan startTime ("HH:mm:ss") no longer throws (it did: DateTime.parse)', () {
    final dto = TodayWorkLogDto.fromJson({
      'id': 'w1',
      'clientId': 'c1',
      'startTime': '10:23:45',
      'endTime': null,
      'isActive': true,
    });
    final now = DateTime.now();
    expect(dto.startTime, DateTime(now.year, now.month, now.day, 10, 23, 45));
    expect(dto.endTime, isNull);
  });

  test('a full ISO instant is still parsed as before', () {
    final dto = TodayWorkLogDto.fromJson({
      'id': 'w1',
      'clientId': 'c1',
      'startTime': '2026-09-30T08:23:45Z',
      'endTime': '2026-09-30T12:00:00Z',
      'isActive': false,
    });
    expect(dto.startTime, DateTime.utc(2026, 9, 30, 8, 23, 45));
    expect(dto.endTime, DateTime.utc(2026, 9, 30, 12));
  });
}
