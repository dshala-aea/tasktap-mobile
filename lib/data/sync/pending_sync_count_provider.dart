// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../timbratura/work_session_repository.dart' show reconciledOrphanMarker;
import 'sync_service.dart' show appDatabaseProvider;

typedef PendingSyncCount = ({int pending, int failed});

const _reportPending = ['readyToSubmit', 'uploadingMedia', 'submitting'];
const _queuePending = ['pendingSync', 'submitting'];

/// Aggregates how many rows across the existing offline queues (draft reports, pending tickets,
/// pending ticket attachments, ticket timer sessions, personal punches) are queued waiting to
/// sync, and how many are in a failed state — pure read-side aggregation over tables the existing
/// queues already own; this provider owns no sync logic of its own.
///
/// Personal punches are included because they are hours the office has not received. Leaving them
/// out made a held or refused break invisible everywhere except the Timbra screen: the app said
/// there was nothing unsent while the technician's pausa was still on the phone.
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
  // A queued ticket timer is hours not yet on the server: a start that never left the phone, or a
  // close waiting behind the signal. `syncError` is the "we tried and were refused" flag, the same
  // meaning the other queues' `failed` state carries.
  final timersStream = (db.select(
    db.ticketTimers,
  )..where((t) => t.isPendingSync.equals(true))).watch();
  // Personal punches, excluding the reconciler's own display-only corrections (they are pending
  // by construction but are never uploaded, so counting them would report work no sync can clear).
  final workSessionsStream =
      (db.select(db.workSessions)..where(
            (w) =>
                w.isPendingSync.equals(true) &
                (w.notes.isNull() | w.notes.equals(reconciledOrphanMarker).not()),
          ))
          .watch();

  return Rx.combineLatest5(
    reportsStream,
    ticketsStream,
    attachmentsStream,
    timersStream,
    workSessionsStream,
    (reports, tickets, attachments, timers, workSessions) {
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
      for (final t in timers) {
        if (t.syncError != null) {
          failed++;
        } else {
          pending++;
        }
      }
      // Every row selected above is a pending personal punch (the reconciler's display-only
      // corrections are excluded in the query).
      pending += workSessions.length;

      return (pending: pending, failed: failed);
    },
  );
});
