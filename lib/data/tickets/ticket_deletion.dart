// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ticket/ticket_workflow_api_client.dart';
import '../local/app_database.dart';
import '../sync/sync_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TicketDeletionService
//
// Removing a ticket from the device. Two genuinely different operations behind
// one seam, because the two kinds of ticket live in two different places:
//
//   - a ticket that only ever existed on this device (`pending_tickets`, the
//     create-path outbox) is pure local state — no network, never refused for
//     being offline;
//   - a ticket the server has (`tickets`) is deleted server-side first, and
//     only then dropped locally.
//
// There is no delete outbox and none is invented here: a server-side delete
// attempted offline is REFUSED (see [TicketDeleteOfflineException]) rather than
// queued. Queueing it would mean a ticket the technician watched disappear
// silently survives until some later reconnect — the "silently no-op" failure
// this exists to avoid.
// ══════════════════════════════════════════════════════════════════════════════

/// A server-side delete was refused because the device has no connection.
///
/// Carries the sentence the UI shows verbatim — deleting a ticket that exists server-side needs the
/// server, and saying so plainly is the whole point (there is no local delete to fall back on).
class TicketDeleteOfflineException implements Exception {
  const TicketDeleteOfflineException();

  @override
  String toString() =>
      'Per eliminare un ticket già inviato serve la connessione. Riprova quando hai segnale.';
}

class TicketDeletionService {
  TicketDeletionService({required AppDatabase db, required TicketWorkflowApiClient api})
    : _db = db,
      _api = api;

  final AppDatabase _db;
  final TicketWorkflowApiClient _api;

  /// Remove a ticket that only ever existed on this device (a `PendingTickets` row).
  ///
  /// Pure local cleanup: no network, so it never fails on connectivity and is always available.
  /// This is the ticket in the ClickUp title — created offline so the create request never left the
  /// device, or refused by the server and no longer wanted — and it must be removable with no
  /// signal at all.
  Future<void> deleteLocalOnly(String localId) => _removeLocalRows(localId);

  /// Remove a ticket the server has.
  ///
  /// [isOnline] is supplied by the caller (the UI reads `isOnlineProvider`) rather than read here,
  /// matching how `TicketCreationQueue.create` takes `isOnline` — the same "the queue never decides
  /// what the radio is doing" split. Offline, this refuses by throwing
  /// [TicketDeleteOfflineException]: there is no local delete outbox, and inventing one would mean
  /// the ticket silently survives until some later reconnect.
  ///
  /// The server call treats a 404 as success (see `TicketWorkflowApiClient.deleteTicket`); the local
  /// rows are dropped only once that call has succeeded or answered 404.
  Future<void> deleteServerTicket({required String ticketId, required bool isOnline}) async {
    if (!isOnline) throw const TicketDeleteOfflineException();
    await _api.deleteTicket(ticketId);
    await _removeLocalRows(ticketId);
  }

  /// Drops every local row keyed by this ticket id, in one transaction.
  ///
  /// The Drift schema declares no foreign keys on any of these tables — `references(...)` appears
  /// exactly once (on `ScheduleAssignees.scheduleId`) and no `foreign_keys` pragma is enabled — so
  /// nothing cascades and each row that points at the ticket has to be removed explicitly here or
  /// it is orphaned. `tickets`/`pendingTickets` are the row itself (whichever table it lived in);
  /// the rest are the ticket-owned children the sync mirrors upsert but never prune
  /// (`SyncService._upsertTickets` upserts without pruning, so a deleted ticket is never
  /// resurrected — but its children would sit on the device forever). There is no local mirror of
  /// ticket worklogs (`ticketWorklogsProvider` is online-only), so there is nothing to remove for
  /// those; and a `DraftReports`/`CantierePunches` row merely referencing the ticket is a
  /// technician's own queued work, deliberately not deleted.
  Future<void> _removeLocalRows(String ticketId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.tickets)..where((t) => t.id.equals(ticketId))).go();
      await (_db.delete(_db.pendingTickets)..where((t) => t.id.equals(ticketId))).go();
      await (_db.delete(
        _db.pendingTicketAttachments,
      )..where((a) => a.ticketId.equals(ticketId))).go();
      await (_db.delete(_db.ticketMateriali)..where((m) => m.ticketId.equals(ticketId))).go();
      await (_db.delete(
        _db.cachedTicketControls,
      )..where((c) => c.ticketId.equals(ticketId))).go();
      await (_db.delete(_db.ticketControls)..where((c) => c.ticketId.equals(ticketId))).go();
      await (_db.delete(_db.ticketAssets)..where((a) => a.ticketId.equals(ticketId))).go();
      await (_db.delete(
        _db.checklistOmittedTickets,
      )..where((o) => o.ticketId.equals(ticketId))).go();
      await (_db.delete(_db.schedules)..where((s) => s.ticketId.equals(ticketId))).go();
    });
  }
}

final ticketDeletionServiceProvider = Provider<TicketDeletionService>((ref) {
  return TicketDeletionService(
    db: ref.watch(appDatabaseProvider),
    api: ref.watch(ticketWorkflowApiClientProvider),
  );
});
