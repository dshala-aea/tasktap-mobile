import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

Map<String, dynamic> _user(Object? workDate) => {
  'id': 'w1',
  'userId': 'u1',
  'workDate': ?workDate,
  'startTime': '08:00:00',
  'endTime': null,
};

Map<String, dynamic> _cantiere(Object? workDate) => {
  'id': 'w1',
  'cantiereId': 'c1',
  'customerId': 'k1',
  'userId': 'u1',
  'workDate': ?workDate,
  'startTime': '08:00:00',
  'endTime': null,
};

Map<String, dynamic> _ticket(Object? workDate) => {
  'id': 'w1',
  'ticketId': 't1',
  'userId': 'u1',
  'workDate': ?workDate,
  'startTime': '08:00:00',
  'endTime': null,
};

void main() {
  final cases =
      <
        String,
        (
          Map<String, dynamic> Function(Object?),
          DateTime Function(Map<String, dynamic>),
        )
      >{
        'UserWorkLogDto': (_user, (j) => UserWorkLogDto.fromJson(j).workDate),
        'CantiereWorkLogDto': (
          _cantiere,
          (j) => CantiereWorkLogDto.fromJson(j).workDate,
        ),
        'TicketWorkLogDto': (
          _ticket,
          (j) => TicketWorkLogDto.fromJson(j).workDate,
        ),
      };

  for (final entry in cases.entries) {
    final (build, read) = entry.value;
    group(entry.key, () {
      for (final raw in [
        '2026-07-10T00:00:00Z',
        '2026-07-10',
        '2026-07-10T00:00:00',
      ]) {
        test('workDate "$raw" is the civil date 2026-07-10', () {
          final d = read(build(raw));
          expect(d, DateTime.utc(2026, 7, 10));
          expect(d.isUtc, isTrue);
        });
      }

      test('an unparseable workDate throws FormatException', () {
        expect(() => read(build('not-a-date')), throwsFormatException);
      });

      test('a missing workDate throws FormatException', () {
        expect(() => read(build(null)), throwsFormatException);
      });
    });
  }
}
