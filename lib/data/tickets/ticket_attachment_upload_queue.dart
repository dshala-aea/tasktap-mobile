// dart format width=100
import 'package:uuid/uuid.dart';

import '../../core/utils/error_message.dart';
import '../../features/ticket/ticket_detail_api_client.dart';
import 'pending_ticket_attachment_repository.dart';
import 'pending_ticket_attachment_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TicketAttachmentUploadQueue
//
// Persists every "attach a file to a ticket" attempt locally FIRST, then
// decides whether it's safe to send it and, later, whether it's safe to
// retry it. Mirrors TicketCreationQueue's shape — see its own doc comment
// for the fuller design rationale — but keeps the *original*, stricter retry
// policy: `POST /api/tickets/{id}/attachments` has no client-supplied
// idempotency key (unlike ticket creation's `clientId`), so a `failed`
// row's outcome on the server is genuinely unknown and an automatic resend
// risks attaching the same photo twice.
//
//   pendingSync ──(never sent — device was offline when picked)──► submitting
//   submitting  ──(200 OK)─────────────────────────────────────────► submitted
//   submitting  ──(error — outcome on the server is now unknown)───► failed
//
// Only `pendingSync` rows are auto-retried by [processAll]. `failed` rows sit
// until an explicit, user-initiated [retry] — never auto-retried. Invariant,
// mirrored from TicketCreationQueue: a pending attachment is NEVER deleted on
// failure — only its state changes.
// ══════════════════════════════════════════════════════════════════════════════

class TicketAttachmentUploadQueue {
  TicketAttachmentUploadQueue({
    required PendingTicketAttachmentRepository repo,
    required TicketDetailApiClient apiClient,
    void Function(String ticketId)? onUploaded,
  }) : _repo = repo,
       _apiClient = apiClient,
       _onUploaded = onUploaded;

  final PendingTicketAttachmentRepository _repo;
  final TicketDetailApiClient _apiClient;

  /// Called after every successful upload/retry — wired by the provider to invalidate the
  /// server-fetched attachment list for that ticket, so the newly uploaded file appears without
  /// the technician having to leave and reopen the Allegati tab.
  final void Function(String ticketId)? _onUploaded;

  bool _running = false;

  /// Persist the attachment locally, then — only if [isOnline] — attempt to send it immediately.
  /// When offline, the row is left in `pendingSync` for [processAll] to pick up on reconnect.
  Future<TicketAttachmentUploadOutcome> upload({
    required String ticketId,
    required String localPath,
    required String fileName,
    required String contentType,
    required int sizeBytes,
    required bool isOnline,
  }) async {
    final id = const Uuid().v4();
    await _repo.insert(
      id: id,
      ticketId: ticketId,
      localPath: localPath,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
      state: isOnline
          ? PendingTicketAttachmentState.submitting
          : PendingTicketAttachmentState.pendingSync,
    );

    if (!isOnline) {
      return TicketAttachmentUploadOutcome.queuedOffline(id, ticketId);
    }
    return _attempt(id);
  }

  /// Auto-retry every attachment that has not reached the server yet — only `pendingSync`. See
  /// the class doc comment for why `failed` is excluded. Called on reconnect and on app start.
  Future<void> processAll() async {
    if (_running) return;
    _running = true;
    try {
      final pending = await _repo.getByState(PendingTicketAttachmentState.pendingSync);
      for (final a in pending) {
        await _attempt(a.id);
      }
    } finally {
      _running = false;
    }
  }

  /// Explicit, user-initiated retry — the "Riprova" action on a failed row.
  Future<TicketAttachmentUploadOutcome> retry(String id) => _attempt(id);

  Future<TicketAttachmentUploadOutcome> _attempt(String id) async {
    final a = await _repo.getById(id);
    if (a == null) {
      return TicketAttachmentUploadOutcome.failed(id, '', 'Allegato locale non trovato');
    }

    await _repo.updateState(id: id, state: PendingTicketAttachmentState.submitting, clearError: true);

    try {
      final result = await _apiClient.uploadAttachment(
        ticketId: a.ticketId,
        localPath: a.localPath,
        fileName: a.fileName,
        contentType: a.contentType,
      );
      await _repo.markSubmitted(id: id, serverAttachmentId: result.allegatoId);
      _onUploaded?.call(a.ticketId);
      return TicketAttachmentUploadOutcome.submitted(id, a.ticketId, result.allegatoId);
    } catch (e) {
      // NEVER delete on failure — keep the attachment for a manual retry. The stored string is
      // rendered verbatim under "Caricamento non riuscito", so it has to be a sentence.
      final reason = humanErrorMessage(e, azione: 'caricare l\'allegato');
      await _repo.updateState(id: id, state: PendingTicketAttachmentState.failed, error: reason);
      return TicketAttachmentUploadOutcome.failed(id, a.ticketId, reason);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TicketAttachmentUploadOutcome
// ══════════════════════════════════════════════════════════════════════════════

enum _TicketAttachmentUploadOutcomeType { queuedOffline, submitted, failed }

class TicketAttachmentUploadOutcome {
  const TicketAttachmentUploadOutcome._(
    this.localId,
    this.ticketId,
    this._type, {
    this.serverAttachmentId,
    this.error,
  });

  factory TicketAttachmentUploadOutcome.queuedOffline(String localId, String ticketId) =>
      TicketAttachmentUploadOutcome._(
        localId,
        ticketId,
        _TicketAttachmentUploadOutcomeType.queuedOffline,
      );

  factory TicketAttachmentUploadOutcome.submitted(
    String localId,
    String ticketId,
    String serverAttachmentId,
  ) => TicketAttachmentUploadOutcome._(
    localId,
    ticketId,
    _TicketAttachmentUploadOutcomeType.submitted,
    serverAttachmentId: serverAttachmentId,
  );

  factory TicketAttachmentUploadOutcome.failed(String localId, String ticketId, String error) =>
      TicketAttachmentUploadOutcome._(
        localId,
        ticketId,
        _TicketAttachmentUploadOutcomeType.failed,
        error: error,
      );

  final String localId;
  final String ticketId;
  final _TicketAttachmentUploadOutcomeType _type;
  final String? serverAttachmentId;
  final String? error;

  bool get isQueuedOffline => _type == _TicketAttachmentUploadOutcomeType.queuedOffline;
  bool get isSubmitted => _type == _TicketAttachmentUploadOutcomeType.submitted;
  bool get isFailed => _type == _TicketAttachmentUploadOutcomeType.failed;
}
