// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import 'sync_service.dart' show appDatabaseProvider;

typedef PendingSyncCount = ({int pending, int failed});

const _reportPending = ['readyToSubmit', 'uploadingMedia', 'submitting'];
const _queuePending = ['pendingSync', 'submitting'];

/// Aggregates how many rows across the existing offline queues (draft reports, pending tickets,
/// pending ticket attachments) are queued waiting to sync, and how many are in a failed state —
/// pure read-side aggregation over tables the existing queues already own; this provider owns no
/// sync logic of its own.
final pendingSyncCountProvider = StreamProvider<PendingSyncCount>((ref) {
  final db = ref.watch(appDatabaseProvider);

  final reportsStream = (db.select(
    db.draftReports,
  )..where((r) => r.submissionState.isIn([..._reportPending, 'failed']))).watch();
  final ticketsStream = (db.select(
    db.pendingTickets,
  )..where((t) => t.state.isNotValue('submitted'))).watch();
  final attachmentsStream = (db.select(
    db.pendingTicketAttachments,
  )..where((a) => a.state.isNotValue('submitted'))).watch();

  return Rx.combineLatest3(reportsStream, ticketsStream, attachmentsStream, (
    reports,
    tickets,
    attachments,
  ) {
    var pending = 0;
    var failed = 0;

    for (final r in reports) {
      if (r.submissionState == 'failed') {
        failed++;
      } else if (_reportPending.contains(r.submissionState)) {
        pending++;
      }
    }
    for (final t in tickets) {
      if (t.state == 'failed') {
        failed++;
      } else if (_queuePending.contains(t.state)) {
        pending++;
      }
    }
    for (final a in attachments) {
      if (a.state == 'failed') {
        failed++;
      } else if (_queuePending.contains(a.state)) {
        pending++;
      }
    }

    return (pending: pending, failed: failed);
  });
});
