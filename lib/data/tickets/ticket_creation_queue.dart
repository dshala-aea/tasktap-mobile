// dart format width=100
import 'package:uuid/uuid.dart';

import '../../core/utils/error_message.dart';
import '../../features/ticket/ticket_api_client.dart';
import '../api/problem_details.dart';
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
// One exception, added later: a rejection the client can REPAIR. A 404 that
// names one of the request's reference fields means the next attempt would
// send the same rejected id and fail identically — no answer will ever differ,
// so an automatic retry is not optimistic, it is pointless. The field is
// persisted on the row, the row is held out of the sweeps (see
// repairableFieldOf), and a human repairs it through the wizard. This layer
// only detects and records that: it opens no UI and knows no field's label.
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
  }) : _repo = repo,
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

  /// The request fields whose rejection this client can actually repair — both re-pickable in the
  /// wizard and writable back to the queue row. Not in this set means the row waits for nothing: it
  /// is shown as failed and retried as before, because guessing at a repair for a field we cannot
  /// render would only produce a screen that cannot fix the problem.
  ///
  /// `cantiereId` is absent because no wizard step has a cantiere field — there is no picker to
  /// repair it with. `statusId` is absent because the wizard never asks for it: it defaults from
  /// the default `TicketStatus`, so a "repair" would re-send the very id the server just refused.
  /// See the plan's third-pass revision note, item 1.
  static const _repairableFields = {
    'customerId',
    'locationId',
    'contractId',
    'commessaId',
    'assignedUserId',
    'typeId',
    'agentId',
    'prodottoAssistenzaIds',
  };

  /// The field a `not_found` blamed, when this client can repair it. Null otherwise — including for
  /// a field name from a backend that has moved on, and for every non-404.
  ///
  /// Static and pure (a caught error in, a `String?` out) so it is testable without a database or a
  /// queue.
  static String? repairableFieldOf(Object error) {
    final field = ProblemDetails.fieldOf(error);
    return field != null && _repairableFields.contains(field) ? field : null;
  }

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
    String priorita = 'Media',
    DateTime? dueDate,
    String? technicianNotes,
    String? agentId,
    String? contractId,
    String? commessaId,
    String? cantiereId,
    List<String> prodottoAssistenzaIds = const [],
    List<String> tags = const [],
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
      priorita: priorita,
      dueDate: dueDate,
      technicianNotes: technicianNotes,
      agentId: agentId,
      contractId: contractId,
      commessaId: commessaId,
      cantiereId: cantiereId,
      prodottoAssistenzaIds: prodottoAssistenzaIds,
      tags: tags,
      state: isOnline ? PendingTicketState.submitting : PendingTicketState.pendingSync,
    );

    if (!isOnline) {
      return TicketCreationOutcome.queuedOffline(id);
    }
    return _attempt(id);
  }

  /// Write a corrected ticket back onto the row the server rejected, in place, and clear the flag
  /// that was holding it out of the retry sweeps.
  ///
  /// An UPDATE of that same row, for two reasons that are the whole point of the repair path: a
  /// [create] would insert a SECOND pending ticket and leave the rejected one sitting beside it,
  /// and a `PUT /api/tickets` would reach the server for a ticket the server does not have yet —
  /// this row has never been created. Nothing is sent from here at all.
  ///
  /// Takes the same field set [create] does and hands it to the same row writer
  /// (`PendingTicketRepository.updateFields`, itself built on the companion [create]'s insert uses),
  /// so a column added to one cannot be silently missing from the other.
  ///
  /// The next automatic sweep picks the row up: `repairableField` is null again, so nothing excludes
  /// it. See [repairableFieldOf] for what made it repairable in the first place.
  Future<void> repair(
    String id, {
    required String title,
    String? description,
    required String customerId,
    required String locationId,
    String? assignedUserId,
    required int statusId,
    required int typeId,
    String priorita = 'Media',
    DateTime? dueDate,
    String? technicianNotes,
    String? agentId,
    String? contractId,
    String? commessaId,
    String? cantiereId,
    List<String> prodottoAssistenzaIds = const [],
    List<String> tags = const [],
  }) async {
    await _repo.updateFields(
      id: id,
      title: title,
      description: description,
      customerId: customerId,
      locationId: locationId,
      assignedUserId: assignedUserId,
      statusId: statusId,
      typeId: typeId,
      priorita: priorita,
      dueDate: dueDate,
      technicianNotes: technicianNotes,
      agentId: agentId,
      contractId: contractId,
      commessaId: commessaId,
      cantiereId: cantiereId,
      prodottoAssistenzaIds: prodottoAssistenzaIds,
      tags: tags,
    );
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
  ///
  /// Rows waiting on a repair are excluded from both sweeps: the id the server
  /// just refused would be sent again, unchanged, and refused again. A repaired
  /// row has no flag left, so it comes back through here like any other.
  Future<void> processAll() async {
    if (_running) return;
    _running = true;
    try {
      final pending = [
        ...await _repo.getByState(PendingTicketState.pendingSync, autoRetryableOnly: true),
        ...await _repo.getByState(PendingTicketState.failed, autoRetryableOnly: true),
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

    await _repo.updateState(id: id, state: PendingTicketState.submitting, clearError: true);

    try {
      final serverId = await _apiClient.createTicket(
        title: t.title,
        description: t.description,
        customerId: t.customerId,
        locationId: t.locationId,
        assignedUserId: t.assignedUserId,
        statusId: t.statusId,
        typeId: t.typeId,
        priorita: t.priorita,
        dueDate: t.dueDate,
        technicianNotes: t.technicianNotes,
        agentId: t.agentId,
        contractId: t.contractId,
        commessaId: t.commessaId,
        cantiereId: t.cantiereId,
        prodottoAssistenzaIds: decodePendingStringList(t.prodottoAssistenzaIdsJson),
        tags: decodePendingStringList(t.tagsJson),
        // The local row id, unchanged across every attempt — that is the whole
        // point. A new one per attempt would deduplicate nothing.
        clientId: t.id,
      );
      await _repo.markSubmitted(id: id, serverTicketId: serverId);
      _onSubmitted?.call();
      return TicketCreationOutcome.submitted(id, serverId);
    } catch (e) {
      // NEVER delete on failure — keep the ticket for a manual retry.
      //
      // The stored string is rendered verbatim on the ticket list ("Invio non riuscito: …"), so it
      // has to be a sentence rather than an exception.
      final reason = humanErrorMessage(e, azione: 'creare il ticket');
      // The flag travels with this failure and nothing else: a later failure with no field in its
      // body clears it (see `markFailed`), so a row is never held out of the retry sweeps on the
      // strength of a rejection that has since been superseded.
      await _repo.markFailed(id: id, error: reason, repairableField: repairableFieldOf(e));
      return TicketCreationOutcome.failed(id, reason);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TicketCreationOutcome
// ══════════════════════════════════════════════════════════════════════════════

enum _TicketCreationOutcomeType { queuedOffline, submitted, failed }

class TicketCreationOutcome {
  const TicketCreationOutcome._(this.localId, this._type, {this.serverTicketId, this.error});

  factory TicketCreationOutcome.queuedOffline(String localId) =>
      TicketCreationOutcome._(localId, _TicketCreationOutcomeType.queuedOffline);

  factory TicketCreationOutcome.submitted(String localId, String serverTicketId) =>
      TicketCreationOutcome._(
        localId,
        _TicketCreationOutcomeType.submitted,
        serverTicketId: serverTicketId,
      );

  factory TicketCreationOutcome.failed(String localId, String error) =>
      TicketCreationOutcome._(localId, _TicketCreationOutcomeType.failed, error: error);

  final String localId;
  final _TicketCreationOutcomeType _type;
  final String? serverTicketId;
  final String? error;

  bool get isQueuedOffline => _type == _TicketCreationOutcomeType.queuedOffline;
  bool get isSubmitted => _type == _TicketCreationOutcomeType.submitted;
  bool get isFailed => _type == _TicketCreationOutcomeType.failed;
}
