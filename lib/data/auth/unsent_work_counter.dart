// dart format width=100
import 'package:drift/drift.dart';

import '../../core/audio/pending_recording_store.dart';
import '../local/app_database.dart';
import '../sync/draft_submission_state.dart';
import '../tickets/pending_ticket_state.dart';
import '../timbratura/cantiere_session_repository.dart' show cantiereReconciledOrphanMarker;
import '../timbratura/work_session_repository.dart' show reconciledOrphanMarker;

// ══════════════════════════════════════════════════════════════════════════════
// UnsentWorkCounter
//
// One answer to "how much work is sitting on this device that the server has
// never seen?" — the number the logout dialog must name before it lets someone
// end a session, because ending it wipes Drift and that work with it.
//
// Before this existed there was no such number anywhere. `pendingSyncCountProvider`
// counts three of the six queues and feeds a badge; timbra and cantiere pending
// punches (the payroll data) were not in any count, and neither were voice
// recordings. So the logout dialog could only say "Sei sicuro?" — and the audit's
// F1 finding is what that costs: a technician who spent a day offline taps Esci
// once and loses every rapportino, ticket, punch and recording on the device.
//
// Deliberately reads the tables directly rather than going through each queue's
// repository:
//   - no single repository spans all six queues, and adding a counting method to
//     each one would put this read model inside every write path's file;
//   - the timbra/cantiere repositories expose only *today's* rows (a display
//     concern), while this must count ANY day — a punch left pending over the
//     weekend is exactly the work that must not be lost silently.
//
// What is NOT counted, on purpose:
//   - draft reports that are not local-only: those are server rows synced down
//     for display (Inviato/Controllato/…), not work waiting to be sent. Their
//     `submissionState` is left at the column default `draft`, so counting
//     "state != submitted" alone would count every report the office ever wrote.
//   - events marked `reconciled_orphan`: the reconciler has already established
//     the server holds them (or already closed them); the sync services skip them
//     by contract, so they are not unsent work and will not be lost in any
//     meaningful sense.
//   - `sync_failed_conflict` work_sessions are already `isPendingSync = false`
//     (see `WorkSessionRepository.markSyncFailed`), so the pending filter excludes
//     them without a second clause.
// ══════════════════════════════════════════════════════════════════════════════

/// How much unsent work sits in each queue. A record rather than six getters so a
/// caller (and a test) can assert the whole thing at once — a queue silently
/// dropping out of the total is the regression this type exists to catch.
class UnsentWorkBreakdown {
  const UnsentWorkBreakdown({
    this.draftReports = 0,
    this.pendingTickets = 0,
    this.pendingAttachments = 0,
    this.workSessions = 0,
    this.cantierePunches = 0,
    this.voiceRecordings = 0,
  });

  /// Locally-authored rapportini not yet submitted (`isLocalOnly` and not `submitted`).
  final int draftReports;

  /// Ticket-create outbox rows in any state but `submitted`.
  final int pendingTickets;

  /// Ticket-attachment outbox rows in any state but `submitted`.
  final int pendingAttachments;

  /// Personal timbra events still `isPendingSync`, on ANY day.
  final int workSessions;

  /// Cantiere timbra events still `isPendingSync`, on ANY day.
  final int cantierePunches;

  /// Voice recordings sitting in the pending_voice directory (any owner — a
  /// shared device's wipe takes all of them).
  final int voiceRecordings;

  int get total =>
      draftReports +
      pendingTickets +
      pendingAttachments +
      workSessions +
      cantierePunches +
      voiceRecordings;

  bool get isEmpty => total == 0;

  /// The count as the logout dialog's copy needs it ("1 elemento" / "N elementi").
  bool get isSingular => total == 1;

  @override
  String toString() =>
      'UnsentWorkBreakdown(draftReports: $draftReports, pendingTickets: $pendingTickets, '
      'pendingAttachments: $pendingAttachments, workSessions: $workSessions, '
      'cantierePunches: $cantierePunches, voiceRecordings: $voiceRecordings)';
}

/// Counts every unsent queue on this device. See the file comment for what is and is not
/// included and why.
class UnsentWorkCounter {
  UnsentWorkCounter({required AppDatabase db, Future<int> Function()? countVoiceRecordings})
    : _db = db,
      _countVoiceRecordings = countVoiceRecordings ?? _countAppVoiceRecordings;

  final AppDatabase _db;

  /// Injectable because [PendingRecordingStore.forApp] needs the documents directory, which
  /// `flutter test` cannot provide — every counter test supplies its own.
  final Future<int> Function() _countVoiceRecordings;

  static Future<int> _countAppVoiceRecordings() async =>
      (await (await PendingRecordingStore.forApp()).list()).length;

  Future<UnsentWorkBreakdown> count() async {
    final drafts =
        await (_db.select(_db.draftReports)..where(
              (r) =>
                  r.isLocalOnly.equals(true) &
                  r.submissionState
                      .equals(DraftSubmissionState.submitted.toPersistedString())
                      .not(),
            ))
            .get();

    final tickets =
        await (_db.select(_db.pendingTickets)..where(
              (t) => t.state
                  .equals(PendingTicketState.submitted.toPersistedString())
                  .not(),
            ))
            .get();

    final attachments =
        await (_db.select(_db.pendingTicketAttachments)..where(
              (a) => a.state
                  .equals(PendingTicketState.submitted.toPersistedString())
                  .not(),
            ))
            .get();

    // No day window: a punch from last week that never left the phone is exactly what a
    // technician must be told about before it is wiped.
    final sessions =
        await (_db.select(_db.workSessions)..where(
              (s) =>
                  s.isPendingSync.equals(true) &
                  (s.notes.isNull() | s.notes.equals(reconciledOrphanMarker).not()),
            ))
            .get();

    final punches =
        await (_db.select(_db.cantierePunches)..where(
              (t) =>
                  t.isPendingSync.equals(true) &
                  (t.notes.isNull() | t.notes.equals(cantiereReconciledOrphanMarker).not()),
            ))
            .get();

    return UnsentWorkBreakdown(
      draftReports: drafts.length,
      pendingTickets: tickets.length,
      pendingAttachments: attachments.length,
      workSessions: sessions.length,
      cantierePunches: punches.length,
      voiceRecordings: await _countVoiceRecordings(),
    );
  }
}
