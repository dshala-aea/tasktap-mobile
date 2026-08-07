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
// Every attempt carries the local row's uuid as `clientId`. The server keys on
// it, so a resend returns the ticket it already created (200) rather than a
// second one (201). That is what makes retrying safe at all.
//
// This queue used to be stricter than SubmissionQueue for want of that key. It
// could distinguish two kinds of failure but could only act on one:
//   - pendingSync: the device was offline, so the request was NEVER SENT.
//     Nothing could have reached the server; always safe to retry.
//   - failed: the request WAS sent and something went wrong afterwards. The
//     outcome on the server was unknown, so an automatic retry risked a second
//     customer-visible ticket and no retry lost the job. Neither is
//     acceptable, so the technician was asked to decide — about the one thing
//     only the server could know.
//
// Both are now auto-retried. The distinction is kept because it still says
// something true about what happened, and it is what the UI shows; it no
// longer decides whether a retry may happen.
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

  /// Auto-retry every ticket that has not reached the server yet — both the
  /// ones never sent (`pendingSync`) and the ones whose send failed part-way
  /// (`failed`). Called on reconnect and on app start.
  ///
  /// `failed` rows are included because `clientId` makes the resend safe: if
  /// the earlier attempt did land, the server returns that same ticket instead
  /// of creating another. Before the key existed this loop could only carry
  /// `pendingSync`, and a ticket that failed mid-send sat on the device until
  /// somebody noticed it.
  Future<void> processAll() async {
    if (_running) return;
    _running = true;
    try {
      final pending = [
        ...await _repo.getByState(PendingTicketState.pendingSync),
        ...await _repo.getByState(PendingTicketState.failed),
      ];
      for (final t in pending) {
        await _attempt(t.id);
      }
    } finally {
      _running = false;
    }
  }

  /// Explicit, user-initiated retry — the "Riprova" button. Same call as the
  /// automatic path; it exists so a technician who does not want to wait for
  /// the next reconnect can push a ticket through now.
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
        // The local row id, unchanged across every attempt — that is the whole
        // point. A new one per attempt would deduplicate nothing.
        clientId: t.id,
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
