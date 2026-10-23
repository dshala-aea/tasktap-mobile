import 'package:dio/dio.dart' show DioException;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../data/attachments/attachment_content_cache.dart' show AllegatoEntityType;
import '../../data/local/app_database.dart';
import '../../data/reference/reference_cache_repository.dart' show referenceCacheProvider;
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart';
import '../../data/tickets/ticket_attachment_upload_queue_watcher.dart';
import '../../data/tickets/ticket_creation_queue_watcher.dart';
import '../../data/timbratura/ticket_timer_sync_service.dart'
    show ticketTimerRepositoryProvider;
import '../admin/admin_api_client.dart';
import '../checklist/checklist_providers.dart' show checklistReadRepositoryProvider;
import 'ticket_controls_mirror.dart';
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

/// Queued tickets the server rejected for a reference this client can repair: their
/// `repairableField` names the request field that would fail identically on any resend, so the
/// queue has taken them out of both automatic retry sweeps and they are waiting on a human.
///
/// Read-only, and deliberately so — the UI observes that a row is repairable; it never decides it.
/// What qualifies, and the repair that clears it, belong to `TicketCreationQueue`
/// (`repairableFieldOf` / `repair`). A repair nulls the column, the row leaves this stream and
/// re-enters the ordinary retry path by the same route every other row uses.
final repairablePendingTicketsProvider =
    StreamProvider.autoDispose<List<PendingTicket>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.pendingTickets,
      )..where((t) => t.repairableField.isNotNull())).watch();
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

/// Full cached TicketStatuses rows, ordered by id — used wherever `isDefault`/
/// `isClosed` or a stable display order is needed (unlike `ticketStatusMapProvider`,
/// whose `Map&lt;int, String&gt;` shape discards both columns and whose iteration
/// order is whatever SQLite happens to return, not a meaningful sequence).
final ticketStatusesProvider = StreamProvider.autoDispose<List<TicketStatuse>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.ticketStatuses,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();
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

/// The maintenance-template catalogue the create wizard's "Modello checklist" picker reads.
///
/// Rows, not a `Map<id, name>` like [ticketTypeMapProvider]: the picker has to answer two questions
/// the name alone cannot — whether new work may resolve the template ([MaintenanceTemplate.isActive])
/// and which version it would resolve to ([MaintenanceTemplate.latestPublishedVersion]) — so the
/// whole row has to reach the widget. Mirrors [ticketStatusesProvider]'s shape for that reason.
///
/// The whole catalogue is returned; narrowing it to what may be *attached* is
/// [assignableMaintenanceTemplates]' job, kept separate so it is testable without a widget.
final maintenanceTemplatesProvider =
    StreamProvider.autoDispose<List<MaintenanceTemplate>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.maintenanceTemplates,
      )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
    });

/// The templates a *new* ticket may be pinned to: active, and with a published version to snapshot.
///
/// An inactive template is hidden because no new work may resolve it, and one with no
/// [MaintenanceTemplate.latestPublishedVersion] is hidden because attaching it would record nothing
/// — both are exactly the web form's `assignableTemplates` filter
/// (`TicketCreatePanel.tsx`: `isActive && latestPublishedVersion != null`). Kept as a pure function
/// beside the provider so the filter is testable on its own, and so the widget cannot drift from it.
///
/// The catalogue is NOT filtered at the source: an inactive template a queued ticket still points at
/// must stay nameable on the device (see the table's doc comment), which a source-side filter would
/// make impossible.
List<MaintenanceTemplate> assignableMaintenanceTemplates(
  Iterable<MaintenanceTemplate> rows,
) => rows
    .where((t) => t.isActive && t.latestPublishedVersion != null)
    .toList(growable: false);

/// The template id a *send* may carry: [chosenId] when the catalogue still offers it, else null.
///
/// The picker already refuses to *display* a choice the catalogue no longer offers — it falls back
/// to the "Nessuna" option, because `DropdownButtonFormField` asserts its value is one of its items —
/// while the form state keeps the id, so that a repair does not silently rewrite a choice the user
/// made. A send must not be where that gap leaks: nothing clears a queued row's stale id except the
/// next sync ([SyncService._clearStalePendingTemplateIds], which only knows about templates the
/// server stopped *listing*), so a template the server still lists but no longer offers for new work
/// — retired, or with nothing published — stays on the row and would be handed to `POST /api/tickets`.
/// The server answers that with `400 Maintenance template not found`, and a 400 carries no `field`,
/// so `TicketCreationQueue` can never classify the row repairable: it would resend the same doomed id
/// on every retry, forever and invisibly. Null instead is the server's documented fallback — resolve
/// from type/contract — so the work is still created, with the pick unset, which is the state the
/// picker was already showing.
///
/// The rule is the picker's own on purpose: an id the picker will not offer is an id a send must not
/// carry, and the two cannot drift because both call [assignableMaintenanceTemplates]. Null in, null
/// out — "no choice" is always sendable.
///
/// An entirely empty [catalogue] means this device has not synced one at all: there is nothing to
/// judge the choice against, so it is passed through rather than silently discarded — dropping a pick
/// on the strength of absent data is worse than sending one the server may refuse, and the next sync
/// still clears the row if the template really is gone. A catalogue that has rows but offers none of
/// them is a different case, and there the id is not offerable either.
String? offerableMaintenanceTemplateId(
  String? chosenId,
  Iterable<MaintenanceTemplate> catalogue,
) {
  if (chosenId == null) return null;
  final rows = catalogue.toList(growable: false);
  if (rows.isEmpty) return chosenId;
  return assignableMaintenanceTemplates(rows).any((t) => t.id == chosenId)
      ? chosenId
      : null;
}

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
// Ticket-detail tabs. Every one of them now answers offline from a Drift
// mirror the sync fills — Rapportini (O-8a/O-8b), Allegati (O-8b/O-8c),
// Controllo (its checklist mirror), Fabbisogno (the per-ticket materiali
// mirror, pruned to the server's scope) and Prodotti (the ticketAssets +
// assets rows, falling back to them on any transport/server fault). What is
// still online-only is the history: it checks connectivity itself and throws
// [TicketDetailOfflineException] before attempting a request, rather than
// letting Dio's own network error stand in for it: "no data" and "couldn't
// fetch it" must stay distinguishable.
// ══════════════════════════════════════════════════════════════════════════════

/// Rapportini recorded against a ticket (Report tab).
///
/// Online it asks the server, which is the only place that knows about reports this phone has
/// never seen. Offline it reads the Drift mirror, which O-8a now fills with every in-scope report's
/// header and children — so the tab keeps working, and tapping a row opens the read-only view (that
/// one already reads the mirror by id).
///
/// An empty mirror throws [TicketDetailOfflineException] rather than returning `[]`: the device
/// cannot tell "this ticket has no reports" from "none have reached this phone yet", and an empty
/// list would state the first as fact.
/// Online the two sources are MERGED, not switched between. The server is the only place that
/// knows about reports this phone has never seen, but it is the last place to know about the ones
/// this phone just made: a report created offline (or still queued for sending) has no server row
/// yet, so an online-only read made it disappear from its own ticket the moment the radio came
/// back — the work was queued and correct, and the tab said the ticket had no reports.
final ticketReportsProvider = FutureProvider.autoDispose
    .family<List<TicketReportSummary>, String>((ref, ticketId) async {
      final db = ref.watch(appDatabaseProvider);
      final rows = await (db.select(db.draftReports)
            ..where((r) => r.ticketId.equals(ticketId))
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .get();
      final local = rows
          .map(
            (r) => TicketReportSummary.fromMirror(
              id: r.id,
              title: r.title,
              stato: r.stato,
              createdAt: r.createdAt,
            ),
          )
          .toList();

      if (!ref.watch(isOnlineProvider)) {
        if (local.isEmpty) throw const TicketDetailOfflineException();
        return local;
      }

      final api = ref.watch(ticketDetailApiClientProvider);
      final server = await api.fetchReportsForTicket(ticketId);
      // Mirrored server rows carry the server's own id, so they collide with the server list and
      // drop out here; what survives is exactly the local-only work.
      final serverIds = {for (final r in server) r.id};
      return [...server, ...local.where((r) => !serverIds.contains(r.id))]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });

/// Prodotti in assistenza the ticket covers (Prodotti compartment): the ticket's coverage ids from
/// the server, then each prodotto's card.
///
/// Online the server's coverage ids are authoritative and each card is fetched live — the local
/// `ticket_assets` rows are not an authoritative coverage list (see
/// [TicketDetailApiClient.fetchCoveredProdottoIds]), they are what the sync last wrote.
///
/// Offline those mirror rows are the only answer this phone has, and they are what the checklist
/// card on the same tab already renders ([checklistReadRepositoryProvider]), so the compartment
/// stays readable on site instead of going blank. The card-shaped map holds the identity fields the
/// mirror keeps (`name`, `serialNumber`, `matricola`); `codice`/`marchio`/`modello` are not
/// mirrored and simply render as absent. An empty mirror throws, exactly like its siblings: nothing
/// on this phone is not the same fact as no asset on the ticket.
///
/// Online, a call that never arrived or a server fault degrades to those same mirror rows rather
/// than blanking the compartment — the technician is standing in front of the machine either way.
/// A 4xx still rethrows: it is the server answering about this ticket's coverage, not a failure to
/// answer.
final ticketProdottiProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, ticketId) async {
      List<Map<String, dynamic>> byName(List<Map<String, dynamic>> rows) => rows
        ..sort(
          (a, b) => ((a['name'] as String?) ?? '').toLowerCase().compareTo(
            ((b['name'] as String?) ?? '').toLowerCase(),
          ),
        );

      Future<List<Map<String, dynamic>>> fromMirror() async {
        final db = ref.watch(appDatabaseProvider);
        final query = db.select(db.ticketAssets).join([
          innerJoin(db.assets, db.assets.id.equalsExp(db.ticketAssets.prodottoAssistenzaId)),
        ])..where(db.ticketAssets.ticketId.equals(ticketId));
        final rows = await query.get();
        if (rows.isEmpty) throw const TicketDetailOfflineException();
        return byName(
          rows
              .map((row) {
                final asset = row.readTable(db.assets);
                return <String, dynamic>{
                  'id': asset.id,
                  'name': asset.name,
                  'serialNumber': asset.serialNumber,
                  'matricola': asset.matricola,
                };
              })
              .toList(),
        );
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          final ids = await ref
              .watch(ticketDetailApiClientProvider)
              .fetchCoveredProdottoIds(ticketId);
          final admin = ref.watch(adminApiClientProvider);
          final rows = await Future.wait(ids.map(admin.fetchProdottoAssistenzaById));
          return byName(rows.whereType<Map<String, dynamic>>().toList());
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromMirror();
    });

/// Files uploaded directly to a ticket (Allegati tab).
///
/// Server-authoritative online; offline it reads the mirror sync fills (`report_allegati`, with
/// [AllegatoEntityType.ticket]), so the files a technician already knows about stay listed on site.
/// An empty mirror throws rather than answering with nothing: the table is pruned to the ticket
/// scope on every sync, but it is also empty on a device that has not run one yet, and the tab
/// must not state "nessun allegato" when it simply does not know.
///
/// As with [ticketProdottiProvider], an online call that never arrived or hit a server fault
/// answers from the mirror instead — the files this phone already knows about are strictly better
/// than an error page on the tab the technician opened to check a photo got attached.
final ticketAttachmentsProvider = FutureProvider.autoDispose
    .family<List<TicketAttachmentDto>, String>((ref, ticketId) async {
      Future<List<TicketAttachmentDto>> fromMirror() async {
        final db = ref.watch(appDatabaseProvider);
        final rows =
            await (db.select(db.reportAllegati)
                  ..where(
                    (a) =>
                        a.entityType.equals(AllegatoEntityType.ticket) &
                        a.entityId.equals(ticketId) &
                        a.isActive.equals(true) &
                        a.isPendingUpload.equals(false),
                  )
                  ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
                .get();
        if (rows.isEmpty) throw const TicketDetailOfflineException();
        return rows
            .map(
              (a) => TicketAttachmentDto(
                id: a.id,
                fileName: a.fileName,
                contentType: a.contentType,
                sizeBytes: a.sizeBytes,
                contentUrl: a.url,
                createdAt: a.createdAt,
              ),
            )
            .toList();
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref.watch(ticketDetailApiClientProvider).fetchAttachments(ticketId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromMirror();
    });

/// Attachments picked from this ticket's Allegati tab that have not yet reached the server —
/// waiting for connectivity, currently uploading, or failed (needs a manual retry). Surfaced
/// alongside [ticketAttachmentsProvider] so nothing captured offline is invisible, mirroring how
/// [pendingTicketsProvider] sits beside the confirmed ticket list.
final pendingTicketAttachmentsProvider = StreamProvider.autoDispose
    .family<List<PendingTicketAttachment>, String>((ref, ticketId) {
      return ref
          .watch(pendingTicketAttachmentRepositoryProvider)
          .watchForTicket(ticketId);
    });

/// A ticket's checklist, resolved from the maintenance-template version it
/// materialised at creation (ADR-0012). Shared by the Controllo tab
/// (read-only) and the rapportino Controlli step (interactive).
///
/// Two explicit axes, never merged:
/// * online, the live fetch is the answer, returned as-is — it is the fresh truth;
/// * offline, the checklist is answered from the sync mirror with no network
///   call at all ([ticketControlGroupsFromMirror] rebuilds the server's tree
///   from `ticket_controls` + `control_groups`), so the tab is available with
///   the radio off instead of throwing [TicketDetailOfflineException].
///
/// A live fetch that throws degrades to the mirror rather than to an error
/// screen: a flaky connection should show the last known checklist.
///
/// An empty mirror throws [TicketDetailOfflineException] instead of answering
/// `[]`. The mirror cannot tell "this ticket has no template" from "its rows
/// have not reached this phone yet", and `[]` would state the first as fact —
/// a signed rapportino with a silently missing safety checklist. The same rule
/// its siblings already follow ([ticketReportsProvider],
/// [ticketAttachmentsProvider]). A genuinely empty *live* answer still yields
/// `[]`: online, the server did answer.
final ticketControlsProvider = FutureProvider.autoDispose
    .family<List<TicketControlGroupDto>, String>((ref, ticketId) async {
      final repository = ref.watch(checklistReadRepositoryProvider);

      Future<List<TicketControlGroupDto>> fromMirror() async {
        // One-shot reads: this provider answers once per build, so there is nothing for a query
        // stream subscription to deliver a second time. See the repository's own note.
        final controls = await repository.getTicketControlRows(ticketId);
        final groups = await repository.getControlGroups();
        final result = ticketControlGroupsFromMirror(controls: controls, groups: groups);
        if (result.isEmpty) throw const TicketDetailOfflineException();
        return result;
      }

      if (!ref.watch(isOnlineProvider)) {
        return fromMirror();
      }
      final api = ref.watch(ticketDetailApiClientProvider);
      try {
        return await api.fetchControls(ticketId);
      } catch (e) {
        debugPrint(
          'ticketControlsProvider($ticketId): live fetch failed ($e) — '
          'falling back to the local checklist mirror',
        );
        return fromMirror();
      }
    });

/// Materials planned for a ticket — fabbisogno (Fabbisogno tab).
///
/// Local-Drift-backed, unlike the sibling ticket-detail providers that still
/// fetch on demand (Rapportini, Attachments, Worklogs, History, and the
/// by-id lookups below) — TicketMateriali syncs to the device
/// (MobileUserSyncResult.TicketMateriali, office-set/low-volatility like the materiali catalog
/// itself), so this works offline. Returns the same [TicketMaterialeDto] shape the online
/// fetch used to, so both existing consumers (ticket_detail_screen.dart,
/// step_materiali_fold.dart) needed no changes — just resolved from the local mirror + local
/// materiali catalog instead of parsed from a network response.
final ticketMaterialiProvider = StreamProvider.autoDispose
    .family<List<TicketMaterialeDto>, String>((ref, ticketId) {
      final db = ref.watch(appDatabaseProvider);
      final query = db.select(db.ticketMateriali)
        ..where((m) => m.ticketId.equals(ticketId));
      return query.watch().asyncMap((rows) async {
        final materialeIds = rows
            .where((r) => r.materialeId != null)
            .map((r) => r.materialeId!)
            .toSet();
        final catalog = materialeIds.isEmpty
            ? const <MaterialiData>[]
            : await (db.select(
                db.materiali,
              )..where((m) => m.id.isIn(materialeIds))).get();
        final catalogById = {for (final c in catalog) c.id: c};

        return [
          for (final r in rows)
            TicketMaterialeDto(
              id: r.id,
              materialeId: r.materialeId,
              codice: r.materialeId != null
                  ? catalogById[r.materialeId]?.code
                  : null,
              // Free-text items name themselves; a catalog reference resolves through the
              // synced catalog — same precedence the online endpoint's own resolution used.
              nome: r.materialeId != null
                  ? (catalogById[r.materialeId]?.name ?? r.freeTextName ?? '')
                  : (r.freeTextName ?? ''),
              quantita: r.quantity,
              unitaMisura:
                  r.unitOfMeasure ?? catalogById[r.materialeId]?.unitOfMeasure,
              note: r.notes,
              disponibile: r.isAvailable,
            ),
        ];
      });
    });

/// Time booked against a ticket, newest first — and the one entry still running, if any.
///
/// Online the server's list is authoritative, but a session this device started and has not
/// managed to upload yet is still shown alongside it: the technician started it, and hiding a
/// running timer until the server confirms would invite a second one on another ticket.
/// Offline the mirror answers (sync fills it for the caller's own sessions, 90-day window plus
/// anything still running), and an empty mirror throws rather than drawing "no hours booked".
final ticketWorklogsProvider = FutureProvider.autoDispose
    .family<List<TicketWorkLogDto>, String>((ref, ticketId) async {
      final repo = ref.watch(ticketTimerRepositoryProvider);
      final rows = await repo.forTicket(ticketId);

      if (ref.watch(isOnlineProvider)) {
        final api = ref.watch(ticketWorkflowApiClientProvider);
        final pending = rows.where((r) => r.isPendingSync);
        final List<TicketWorkLogDto> server;
        try {
          server = await api.fetchWorklogs(ticketId);
        } on DioException {
          // The request died although the radio says online: the mirror is what there is.
          return _ticketWorklogsFromMirror(rows);
        }
        // Anything that is NOT a failed request (a payload this app cannot parse —
        // `parseDateOnlyOrThrow`) propagates: the tab's error state must say the hours could not
        // be loaded. Swallowing it would render "Nessuna ora registrata" over a server that does
        // hold hours.
        final merged = [...pending.map(ticketWorkLogFromTimer), ...server];
        merged.sortNewestFirst();
        return merged;
      }

      return _ticketWorklogsFromMirror(rows);
    });

List<TicketWorkLogDto> _ticketWorklogsFromMirror(
  List<TicketTimer> rows,
) {
  if (rows.isEmpty) {
    // An empty mirror is not evidence of "no hours booked": it may simply never have synced.
    // Saying so beats drawing a zero the technician cannot distinguish from real work.
    throw const TicketDetailOfflineException();
  }
  return rows.map(ticketWorkLogFromTimer).toList()..sortNewestFirst();
}

extension TicketWorkLogSorting on List<TicketWorkLogDto> {
  /// Newest first, and a running entry before a closed one on the same day — the order the
  /// online endpoint returns. An open session sorts last on its day by date alone, which would
  /// put the live timer below hours already booked.
  void sortNewestFirst() => sort((a, b) {
    final byDate = b.workDate.compareTo(a.workDate);
    if (byDate != 0) return byDate;
    if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
    return b.startTime.compareTo(a.startTime);
  });
}

/// A mirrored row in the shape the screens already render.
TicketWorkLogDto ticketWorkLogFromTimer(TicketTimer row) {
  final start = row.startUtc;
  final end = row.endUtc;
  final workDate = row.workDate;
  final startSeconds = row.startSeconds;
  if (workDate == null && start == null) {
    // Neither frame present: nothing truthful can be shown for this row.
    throw StateError('Timer ${row.id} has no date');
  }
  return TicketWorkLogDto(
    id: row.id,
    ticketId: row.ticketId,
    userId: row.userId,
    workDate: workDate ?? DateTime.utc(start!.year, start.month, start.day),
    startTime: startSeconds != null
        ? Duration(seconds: startSeconds)
        : Duration(
            hours: start!.hour,
            minutes: start.minute,
            seconds: start.second,
          ),
    endTime: row.endSeconds == null ? null : Duration(seconds: row.endSeconds!),
    isManualEntry: row.isManualEntry,
    description: row.description,
    approvalStatus: row.approvalStatus?.toString(),
    // The instants are the truth when both are known: subtracting two bare times of day gives a
    // negative duration for an overnight session (see TicketWorkLogDto.duration's own comment).
    duration: start != null && end != null
        ? (end.isAfter(start) ? end.difference(start) : Duration.zero)
        : null,
  );
}

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
/// Online the server answers, because it is the only place that knows about an edit made in the
/// office a minute ago. When the request never arrived — the radio says online but there is no
/// response — or the server answered with its own fault, the synced mirror answers instead, and
/// offline it is the mirror from the start. A 4xx is never second-guessed: a 404 from the server
/// means the contract is gone, and showing a stale mirrored row would state otherwise.
///
/// The mirror has no `condizioni` (it is not part of the sync contract), so that field reads as
/// absent offline. It is shown as '—', not invented.
final contractByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, contractId) async {
      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref.watch(adminApiClientProvider).fetchContractById(contractId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      final row = await ref.watch(referenceCacheProvider).contractById(contractId);
      if (row == null) throw const TicketDetailOfflineException();
      return {
        'id': row.id,
        'name': row.name,
        'customerId': row.customerId,
        'locationId': row.locationId,
        // Re-stamped to UTC: this map stands in for the server's own contract JSON, whose dates
        // carry a `Z`. Drift hands a `DateTimeColumn` back as a LOCAL-kind instant, so without the
        // conversion a mirrored row's date can read as a different day from the server's copy.
        'startDate': row.startDate.toUtc().toIso8601String(),
        'endDate': row.endDate?.toUtc().toIso8601String(),
        'isActive': row.isActive,
        'numero': row.numero,
        'codice': row.codice,
        'externalId': row.externalId,
      };
    });

/// The commessa a ticket or cantiere is tagged with (feature audit module #13, Gap 6) — keyed by
/// `commessaId`, not by the ticket/cantiere it belongs to, so a ticket and its cantiere pointing
/// at the same commessa share this provider's cache rather than each issuing its own fetch.
///
/// Same online-then-mirror shape as [contractByIdProvider]. The mirror carries the fields a
/// technician reads on site (`codice`, `descrizione`, `stato`); the office-only detail screen
/// shows the rest as absent rather than as zero.
final commessaByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, commessaId) async {
      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref.watch(adminApiClientProvider).fetchCommessaById(commessaId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      final row = await ref.watch(referenceCacheProvider).commessaById(commessaId);
      if (row == null) throw const TicketDetailOfflineException();
      return {
        'id': row.id,
        'codice': row.codice,
        'descrizione': row.descrizione,
        'customerId': row.customerId,
        'stato': row.stato,
        'isActive': row.isActive,
        'externalId': row.externalId,
      };
    });

/// The prodotto assistenza a contract is tied to — keyed by `prodottoAssistenzaId`, same
/// online-then-mirror shape as [commessaByIdProvider]. The contract detail screen only has the id
/// (not the customer it belongs to), so the server path uses
/// [AdminApiClient.fetchProdottoAssistenzaById] rather than the customer-scoped
/// `fetchProdottiAssistenza` the contract/prodotto FORM screens use.
final prodottoAssistenzaByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, prodottoId) async {
      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref
              .watch(adminApiClientProvider)
              .fetchProdottoAssistenzaById(prodottoId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      final row = await ref
          .watch(referenceCacheProvider)
          .prodottoAssistenzaById(prodottoId);
      if (row == null) throw const TicketDetailOfflineException();
      return {
        'id': row.id,
        'name': row.name,
        'customerId': row.customerId,
        'locationId': row.locationId,
        'codice': row.codice,
        'serialNumber': row.serialNumber,
        'categoria': row.categoria,
        'marchio': row.marchio,
        'isActive': row.isActive,
        'externalId': row.externalId,
      };
    });
