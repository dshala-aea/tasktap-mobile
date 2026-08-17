// dart format width=100
import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'pending_ticket_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PendingTicketRepository
//
// All CRUD for the pending_tickets local outbox. Zero network — mirrors
// DraftReportRepository's shape for the submission-state slice.
// ══════════════════════════════════════════════════════════════════════════════

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
    required PendingTicketState state,
  }) async {
    await _db
        .into(_db.pendingTickets)
        .insert(
          PendingTicketsCompanion.insert(
            id: id,
            createdAt: DateTime.now().toUtc(),
            title: title,
            description: Value(description),
            customerId: customerId,
            locationId: locationId,
            assignedUserId: Value(assignedUserId),
            statusId: statusId,
            typeId: typeId,
            state: Value(state.toPersistedString()),
          ),
        );
  }

  Future<PendingTicket?> getById(String id) async {
    return (_db.select(_db.pendingTickets)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<PendingTicket>> getByState(PendingTicketState state) async {
    return (_db.select(
      _db.pendingTickets,
    )..where((t) => t.state.equals(state.toPersistedString()))).get();
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
