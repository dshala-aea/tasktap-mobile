// dart format width=100
import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'pending_ticket_attachment_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PendingTicketAttachmentRepository
//
// All CRUD for the pending_ticket_attachments local outbox. Zero network —
// mirrors PendingTicketRepository's shape.
// ══════════════════════════════════════════════════════════════════════════════

class PendingTicketAttachmentRepository {
  PendingTicketAttachmentRepository(this._db);

  final AppDatabase _db;

  /// Insert a new local-only pending attachment row.
  Future<void> insert({
    required String id,
    required String ticketId,
    required String localPath,
    required String fileName,
    required String contentType,
    required int sizeBytes,
    required PendingTicketAttachmentState state,
  }) async {
    await _db
        .into(_db.pendingTicketAttachments)
        .insert(
          PendingTicketAttachmentsCompanion.insert(
            id: id,
            createdAt: DateTime.now().toUtc(),
            ticketId: ticketId,
            localPath: localPath,
            fileName: fileName,
            contentType: contentType,
            sizeBytes: sizeBytes,
            state: Value(state.toPersistedString()),
          ),
        );
  }

  Future<PendingTicketAttachment?> getById(String id) async {
    return (_db.select(
      _db.pendingTicketAttachments,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  Future<List<PendingTicketAttachment>> getByState(PendingTicketAttachmentState state) async {
    return (_db.select(
      _db.pendingTicketAttachments,
    )..where((a) => a.state.equals(state.toPersistedString()))).get();
  }

  /// Everything not yet successfully uploaded for a given ticket — surfaced in the Allegati tab
  /// alongside the server-confirmed list so nothing picked offline is invisible to the
  /// technician. Once a row reaches `submitted` it drops out here; the real attachment then shows
  /// up through the normal server fetch instead.
  Stream<List<PendingTicketAttachment>> watchForTicket(String ticketId) {
    return (_db.select(_db.pendingTicketAttachments)
          ..where((a) => a.ticketId.equals(ticketId))
          ..where((a) => a.state.equals(PendingTicketAttachmentState.submitted.toPersistedString()).not())
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
        .watch();
  }

  Future<void> updateState({
    required String id,
    required PendingTicketAttachmentState state,
    String? error,
    bool clearError = false,
  }) async {
    await (_db.update(_db.pendingTicketAttachments)..where((a) => a.id.equals(id))).write(
      PendingTicketAttachmentsCompanion(
        state: Value(state.toPersistedString()),
        error: clearError || error == null ? const Value(null) : Value(error),
      ),
    );
  }

  Future<void> markSubmitted({required String id, required String serverAttachmentId}) async {
    await (_db.update(_db.pendingTicketAttachments)..where((a) => a.id.equals(id))).write(
      PendingTicketAttachmentsCompanion(
        state: Value(PendingTicketAttachmentState.submitted.toPersistedString()),
        serverAttachmentId: Value(serverAttachmentId),
        error: const Value(null),
      ),
    );
  }
}
