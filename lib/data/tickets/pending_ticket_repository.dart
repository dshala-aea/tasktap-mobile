// dart format width=100
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'pending_ticket_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PendingTicketRepository
//
// All CRUD for the pending_tickets local outbox. Zero network — mirrors
// DraftReportRepository's shape for the submission-state slice.
// ══════════════════════════════════════════════════════════════════════════════

/// The JSON-text list storage [PendingTickets.tagsJson] and `.prodottoAssistenzaIdsJson` share —
/// see their doc comments for why. `null`/`""` is "never set", not a parse error: a row written
/// before the column existed, or by a technician who never opened the picker.
///
/// Top-level rather than a private member of [TicketCreationQueue], because the queue is not its
/// only reader: `NewTicketFormState.fromPendingRow` seeds the repair wizard from the same encoding
/// (`new_ticket_form_state.dart`), and two decoders for one format is how they drift.
List<String> decodePendingStringList(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  return decoded is List ? decoded.cast<String>() : const [];
}

/// Every column holding the *ticket* a queued row stands for — the body [insert] and [updateFields]
/// share, so a field added to one is a field added to both. A repair that quietly stopped carrying
/// a column is the failure mode this exists to prevent (see [TicketCreationQueue.repair]).
///
/// The queue's own bookkeeping (`state`, `error`, `serverTicketId`, `repairableField`) is
/// deliberately not here: each is written by the method whose business it is.
PendingTicketsCompanion _rowCompanion({
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
}) {
  return PendingTicketsCompanion(
    title: Value(title),
    description: Value(description),
    customerId: Value(customerId),
    locationId: Value(locationId),
    assignedUserId: Value(assignedUserId),
    statusId: Value(statusId),
    typeId: Value(typeId),
    priorita: Value(priorita),
    dueDate: Value(dueDate),
    technicianNotes: Value(technicianNotes),
    agentId: Value(agentId),
    contractId: Value(contractId),
    commessaId: Value(commessaId),
    cantiereId: Value(cantiereId),
    // JSON text, same convention as tagsJson: a list column has to survive the round trip
    // through the outbox unchanged, and null is reserved for a row that never had one.
    prodottoAssistenzaIdsJson: Value(
      prodottoAssistenzaIds.isEmpty ? null : jsonEncode(prodottoAssistenzaIds),
    ),
    tagsJson: Value(jsonEncode(tags)),
  );
}

class PendingTicketRepository {
  PendingTicketRepository(this._db);

  final AppDatabase _db;

  /// Insert a new local-only pending ticket row.
  Future<void> insert({
    required String id,
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
    required PendingTicketState state,
  }) async {
    await _db
        .into(_db.pendingTickets)
        .insert(
          _rowCompanion(
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
          ).copyWith(
            id: Value(id),
            createdAt: Value(DateTime.now().toUtc()),
            state: Value(state.toPersistedString()),
          ),
        );
  }

  /// Write a corrected ticket back onto an EXISTING row and clear its `repairableField` — the
  /// repair path ([TicketCreationQueue.repair]). Never inserts: repairing is not creating a second
  /// ticket, it is fixing the one the server refused.
  ///
  /// The flag is cleared here, in the same write as the corrected values, so the row cannot be left
  /// carrying a repair it no longer needs. `state` and `error` are left alone — the last send did
  /// fail, and that is still true.
  Future<void> updateFields({
    required String id,
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
    await (_db.update(_db.pendingTickets)..where((t) => t.id.equals(id))).write(
      _rowCompanion(
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
      ).copyWith(repairableField: const Value(null)),
    );
  }

  Future<PendingTicket?> getById(String id) async {
    return (_db.select(_db.pendingTickets)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Rows in [state] — plus, when [autoRetryableOnly], the exclusion that keeps a row waiting on a
  /// human out of an automatic sweep. It is a property of the query rather than a branch in the
  /// caller's loop, so a repaired row re-enters the sweep by the same path every other row uses:
  /// the flag is null again, and there is nothing left to exclude it.
  Future<List<PendingTicket>> getByState(
    PendingTicketState state, {
    bool autoRetryableOnly = false,
  }) async {
    final query = _db.select(_db.pendingTickets)
      ..where((t) => t.state.equals(state.toPersistedString()));
    if (autoRetryableOnly) query.where((t) => t.repairableField.isNull());
    return query.get();
  }

  /// Everything not yet successfully submitted — surfaced in the UI so a
  /// technician can see it, and, for `failed` rows, retry manually.
  Stream<List<PendingTicket>> watchUnresolved() {
    return (_db.select(_db.pendingTickets)
          ..where((t) => t.state.equals(PendingTicketState.submitted.toPersistedString()).not())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<void> updateState({
    required String id,
    required PendingTicketState state,
    String? error,
    bool clearError = false,
  }) async {
    await (_db.update(_db.pendingTickets)..where((t) => t.id.equals(id))).write(
      PendingTicketsCompanion(
        state: Value(state.toPersistedString()),
        error: clearError || error == null ? const Value(null) : Value(error),
      ),
    );
  }

  /// A failed attempt, with the field the server blamed when it named one.
  ///
  /// [repairableField] is written in the same statement as the state, so the flag can never
  /// describe a different failure than the one stored beside it — null clears a flag left by an
  /// earlier rejection, which is what happens when the same row fails this time for an unrelated
  /// reason (a timeout, say).
  Future<void> markFailed({
    required String id,
    required String error,
    String? repairableField,
  }) async {
    await (_db.update(_db.pendingTickets)..where((t) => t.id.equals(id))).write(
      PendingTicketsCompanion(
        state: Value(PendingTicketState.failed.toPersistedString()),
        error: Value(error),
        repairableField: Value(repairableField),
      ),
    );
  }

  Future<void> markSubmitted({required String id, required String serverTicketId}) async {
    await (_db.update(_db.pendingTickets)..where((t) => t.id.equals(id))).write(
      PendingTicketsCompanion(
        state: Value(PendingTicketState.submitted.toPersistedString()),
        serverTicketId: Value(serverTicketId),
        error: const Value(null),
      ),
    );
  }
}
