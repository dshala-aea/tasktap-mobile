import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart';
import '../../data/tickets/ticket_attachment_upload_queue_watcher.dart';
import '../../data/tickets/ticket_creation_queue_watcher.dart';
import '../admin/admin_api_client.dart';
import 'ticket_detail_api_client.dart';
import 'ticket_workflow_api_client.dart';

/// All cached tickets, most-recent first.
final ticketsProvider = StreamProvider.autoDispose<List<Ticket>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.tickets,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
});

/// Tickets created locally that are not yet confirmed by the server:
/// waiting for connectivity, currently submitting, or failed (needs a
/// manual retry). Surfaced on the ticket list so nothing typed offline is
/// invisible to the technician.
final pendingTicketsProvider = StreamProvider.autoDispose<List<PendingTicket>>((
  ref,
) {
  return ref.watch(pendingTicketRepositoryProvider).watchUnresolved();
});

/// Map of statusId → Italian status name from cached TicketStatuses table.
final ticketStatusMapProvider = StreamProvider.autoDispose<Map<int, String>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db
      .select(db.ticketStatuses)
      .watch()
      .map((rows) => {for (final r in rows) r.id: r.name});
});

/// Map of typeId → type name from cached TicketTypes table.
final ticketTypeMapProvider = StreamProvider.autoDispose<Map<int, String>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db
      .select(db.ticketTypes)
      .watch()
      .map((rows) => {for (final r in rows) r.id: r.name});
});

/// All schedules for a specific ticket id.
final schedulesForTicketProvider = StreamProvider.autoDispose
    .family<List<Schedule>, String>((ref, ticketId) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.schedules)
            ..where((s) => s.ticketId.equals(ticketId))
            ..orderBy([(s) => OrderingTerm.asc(s.activityDate)]))
          .watch();
    });

// ══════════════════════════════════════════════════════════════════════════════
// Ticket-detail tabs with no local mirror (Report / Controllo / Allegati /
// Fabbisogno) — fetched on demand from the backend. None of these are ever
// written by SyncService, so "no data" and "couldn't fetch it" must stay
// distinguishable: each provider checks connectivity itself and throws
// [TicketDetailOfflineException] before attempting a request when offline,
// rather than letting Dio's own network error stand in for it.
// ══════════════════════════════════════════════════════════════════════════════

/// Rapportini recorded against a ticket (Report tab).
final ticketReportsProvider = FutureProvider.autoDispose
    .family<List<TicketReportSummary>, String>((ref, ticketId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(ticketDetailApiClientProvider);
      return api.fetchReportsForTicket(ticketId);
    });

/// Files uploaded directly to a ticket (Allegati tab).
final ticketAttachmentsProvider = FutureProvider.autoDispose
    .family<List<TicketAttachmentDto>, String>((ref, ticketId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(ticketDetailApiClientProvider);
      return api.fetchAttachments(ticketId);
    });

/// Attachments picked from this ticket's Allegati tab that have not yet reached the server —
/// waiting for connectivity, currently uploading, or failed (needs a manual retry). Surfaced
/// alongside [ticketAttachmentsProvider] so nothing captured offline is invisible, mirroring how
/// [pendingTicketsProvider] sits beside the confirmed ticket list.
final pendingTicketAttachmentsProvider = StreamProvider.autoDispose
    .family<List<PendingTicketAttachment>, String>((ref, ticketId) {
      return ref.watch(pendingTicketAttachmentRepositoryProvider).watchForTicket(ticketId);
    });

/// A ticket's checklist, resolved from the maintenance-template version it
/// materialised at creation (ADR-0012). Shared by the Controllo tab
/// (read-only) and the rapportino Controlli step (interactive).
final ticketControlsProvider = FutureProvider.autoDispose
    .family<List<TicketControlGroupDto>, String>((ref, ticketId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(ticketDetailApiClientProvider);
      return api.fetchControls(ticketId);
    });

/// Materials planned for a ticket — fabbisogno (Fabbisogno tab).
///
/// Local-Drift-backed, unlike the five sibling ticket-detail providers below (Rapportini,
/// Controls, Attachments, Worklogs, History) — TicketMateriali syncs to the device
/// (MobileUserSyncResult.TicketMateriali, office-set/low-volatility like the materiali catalog
/// itself), so this works offline. Returns the same [TicketMaterialeDto] shape the online
/// fetch used to, so both existing consumers (ticket_detail_screen.dart,
/// step_materiali_fold.dart) needed no changes — just resolved from the local mirror + local
/// materiali catalog instead of parsed from a network response.
final ticketMaterialiProvider = StreamProvider.autoDispose
    .family<List<TicketMaterialeDto>, String>((ref, ticketId) {
      final db = ref.watch(appDatabaseProvider);
      final query = db.select(db.ticketMateriali)..where((m) => m.ticketId.equals(ticketId));
      return query.watch().asyncMap((rows) async {
        final materialeIds = rows
            .where((r) => r.materialeId != null)
            .map((r) => r.materialeId!)
            .toSet();
        final catalog = materialeIds.isEmpty
            ? const <MaterialiData>[]
            : await (db.select(db.materiali)..where((m) => m.id.isIn(materialeIds))).get();
        final catalogById = {for (final c in catalog) c.id: c};

        return [
          for (final r in rows)
            TicketMaterialeDto(
              id: r.id,
              materialeId: r.materialeId,
              codice: r.materialeId != null ? catalogById[r.materialeId]?.code : null,
              // Free-text items name themselves; a catalog reference resolves through the
              // synced catalog — same precedence the online endpoint's own resolution used.
              nome: r.materialeId != null
                  ? (catalogById[r.materialeId]?.name ?? r.freeTextName ?? '')
                  : (r.freeTextName ?? ''),
              quantita: r.quantity,
              unitaMisura: r.unitOfMeasure ?? catalogById[r.materialeId]?.unitOfMeasure,
              note: r.notes,
              disponibile: r.isAvailable,
            ),
        ];
      });
    });

/// Time booked against a ticket, newest first — and the one entry still running, if any.
///
/// Online-only for the same reason the writes are: there is no local mirror of ticket worklogs,
/// and inventing one would mean showing a technician a timer state the server may already
/// disagree with.
final ticketWorklogsProvider = FutureProvider.autoDispose
    .family<List<TicketWorkLogDto>, String>((ref, ticketId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(ticketWorkflowApiClientProvider);
      return api.fetchWorklogs(ticketId);
    });

/// The running entry on this ticket, or null.
///
/// Derived from [ticketWorklogsProvider] rather than fetched separately so the timer bar and the
/// entry list can never disagree about whether a clock is going.
final runningTicketWorklogProvider = Provider.autoDispose
    .family<TicketWorkLogDto?, String>((ref, ticketId) {
      final entries = ref.watch(ticketWorklogsProvider(ticketId)).valueOrNull;
      if (entries == null) return null;
      for (final e in entries) {
        if (e.isRunning) return e;
      }
      return null;
    });

/// A ticket's field-by-field audit trail.
final ticketHistoryProvider = FutureProvider.autoDispose
    .family<List<TicketHistoryEntryDto>, String>((ref, ticketId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(ticketWorkflowApiClientProvider);
      return api.fetchHistory(ticketId);
    });

/// The contract a ticket is tied to (feature audit module #11, Gap D) — keyed by `contractId`,
/// not `ticketId`, so a cantiere or another ticket pointing at the same contract shares this
/// provider's cache rather than each issuing its own fetch.
///
/// Live-fetched, same as [AdminApiClient.fetchContractById]'s own doc comment explains: contracts
/// have no local Drift mirror, only `Tickets.contractId` (a bare id column, synced) does. Online-
/// only for the same reason every other tab on this screen without a mirror is.
final contractByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, contractId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(adminApiClientProvider);
      return api.fetchContractById(contractId);
    });

/// The commessa a ticket or cantiere is tagged with (feature audit module #13, Gap 6) — keyed by
/// `commessaId`, not by the ticket/cantiere it belongs to, so a ticket and its cantiere pointing
/// at the same commessa share this provider's cache rather than each issuing its own fetch.
///
/// Live-fetched, same reasoning as [contractByIdProvider]: commesse have no local Drift mirror,
/// only `Tickets.commessaId`/`Cantieri.commessaId` (bare id columns, synced) do.
final commessaByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, commessaId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const TicketDetailOfflineException();
      }
      final api = ref.watch(adminApiClientProvider);
      return api.fetchCommessaById(commessaId);
    });
