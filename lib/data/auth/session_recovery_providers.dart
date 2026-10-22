// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/submission_queue.dart';
import '../sync/submission_queue_watcher.dart' show realSubmissionQueueProvider;
import '../sync/sync_service.dart' show appDatabaseProvider;
import '../tickets/ticket_attachment_upload_queue.dart';
import '../tickets/ticket_attachment_upload_queue_watcher.dart'
    show ticketAttachmentUploadQueueProvider;
import '../tickets/ticket_creation_queue.dart';
import '../tickets/ticket_creation_queue_watcher.dart' show ticketCreationQueueProvider;
import '../timbratura/cantiere_timbra_sync_service.dart';
import '../timbratura/ticket_timer_sync_service.dart';
import '../timbratura/timbra_sync_service.dart';
import '../../presentation/providers/auth_providers.dart' show sessionEnderProvider;
import 'session_recovery.dart';
import 'unsent_work_counter.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Unsent-work wiring — the counter, the "Invia ora" flush, and the post-forced-
// sign-out decision.
//
// Kept out of `auth_providers.dart` on purpose: this file reaches into every
// queue provider, and `dio_client` (→ `auth_providers` → everything) reads
// `sessionEnderProvider` — pulling the queue graph into `auth_providers` would
// drag the whole data layer into the file the network stack imports.
// ══════════════════════════════════════════════════════════════════════════════

/// The single count of unsent work (see [UnsentWorkCounter] for what it includes).
final unsentWorkCounterProvider = Provider<UnsentWorkCounter>((ref) {
  return UnsentWorkCounter(db: ref.watch(appDatabaseProvider));
});

/// "Invia ora" — one attempt to push everything the queues can push, on demand.
///
/// Each queue keeps its own policy (the submission queue force-sends transiently-failed rows,
/// ticket creation only the never-sent `pendingSync` ones, attachments the same, timbra clears its
/// refusal hold because this is manual). That policy is not duplicated here: this only *triggers*
/// each queue and never interprets the result — the caller re-counts, which is the one honest
/// answer to "did everything get out?".
///
/// Voice recordings are deliberately absent: uploading one is the AI-transcription flow the
/// technician drives from the copilot screen, not a background queue. A pending recording
/// therefore keeps the count above zero, and the dialog offers "Esci comunque" — which is correct,
/// because that recording's audio only exists on this device.
class UnsentWorkFlusher {
  const UnsentWorkFlusher({
    required this.submissionQueue,
    required this.ticketCreationQueue,
    required this.ticketAttachmentQueue,
    required this.timbraSync,
    required this.cantiereSync,
    required this.ticketTimerSync,
  });

  final SubmissionQueue submissionQueue;
  final TicketCreationQueue ticketCreationQueue;
  final TicketAttachmentUploadQueue ticketAttachmentQueue;
  final TimbraSyncService timbraSync;
  final CantiereTimbraSyncService cantiereSync;

  /// Queued ticket clock sessions. The counter counts them, so the flush that exists to send what
  /// the counter counted has to try them too — otherwise "Invia ora" leaves the number unchanged
  /// with nothing the technician can do about it.
  final TicketTimerSyncService ticketTimerSync;

  Future<void> flush() async {
    await Future.wait([
      _swallow(submissionQueue.processAll(force: true)),
      _swallow(ticketCreationQueue.processAll()),
      _swallow(ticketAttachmentQueue.processAll()),
      _swallow(timbraSync.syncNow(manual: true)),
      _swallow(cantiereSync.syncNow()),
      // `manual` for the same reason timbra takes it: this is a user-initiated attempt, so it
      // clears the in-memory backoff and releases rows a permanent refusal was holding back.
      _swallow(ticketTimerSync.syncNow(manual: true)),
    ]);
  }

  /// One queue failing must not stop the others: the caller re-counts afterwards and reports
  /// whatever is left.
  static Future<void> _swallow(Future<void> attempt) async {
    try {
      await attempt;
    } catch (_) {
      // Recorded by the queue itself (per-row state/error); nothing to add here.
    }
  }
}

final unsentWorkFlusherProvider = Provider<UnsentWorkFlusher>((ref) {
  return UnsentWorkFlusher(
    submissionQueue: ref.watch(realSubmissionQueueProvider),
    ticketCreationQueue: ref.watch(ticketCreationQueueProvider),
    ticketAttachmentQueue: ref.watch(ticketAttachmentUploadQueueProvider),
    timbraSync: ref.watch(timbraSyncServiceProvider),
    cantiereSync: ref.watch(cantiereTimbraSyncServiceProvider),
    ticketTimerSync: ref.watch(ticketTimerSyncServiceProvider),
  );
});

/// Whether the local data a forced sign-out left behind is this account's, that account's, or
/// nobody's — resolved once per sign-in from the router's `redirect` (see
/// [SessionRecoveryController]).
final sessionRecoveryProvider =
    StateNotifierProvider<SessionRecoveryController, SessionRecoveryState>((ref) {
      return SessionRecoveryController(
        counter: ref.watch(unsentWorkCounterProvider),
        discardLocalData: () => ref.read(sessionEnderProvider).discardRetainedData(),
        flushQueues: () => ref.read(unsentWorkFlusherProvider).flush(),
      );
    });
