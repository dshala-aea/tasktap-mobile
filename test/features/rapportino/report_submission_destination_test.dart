import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/features/rapportino/report_submission_destination.dart';

void main() {
  test('open ticket wins over everything', () {
    expect(
      reportSubmissionDestination(
        ticketId: 'ticket-1',
        cantiereId: 'cantiere-1',
        ticketIsClosed: false,
      ),
      AppRoutes.ticketDetailPath('ticket-1'),
    );
  });

  test('closed ticket with a cantiere goes to the cantiere', () {
    expect(
      reportSubmissionDestination(
        ticketId: 'ticket-1',
        cantiereId: 'cantiere-1',
        ticketIsClosed: true,
      ),
      AppRoutes.cantieriDetailPath('cantiere-1', ticketId: 'ticket-1'),
    );
  });

  test('closed ticket without a cantiere goes home', () {
    expect(
      reportSubmissionDestination(
        ticketId: 'ticket-1',
        cantiereId: null,
        ticketIsClosed: true,
      ),
      AppRoutes.dashboard,
    );
  });

  test('standalone report goes home', () {
    expect(
      reportSubmissionDestination(
        ticketId: null,
        cantiereId: null,
        ticketIsClosed: false,
      ),
      AppRoutes.dashboard,
    );
  });
}
