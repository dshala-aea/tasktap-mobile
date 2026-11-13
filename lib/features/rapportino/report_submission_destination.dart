import '../../core/router/app_router.dart';

/// Where the report wizard goes after a successful save/submit.
///
/// The report is part of a job, so the job is the natural next screen: the technician can see
/// the new report in its linked reports and keep working. Only a closed ticket or a report with
/// no job binding sends the technician home.
String reportSubmissionDestination({
  required String? ticketId,
  required String? cantiereId,
  required bool ticketIsClosed,
}) {
  if (ticketId != null && ticketId.isNotEmpty) {
    if (!ticketIsClosed) return AppRoutes.ticketDetailPath(ticketId);
  }
  if (cantiereId != null && cantiereId.isNotEmpty) {
    return AppRoutes.cantieriDetailPath(cantiereId, ticketId: ticketId);
  }
  return AppRoutes.dashboard;
}
