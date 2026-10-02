// The ticket timer bar's elapsed time. A running TicketWorkLogDto holds a date-only `workDate`
// (UTC-flagged civil date) and a Rome wall-clock `startTime` (a bare TimeSpan). Adding them
// as if both were UTC under-reports the elapsed time by the Rome offset (and goes negative right
// after the start). Same expectations under any device zone (tool/test_tz_matrix.sh).

import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_screen.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

TicketWorkLogDto _running(DateTime workDate, Duration start) => TicketWorkLogDto(
  id: 'w1',
  ticketId: 't1',
  userId: 'u1',
  workDate: workDate,
  startTime: start,
  isManualEntry: false,
);

void main() {
  final rome = BusinessTime('Europe/Rome');

  test('summer: started 10:00 Rome (08:00Z), 5 minutes later', () {
    final e = ticketTimerElapsed(
      _running(DateTime.utc(2026, 7, 10), const Duration(hours: 10)),
      DateTime.utc(2026, 7, 10, 8, 5),
      rome,
    );
    expect(e, const Duration(minutes: 5));
  });

  test('winter: started 10:00 Rome (09:00Z), 5 minutes later', () {
    final e = ticketTimerElapsed(
      _running(DateTime.utc(2026, 12, 1), const Duration(hours: 10)),
      DateTime.utc(2026, 12, 1, 9, 5),
      rome,
    );
    expect(e, const Duration(minutes: 5));
  });

  test('a New York tenant zone does not move the legacy Rome frame', () {
    final e = ticketTimerElapsed(
      _running(DateTime.utc(2026, 7, 10), const Duration(hours: 10)),
      DateTime.utc(2026, 7, 10, 8, 5),
      BusinessTime('America/New_York'),
    );
    expect(e, const Duration(minutes: 5));
  });

  test('never negative (clock skew just after start)', () {
    final e = ticketTimerElapsed(
      _running(DateTime.utc(2026, 7, 10), const Duration(hours: 10)),
      DateTime.utc(2026, 7, 10, 7, 59, 58),
      rome,
    );
    expect(e, Duration.zero);
  });
}
