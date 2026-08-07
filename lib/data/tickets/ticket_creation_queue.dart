// dart format width=100
import 'package:uuid/uuid.dart';

import '../../features/ticket/ticket_api_client.dart';
import 'pending_ticket_repository.dart';
import 'pending_ticket_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TicketCreationQueue
//
// Persists every "create ticket" attempt locally FIRST, then decides whether
// it's safe to send it and, later, whether it's safe to retry it.
//
// Why this queue is stricter than SubmissionQueue (the rapportino queue):
// `POST /api/Tickets` has no client-supplied idempotency key. The rapportino
// queue can safely resend a failed submit any number of times because the
// server deduplicates by that key. A ticket create cannot: if the first
// attempt actually reached the server (e.g. the response was lost after a
// 200), blindly resending it would create a second, customer-visible ticket.
//
// So the state machine draws a hard line between two kinds of failure:
//   - pendingSync: the device was offline, so the request was NEVER SENT.
//     100% safe to auto-retry on reconnect — nothing could have reached the
//     server yet. Handled by [processAll].
//   - failed: the request WAS sent (the device believed itself online) and
//     something went wrong afterwards. The outcome on the server is unknown.
//     Never auto-retried. Only [retry], which must be triggered by an
//     explicit user action, will resend it — and even that carries residual
//     duplicate risk. The only way to close that gap fully is a backend
//     `clientId` on CreateTicketRequest that the server can deduplicate on,
//     the same way worklogs and rapportini already do.
//
// Invariant, mirrored from SubmissionQueue: a pending ticket is NEVER deleted
// on failure — only its state changes. Nothing typed by the technician is
// ever lost, even if it can't be safely resent automatically.
// ══════════════════════════════════════════════════════════════════════════════

class TicketCreationQueue {
  TicketCreationQueue({
    required PendingTicketRepository repo,
    required TicketApiClient apiClient,
    void Function()? onSubmitted,
  })  : _repo = repo,
        _apiClient = apiClient,
        _onSubmitted = onSubmitted;

  final PendingTicketRepository _repo;
  final TicketApiClient _apiClient;

  /// Called after every successful create/retry — wired by the provider to
  /// trigger a full sync so the server-assigned ticket (with its real
  /// tenantId/createdAt/etc.) is pulled down into the `tickets` cache table
  /// and shows up in the list without an app restart.
  final void Function()? _onSubmitted;

  bool _running = false;

  /// Persist the ticket locally, then — only if [isOnline] — attempt to send
  /// it immediately. When offline, the row is left in `pendingSync` for
  /// [processAll] to pick up automatically on reconnect.
  Future<TicketCreationOutcome> create({
    required String title,
    String? description,
    required String customerId,
    required String locationId,
    String? assignedUserId,
    required int statusId,
    required int typeId,
    required bool isOnline,
  }) async {
    final id = const Uuid().v4();
    await _repo.insert(
      id: id,
      title: title,
      description: description,
      customerId: customerId,
      locationId: locationId,
      assignedUserId: assignedUserId,
      statusId: statusId,
      typeId: typeId,
      state: isOnline
          ? PendingTicketState.submitting
          : PendingTicketState.pendingSync,
    );

    if (!isOnline) {
      return TicketCreationOutcome.queuedOffline(id);
    }
    return _attempt(id);
  }

  /// Auto-retry every ticket whose create request was NEVER sent (state ==
  /// pendingSync). Called on reconnect and on app start. `failed` rows are
  /// deliberately excluded — see the class doc comment.
  Future<void> processAll() async {
    if (_running) return;
    _running = true;
    try {
      final pending = await _repo.getByState(PendingTicketState.pendingSync);
      for (final t in pending) {
        await _attempt(t.id);
      }
    } finally {
      _running = false;
    }
  }

  /// Explicit, user-initiated retry of a `failed` ticket. Must only be
  /// called from a direct user tap (e.g. a "Riprova" button) — never wired
  /// to an automatic trigger, because the previous attempt's outcome on the
  /// server is unknown.
  Future<TicketCreationOutcome> retry(String id) => _attempt(id);

  Future<TicketCreationOutcome> _attempt(String id) async {
    final t = await _repo.getById(id);
    if (t == null) {
      return TicketCreationOutcome.failed(id, 'Ticket locale non trovato');
    }

    await _repo.updateState(
      id: id,
      state: PendingTicketState.submitting,
      clearError: true,
    );

    try {
      final serverId = await _apiClient.createTicket(
        title: t.title,
        description: t.description,
        customerId: t.customerId,
        locationId: t.locationId,
        assignedUserId: t.assignedUserId,
        statusId: t.statusId,
        typeId: t.typeId,
      );
      await _repo.markSubmitted(id: id, serverTicketId: serverId);
      _onSubmitted?.call();
      return TicketCreationOutcome.submitted(id, serverId);
    } catch (e) {
      // NEVER delete on failure — keep the ticket for a manual retry.
      await _repo.updateState(
        id: id,
        state: PendingTicketState.failed,
        error: e.toString(),
      );
      return TicketCreationOutcome.failed(id, e.toString());
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TicketCreationOutcome
// ══════════════════════════════════════════════════════════════════════════════

enum _TicketCreationOutcomeType { queuedOffline, submitted, failed }

class TicketCreationOutcome {
  const TicketCreationOutcome._(
    this.localId,
    this._type, {
    this.serverTicketId,
    this.error,
  });

  factory TicketCreationOutcome.queuedOffline(String localId) =>
      TicketCreationOutcome._(
          localId, _TicketCreationOutcomeType.queuedOffline);

  factory TicketCreationOutcome.submitted(
          String localId, String serverTicketId) =>
      TicketCreationOutcome._(
        localId,
        _TicketCreationOutcomeType.submitted,
        serverTicketId: serverTicketId,
      );

  factory TicketCreationOutcome.failed(String localId, String error) =>
      TicketCreationOutcome._(
        localId,
        _TicketCreationOutcomeType.failed,
        error: error,
      );

  final String localId;
  final _TicketCreationOutcomeType _type;
  final String? serverTicketId;
  final String? error;

  bool get isQueuedOffline =>
      _type == _TicketCreationOutcomeType.queuedOffline;
  bool get isSubmitted => _type == _TicketCreationOutcomeType.submitted;
  bool get isFailed => _type == _TicketCreationOutcomeType.failed;
}
