import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time.dart' show formatDateOnly;
import '../api/dio_client.dart';
import '../attachments/attachment_content_cache.dart'
    show AllegatoEntityType, attachmentPrefetcherProvider;
import '../local/app_database.dart';
import '../reference/reference_cache_repository.dart';
import '../timbratura/cantiere_session_repository.dart' show cantiereReconciledOrphanMarker;
import 'checklist_reconciler.dart';
import 'checklist_refetch_service.dart';
import 'draft_submission_state.dart';
import 'sync_dto.dart';

/// Calls GET /api/sync/mobile?since=[lastSync], upserts every entity into
/// Drift, and updates sync_meta.lastSync.
///
/// Design contract:
/// - Idempotent: calling twice produces the same result.
/// - Delta-aware: uses lastSync as the `since` param; null → full sync.
/// - Offline-safe: throws if the network call fails; the caller decides retry.
class SyncService {
  SyncService({required this.db, required this.dio});

  final AppDatabase db;
  final Dio dio;

  static const _path = '/api/sync/mobile';

  /// Owns the re-request of checklists the server omitted from a sync (bounded, batched, and
  /// self-disabling — see that class's own doc comment).
  late final ChecklistRefetchService checklistRefetch = ChecklistRefetchService(db: db, dio: dio);

  /// Perform a delta sync.
  ///
  /// Returns the [DateTime] of the sync snapshot on success.
  /// Throws on network error (caller should surface this to the UI).
  Future<DateTime> sync() async {
    final lastSync = await db.getLastSync();
    final queryParams = <String, String>{};
    if (lastSync != null) {
      queryParams['since'] = lastSync.toUtc().toIso8601String();
    }

    final response = await dio.get<Map<String, dynamic>>(
      _path,
      queryParameters: queryParams,
    );

    final payload = SyncResultDto.fromJson(
      response.data as Map<String, dynamic>,
    );

    await db.transaction(() async {
      await _upsertCustomers(payload.customers);
      await _upsertLocations(payload.locations);
      await _upsertTickets(payload.tickets);
      await _upsertSchedules(payload.schedules);
      await _upsertDraftReports(payload.draftReports);
      // Reports this technician submitted that have since left the draft state (Inviato,
      // Controllato, Fatturato, Respinto, Annullato). Same upsert as drafts — the payload already
      // carries the server-authoritative `stato`/`inviatoAt`/etc — so this is what makes an
      // office rejection (POST /api/reports/{id}/respingi) actually show up on the device instead
      // of the phone never learning about it. See sync_dto.dart's `submittedReports` doc comment.
      await _upsertDraftReports(payload.submittedReports);
      // The full aggregate of those reports (children, files, versions) — after both header
      // upserts, because a child is only written for a report row this device already holds.
      await _applyReportAggregate(payload);
      await _upsertTicketStatuses(payload.ticketStatuses);
      await _upsertTicketTypes(payload.ticketTypes);
      await _upsertMateriali(payload.materiali);
      await _replaceTicketMateriali(payload);
      await _upsertMaterialeBarcodes(payload.materialiBarcodes);
      await _upsertCantieri(payload.cantieri);
      await _replaceCantiereCrewAssignments(payload);
      await _replaceColleagues(payload.colleagues);
      await _applyReferenceCache(payload);
      await _replaceMaintenanceTemplates(payload);
      // What unsent local work still points at, computed once and used twice: the instrument
      // catalogue's wholesale replace must keep a pinned instrument, and the prune below must
      // keep every pinned row. Both happen after every upsert, inside this transaction.
      final pins = await _collectUnsentPins();
      await _applyChecklist(payload, pins);
      // The authoritative-scope prune runs after every upsert in the SAME transaction, so no
      // reader ever observes a half-pruned mirror.
      await _pruneToScope(payload, pins);
    });

    await db.setLastSync(payload.syncedAt);

    // Best effort and bounded: a failed re-request must never fail (or delay the result of) the
    // sync that already succeeded. The omitted ids stay remembered for the next one.
    try {
      await checklistRefetch.refetchOmitted();
    } catch (e) {
      debugPrint('sync: omitted checklist re-request failed ($e)');
    }

    return payload.syncedAt;
  }

  /// The per-asset checklist mirror and the instrument catalogue. Skipped member by member when the
  /// payload does not carry it: an older backend must never look like "everything is empty".
  Future<void> _applyChecklist(SyncResultDto payload, _UnsentPins pins) async {
    if (payload.carriesChecklist) {
      final withLocal = await ticketIdsWithLocalChecklist(db);
      await applyChecklistBatch(
        db,
        ChecklistBatch.fromSync(
          payload,
          payloadTicketIds: payload.tickets.map((t) => t.id).toSet(),
          ticketsWithLocalChecklist: withLocal,
        ),
      );
      await pruneOmittedWithoutTicket(db);
    }
    if (payload.carriesStrumenti) {
      // `scope.strumenti == null` (with `scope` present) is the server saying it has no
      // authoritative instrument set for this caller — and the `strumenti: []` that travels with
      // it is the absence of a set, not an authoritative empty one. Replacing the catalogue on it
      // would delete a cached instrument (including one an unsent draft still references) over a
      // permission change, which is exactly what the scope prune is forbidden to do.
      final scope = payload.scope;
      if (scope == null || scope.strumenti != null) {
        await replaceStrumenti(db, payload.strumenti, keepIds: pins.strumenti);
      }
      await replaceServerReportStrumenti(
        db,
        reportIdsInPayload: [...payload.draftReports, ...payload.submittedReports].map((r) => r.id),
        rows: payload.reportStrumenti,
      );
    }
  }

  /// The reference mirror. Each entity is skipped wholesale when the payload does not carry it —
  /// an older backend must not look like "every reference row was deleted" — and pruned only for
  /// the customers this payload actually carries. See [ReferenceCacheRepository].
  Future<void> _applyReferenceCache(SyncResultDto payload) async {
    final cache = ReferenceCacheRepository(db);

    if (payload.carriesContracts) {
      await cache.upsertContracts(payload.contracts);
      await cache.pruneContracts(
        presentCustomerIds: payload.customers.map((c) => c.id).toSet(),
        keepContractIds: payload.contracts.map((c) => c.id).toSet(),
      );
    }
    if (payload.carriesCommesse) {
      await cache.upsertCommesse(payload.commesse);
      await cache.pruneCommesse(
        presentCustomerIds: payload.customers.map((c) => c.id).toSet(),
        keepCommessaIds: payload.commesse.map((c) => c.id).toSet(),
      );
    }
    if (payload.carriesProdottiAssistenza) {
      await cache.upsertProdottiAssistenza(payload.prodottiAssistenza);
      await cache.pruneProdottiAssistenza(
        presentCustomerIds: payload.customers.map((c) => c.id).toSet(),
        keepProdottiIds: payload.prodottiAssistenza.map((p) => p.id).toSet(),
      );
    }
    if (payload.carriesAgents) {
      // No prune: see ReferenceCacheRepository.
      await cache.upsertAgents(payload.agents);
    }
  }

  /// The maintenance-template catalogue the create wizard's "Modello checklist" picker reads.
  ///
  /// Replaced wholesale rather than upserted, for the same reason [_replaceColleagues] is: the
  /// server sends the whole visible set with no delta filter, so a template that is no longer
  /// offered — deleted, or simply no longer visible to this technician — must stop appearing, and an
  /// upsert would leave it in the picker forever. Skipped entirely when the payload does not carry
  /// the member, so an older backend cannot look like "every template was deleted" and wipe the
  /// catalogue.
  ///
  /// The empty-list branch below is narrower than it reads. As the API stands the member is *always*
  /// serialized — `MobileUserSyncResult.MaintenanceTemplates` is assigned unconditionally, so a
  /// caller without `rapportini.template.read` gets `"maintenanceTemplates": []` rather than an
  /// absent key — which makes `carriesMaintenanceTemplates` de-facto always true, and a
  /// carried-but-empty list means "this caller was not granted the catalogue", not "the catalogue is
  /// empty". Pruning on it, the way [_applyReferenceCache] prunes on a carried-but-empty delta, would
  /// blank a technician's picker the moment their permissions changed, so it does not. The cost of
  /// not pruning is bounded and accepted: a sync can never empty the catalogue, so a template the
  /// server stops offering survives in the mirror until sign-out, and only a queued ticket's *choice*
  /// is corrected (below). Telling the two cases apart needs the server to omit the member when
  /// `includeMaintenanceTemplates` is false; until then this stays as it is.
  ///
  /// A queued ticket pinned to a template that just left the catalogue has its choice cleared in the
  /// same transaction — see [_clearStalePendingTemplateIds] for why that has to happen here.
  Future<void> _replaceMaintenanceTemplates(SyncResultDto payload) async {
    if (!payload.carriesMaintenanceTemplates) return;
    final list = payload.maintenanceTemplates;
    // An empty carried list is the caller-without-permission case (see the doc comment), so it must
    // not read as "the catalogue is now empty". Returning here is also what guarantees [keepIds]
    // below is never empty, which [_clearStalePendingTemplateIds] depends on.
    if (list.isEmpty) return;

    await db.transaction(() async {
      await db.delete(db.maintenanceTemplates).go();
      await db.batch(
        (b) => b.insertAll(
          db.maintenanceTemplates,
          list.map(
            (t) => MaintenanceTemplatesCompanion.insert(
              id: t.id,
              origin: t.origin,
              name: t.name,
              description: Value(t.description),
              isActive: Value(t.isActive),
              latestPublishedVersion: Value(t.latestPublishedVersion),
            ),
          ),
        ),
      );
      await _clearStalePendingTemplateIds(list.map((t) => t.id).toSet());
    });
  }

  /// Drops the maintenance-template choice off any queued ticket whose template is no longer in the
  /// catalogue that just arrived.
  ///
  /// Without this the pending row would keep a `maintenanceTemplateId` the server now answers with
  /// `400 Maintenance template not found`. That 400 carries no `field`, so the create queue cannot
  /// classify it repairable (its rule is 404-plus-known-field only — see TicketCreationQueue) and the
  /// row would resend the same doomed id on every retry, forever and invisibly. Clearing the choice
  /// lets the ticket resolve like any other unset pick — the server falls back to type/contract — so
  /// the work still gets created.
  ///
  /// Only rows that still carry a value, and only values missing from [keepIds], are touched; a null
  /// stays null. The caller returned early on an empty catalogue, so [keepIds] is never empty here:
  /// this can never blank a choice that is merely not yet on this device.
  Future<void> _clearStalePendingTemplateIds(Set<String> keepIds) async {
    await (db.update(db.pendingTickets)..where(
          (t) =>
              t.maintenanceTemplateId.isNotNull() &
              t.maintenanceTemplateId.isNotIn(keepIds),
        ))
        .write(const PendingTicketsCompanion(maintenanceTemplateId: Value(null)));
  }

  // ── Authoritative scope (sync v2) ──────────────────────────────────────────
  //
  // The payload has always been upsert-only, so the mirror kept every row that ever left scope:
  // a schedule past the ±7-day window, a ticket reassigned to a colleague, a report older than
  // the 90-day window, a deactivated material, a deleted customer, a removed instrument. `scope`
  // is the server's complete in-scope id set per collection, and this is what finally deletes
  // what is absent from it.
  //
  // Three rules keep the prune from becoming a data-loss path:
  //  * no `scope` → no prune. An older backend omits it, and the wire spells that as null.
  //  * a null MEMBER → no prune for that collection (`strumenti` for a caller without
  //    `team.strumento.read`). `[]` is different and authoritative: nothing is in scope.
  //  * an unsent local piece of work pins every row it references. Pinned rows are kept as
  //    ordinary, visible rows — no hidden flag — because a technician must still be able to open
  //    the ticket a draft is being written against, and the queue must still be able to send it.

  /// Ids that unsent local work still references. Deriving them from the same queues
  /// `UnsentWorkCounter` counts is deliberate: "unsent" must mean one thing on this device.
  Future<_UnsentPins> _collectUnsentPins() async {
    final pins = _UnsentPins();
    final submitted = DraftSubmissionState.submitted.toPersistedString();

    // Local rapportini not yet submitted — the counter's own predicate (`isLocalOnly` and not
    // `submitted`). A local-only row is never a prune candidate itself (rule: no manifest
    // describes it), and every row it points at has to survive with it.
    final drafts = await (db.select(db.draftReports)..where(
          (r) =>
              r.isLocalOnly.equals(true) &
              r.submissionState.equals(submitted).not(),
        ))
        .get();
    for (final d in drafts) {
      _addIfNotNull(pins.tickets, d.ticketId);
      _addIfNotNull(pins.customers, d.customerId);
      _addIfNotNull(pins.locations, d.locationId);
      _addIfNotNull(pins.cantieri, d.cantiereId);
      // A draft's schedule is a reference from unsent work too. Not on the minimum list, but
      // letting it leave would leave the editor pointing at a row the mirror no longer has.
      _addIfNotNull(pins.schedules, d.scheduleId);
    }
    if (drafts.isNotEmpty) {
      final ids = drafts.map((d) => d.id).toList();
      final materialRows =
          await (db.select(db.reportMateriali)..where((m) => m.reportId.isIn(ids))).get();
      for (final m in materialRows) {
        _addIfNotNull(pins.materiali, m.materialeId);
      }
      final strumentoRows =
          await (db.select(db.reportStrumenti)..where((s) => s.reportId.isIn(ids))).get();
      for (final s in strumentoRows) {
        _addIfNotNull(pins.strumenti, s.strumentoId);
      }
    }

    // Ticket-create outbox rows in any state but submitted: their customer/location/cantiere
    // must still be there when the queue retries, and for the repair affordance to name them.
    final pendingTickets = await (db.select(db.pendingTickets)..where(
          (t) => t.state.equals(submitted).not(),
        ))
        .get();
    for (final t in pendingTickets) {
      pins.customers.add(t.customerId);
      pins.locations.add(t.locationId);
      _addIfNotNull(pins.cantieri, t.cantiereId);
      _addIfNotNull(pins.agents, t.agentId);
    }

    // Ticket-attachment outbox rows: they point at a ticket.
    final pendingAttachments = await (db.select(db.pendingTicketAttachments)..where(
          (a) => a.state.equals(submitted).not(),
        ))
        .get();
    for (final a in pendingAttachments) {
      pins.tickets.add(a.ticketId);
    }

    // Cantiere punches on ANY day, excluding the ones the reconciler has already established the
    // server holds (`reconciled_orphan` — the same rule the counter applies).
    final pendingPunches = await (db.select(db.cantierePunches)..where(
          (p) =>
              p.isPendingSync.equals(true) &
              (p.notes.isNull() |
                  p.notes.equals(cantiereReconciledOrphanMarker).not()),
        ))
        .get();
    for (final p in pendingPunches) {
      _addIfNotNull(pins.cantieri, p.cantiereId);
      _addIfNotNull(pins.customers, p.customerId);
      _addIfNotNull(pins.tickets, p.ticketId);
    }

    // Pending simple timbra sessions are unsent work too, but `WorkSessions` carries no
    // customer/location/ticket reference on this device (see the table's columns), so there is
    // nothing for them to pin. If that ever changes, this is where the pin belongs.

    // A pinned ticket pins what its own row points at — the case that matters is a ticket
    // reassigned to a colleague but still needed by a local draft or a queued attachment.
    if (pins.tickets.isNotEmpty) {
      final ticketRows = await (db.select(db.tickets)..where(
            (t) => t.id.isIn(pins.tickets.toList()),
          ))
          .get();
      for (final t in ticketRows) {
        pins.customers.add(t.customerId);
        pins.locations.add(t.locationId);
        _addIfNotNull(pins.agents, t.agentId);
        _addIfNotNull(pins.cantieri, t.cantiereId);
      }
    }

    // A pinned customer's Riferimento: the create wizard pre-fills a new ticket's agent from it,
    // so the agent row must remain readable.
    if (pins.customers.isNotEmpty) {
      final customerRows = await (db.select(db.customers)..where(
            (c) => c.id.isIn(pins.customers.toList()),
          ))
          .get();
      for (final c in customerRows) {
        _addIfNotNull(pins.agents, c.agentId);
      }
    }

    return pins;
  }

  static void _addIfNotNull(Set<String> target, String? id) {
    if (id != null) target.add(id);
  }

  /// Prunes the mirror to the payload's authoritative scope. Runs inside `sync()`'s single
  /// transaction, after every upsert.
  Future<void> _pruneToScope(SyncResultDto payload, _UnsentPins pins) async {
    final scope = payload.scope;
    // Rule 1: an older backend omits `scope` (null on the wire). Absence is never evidence that
    // everything left scope.
    if (scope == null) return;

    // Children before parents throughout: a child left behind either violates the schema's one
    // foreign key (schedule_assignees.schedule_id) or leaves a read path looking up a parent that
    // is gone.

    if (scope.schedules != null) {
      await _pruneSchedules(scope.schedules!, pins.schedules);
    }
    if (scope.tickets != null) {
      await _pruneTickets(scope.tickets!, pins.tickets);
    }
    await _pruneReports(scope);
    if (scope.locations != null) {
      await _pruneIds(db.locations, db.locations.id, scope.locations!, pins.locations);
    }
    if (scope.customers != null) {
      await _pruneIds(db.customers, db.customers.id, scope.customers!, pins.customers);
    }
    if (scope.cantieri != null) {
      await _pruneIds(db.cantieri, db.cantieri.id, scope.cantieri!, pins.cantieri);
    }
    if (scope.agents != null) {
      await _pruneIds(db.agents, db.agents.id, scope.agents!, pins.agents);
    }
    if (scope.materiali != null) {
      await _pruneIds(db.materiali, db.materiali.id, scope.materiali!, pins.materiali);
    }
    if (scope.materialiBarcodes != null) {
      // No pin: nothing unsent references a barcode.
      await _pruneIds(
        db.materialeBarcodes,
        db.materialeBarcodes.id,
        scope.materialiBarcodes!,
        const <String>{},
      );
    }
    if (scope.strumenti != null) {
      // Rule 2: null means this caller has no authoritative instrument set — skip. `[]` means
      // nothing is in scope and does prune (the wholesale replace above already ran with the pins).
      await _pruneIds(db.strumenti, db.strumenti.id, scope.strumenti!, pins.strumenti);
    }
  }

  /// Schedules and their assignments. `schedule_assignees` is the only real foreign key in the
  /// schema, so its rows go first.
  Future<void> _pruneSchedules(List<String> inScope, Set<String> pinned) async {
    final keep = {...inScope, ...pinned};
    final local = await _localIds(db.schedules, db.schedules.id);
    final drop = local.difference(keep);
    if (drop.isEmpty) return;
    await (db.delete(db.scheduleAssignees)..where((a) => a.scheduleId.isIn(drop))).go();
    await (db.delete(db.schedules)..where((s) => s.id.isIn(drop))).go();
  }

  /// Tickets and everything keyed by them.
  Future<void> _pruneTickets(List<String> inScope, Set<String> pinned) async {
    final keep = {...inScope, ...pinned};
    final local = await _localIds(db.tickets, db.tickets.id);
    final drop = local.difference(keep);
    if (drop.isNotEmpty) {
      // The checklist tables (`ticket_controls`, `ticket_assets`, `control_groups`, `assets`) are
      // deliberately NOT pruned by a manifest: the server truncates that collection per sync
      // (see `checklistOmittedTicketIds`), so a manifest would delete rows the server withheld on
      // purpose. Their ticket-scoped rows follow the ticket prune instead; the shared
      // groups/assets are garbage-collected by `applyChecklistBatch`.
      await (db.delete(db.ticketMateriali)..where((r) => r.ticketId.isIn(drop))).go();
      await (db.delete(db.ticketControls)..where((r) => r.ticketId.isIn(drop))).go();
      await (db.delete(db.ticketAssets)..where((r) => r.ticketId.isIn(drop))).go();
      await (db.delete(db.cachedTicketControls)..where((r) => r.ticketId.isIn(drop))).go();
      await (db.delete(db.checklistOmittedTickets)..where((r) => r.ticketId.isIn(drop))).go();
      await (db.delete(db.tickets)..where((t) => t.id.isIn(drop))).go();
    }
    // Fabbisogno has no manifest of its own: it follows the ticket. This also clears rows that
    // arrived for a ticket the mirror never held at all.
    await db.customStatement(
      'DELETE FROM ticket_materiali WHERE ticket_id NOT IN (SELECT id FROM tickets)',
    );
  }

  /// Reports and their child rows.
  ///
  /// `draft_reports` holds two kinds of row, and each has its own manifest: a row still in
  /// `Bozza` answers to `scope.draftReports`, a row that has left the draft state answers to
  /// `scope.submittedReports`.
  Future<void> _pruneReports(SyncScopeDto scope) async {
    final draftScope = scope.draftReports?.toSet();
    final submittedScope = scope.submittedReports?.toSet();
    if (draftScope == null && submittedScope == null) return;

    final submitted = DraftSubmissionState.submitted.toPersistedString();
    final drop = <String>[];
    for (final r in await db.select(db.draftReports).get()) {
      // Rule 4: locally-authored rows are not server rows at all — no manifest describes them,
      // and deleting one would destroy work the server has never seen.
      if (r.isLocalOnly) continue;

      final isDraft = r.stato == 'Bozza';
      final manifest = isDraft ? draftScope : submittedScope;
      // That collection had no authoritative set this time: no evidence of a deletion.
      if (manifest == null) continue;
      if (manifest.contains(r.id)) continue;

      // A Bozza the device has not submitted yet is unsent work even when the row is
      // server-known — the counter calls it "unsent" by exactly this predicate. Never delete it
      // on the strength of a manifest.
      if (isDraft && r.submissionState != submitted) continue;

      drop.add(r.id);
    }
    if (drop.isEmpty) return;

    // Report child rows first — none has a foreign key, but a child whose report is gone is a
    // read path with nothing to resolve against.
    await (db.delete(db.reportStaffTable)..where((r) => r.reportId.isIn(drop))).go();
    await (db.delete(db.reportMateriali)..where((r) => r.reportId.isIn(drop))).go();
    await (db.delete(db.reportControlli)..where((r) => r.reportId.isIn(drop))).go();
    await (db.delete(db.reportStrumenti)..where((r) => r.reportId.isIn(drop))).go();
    await (db.delete(db.draftReports)..where((r) => r.id.isIn(drop))).go();
  }

  /// Deletes every locally-held id that is neither in [inScope] nor [pinned].
  ///
  /// Computes the drop set from the LOCAL ids rather than issuing `id NOT IN (<scope>)`: the
  /// scope list can name a whole tenant book, which would risk SQLite's bound-variable limit,
  /// while the local mirror is by definition the small side of the comparison.
  Future<void> _pruneIds<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    GeneratedColumn<String> id,
    List<String> inScope,
    Set<String> pinned,
  ) async {
    final keep = {...inScope, ...pinned};
    final drop = (await _localIds(table, id)).difference(keep);
    if (drop.isEmpty) return;
    await (db.delete(table)..where((_) => id.isIn(drop))).go();
  }

  Future<Set<String>> _localIds<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    GeneratedColumn<String> id,
  ) async {
    final rows = await (db.selectOnly(table)..addColumns([id])).get();
    return rows.map((r) => r.read(id)).whereType<String>().toSet();
  }

  // ── Upsert helpers ─────────────────────────────────────────────────────────

  /// The materiali catalogue.
  ///
  /// These two tables existed and nothing ever filled them, which left every screen reading them
  /// dead: the magazzino catalogue, admin materiali and cantieri, the schedule pickers, and —
  /// worst — cantiere clock-in, where a technician could not select a site and so could not
  /// record site hours at all. The payload has carried both arrays all along; only the client
  /// side of the wire was missing.
  /// The colleagues a technician can name on a rapportino.
  ///
  /// Replaced wholesale rather than upserted, because the server sends the full active list every
  /// time. Upserting would leave someone who has since left the company in the picker forever —
  /// their row would simply stop being mentioned, and nothing would ever delete it.
  ///
  /// Done in one transaction so a sync interrupted mid-write cannot leave the picker empty; the
  /// technician keeps the previous list until a complete one replaces it.
  Future<void> _replaceColleagues(List<ColleagueDto> list) async {
    if (list.isEmpty) return;

    await db.transaction(() async {
      await db.delete(db.colleagues).go();
      await db.batch(
        (b) => b.insertAll(
          db.colleagues,
          list.map(
            (c) => ColleaguesCompanion.insert(
              id: c.id,
              displayName: c.displayName,
            ),
          ),
        ),
      );
    });
  }

  Future<void> _upsertMateriali(List<MaterialeDto> list) async {
    for (final m in list) {
      await db
          .into(db.materiali)
          .insertOnConflictUpdate(
            MaterialiCompanion.insert(
              id: m.id,
              tenantId: m.tenantId,
              createdAt: m.createdAt,
              updatedAt: Value(m.updatedAt),
              code: m.code,
              name: m.name,
              description: Value(m.description),
              unitOfMeasure: Value(m.unitOfMeasure),
              category: Value(m.category),
              marca: Value(m.marca),
              purchasePrice: Value(m.purchasePrice),
              salePrice: Value(m.salePrice),
              isActive: Value(m.isActive),
            ),
          );
    }
  }

  /// The offline fabbisogno behind the ticket's Fabbisogno tab.
  ///
  /// Replaced, not upserted, and only for the tickets *this payload* carries. The office sets a
  /// ticket's planned materials with `PUT /api/Tickets/{id}/materiali`, which deletes every
  /// `TicketMateriale` row and re-inserts the new list — so a row that survived an edit comes back
  /// with a **new id**. Upserting by id therefore never recognised the replacements as the same
  /// item: after two office edits the technician saw the list two or three times over. The
  /// delete-then-insert below is what makes "edited" read as an edit rather than an addition.
  ///
  /// The set to replace is the payload's **ticket ids**, not the ids that happen to have material
  /// rows: a fabbisogno cleared in the office sends no rows at all, and only deleting against the
  /// ticket can drop the stale ones it left behind.
  ///
  /// Scoped to the payload's ticket ids because absence is a delta-scope fact, never a deletion
  /// signal: a ticket the payload does not carry this time keeps the rows it already mirrored. The
  /// server never says its fabbisogno is gone, it says nothing about it.
  ///
  /// Skipped entirely when the payload does not carry the member, so an older backend cannot look
  /// like "every fabbisogno was cleared" and wipe the tab.
  Future<void> _replaceTicketMateriali(SyncResultDto payload) async {
    if (!payload.carriesTicketMateriali) return;

    final ticketIds = payload.tickets.map((t) => t.id).toSet();
    // No ticket in scope means there is no set to replace. Returning also keeps an empty `IN ()`
    // (which SQLite treats as a syntax error) out of the delete below.
    if (ticketIds.isEmpty) return;

    await db.transaction(() async {
      await (db.delete(db.ticketMateriali)..where((m) => m.ticketId.isIn(ticketIds))).go();
      await db.batch(
        (b) => b.insertAll(
          db.ticketMateriali,
          // Defensive: the contract scopes this member to the payload's tickets. Filtering keeps a
          // row for any other ticket out of the mirror — such a row would be inserted without its
          // ticket's previous set having been deleted, leaving a stale mix behind.
          payload.ticketMateriali
              .where((m) => ticketIds.contains(m.ticketId))
              .map(
                (m) => TicketMaterialiCompanion.insert(
                  id: m.id,
                  tenantId: m.tenantId,
                  createdAt: m.createdAt,
                  updatedAt: Value(m.updatedAt),
                  ticketId: m.ticketId,
                  materialeId: Value(m.materialeId),
                  freeTextName: Value(m.freeTextName),
                  quantity: m.quantity,
                  unitOfMeasure: Value(m.unitOfMeasure),
                  notes: Value(m.notes),
                  isAvailable: Value(m.isAvailable),
                ),
              ),
        ),
      );
    });
  }

  Future<void> _upsertMaterialeBarcodes(List<MaterialeBarcodeDto> list) async {
    for (final b in list) {
      await db
          .into(db.materialeBarcodes)
          .insertOnConflictUpdate(
            MaterialeBarcodesCompanion.insert(
              id: b.id,
              tenantId: b.tenantId,
              createdAt: b.createdAt,
              updatedAt: Value(b.updatedAt),
              materialeId: b.materialeId,
              barcode: b.barcode,
              barcodeType: Value(b.barcodeType),
              isPrimary: Value(b.isPrimary),
            ),
          );
    }
  }

  /// The cantieri a technician may be sent to.
  Future<void> _upsertCantieri(List<CantiereDto> list) async {
    for (final c in list) {
      await db
          .into(db.cantieri)
          .insertOnConflictUpdate(
            CantieriCompanion.insert(
              id: c.id,
              tenantId: c.tenantId,
              createdAt: c.createdAt,
              updatedAt: Value(c.updatedAt),
              name: c.name,
              address: Value(c.address),
              city: Value(c.city),
              postalCode: Value(c.postalCode),
              notes: Value(c.notes),
              startDate: Value(c.startDate),
              endDate: Value(c.endDate),
              status: Value(c.status),
              customerId: Value(c.customerId),
              commessaId: Value(c.commessaId),
            ),
          );
    }
  }

  /// The crew mirror behind the lead-only clock-in affordances and the teammate picker.
  ///
  /// Replaced, not upserted, but only for the cantieri *this payload* carries. The member holds the
  /// complete crew of each of those cantieri with no delta filter on the crew rows — a lead change
  /// must reach a device whose cantiere row itself is unchanged — so the delete-then-insert below
  /// is what makes a person removed from a crew stop appearing. It is scoped to the payload's
  /// cantiere ids because absence is a delta-scope fact, never a deletion signal: a cantiere the
  /// payload does not carry this time keeps the crew it already mirrored. That is also why nothing
  /// is pruned for cantieri that are absent — the server never says their crew is gone, it says
  /// nothing about them.
  ///
  /// Skipped entirely when the payload does not carry the member, so an older backend cannot look
  /// like "every crew is empty" and wipe the mirror.
  Future<void> _replaceCantiereCrewAssignments(SyncResultDto payload) async {
    if (!payload.carriesCantiereCrewAssignments) return;

    final cantiereIds = payload.cantieri.map((c) => c.id).toSet();
    // No cantiere in scope means there is no set to replace. Returning also keeps an empty `IN ()`
    // (which SQLite treats as a syntax error) out of the delete below.
    if (cantiereIds.isEmpty) return;

    await db.transaction(() async {
      await (db.delete(db.cantiereCrewAssignments)..where((a) => a.cantiereId.isIn(cantiereIds)))
          .go();
      await db.batch(
        (b) => b.insertAll(
          db.cantiereCrewAssignments,
          // Defensive: the contract scopes this member to the payload's cantieri. Filtering keeps
          // a row for any other cantiere out of the mirror — such a row would be inserted without
          // its cantiere's previous set having been deleted, leaving a stale mix behind.
          payload.cantiereCrewAssignments
              .where((a) => cantiereIds.contains(a.cantiereId))
              .map(
                (a) => CantiereCrewAssignmentsCompanion.insert(
                  id: a.id,
                  cantiereId: a.cantiereId,
                  userId: a.userId,
                  isLead: Value(a.isLead),
                ),
              ),
        ),
      );
    });
  }

  Future<void> _upsertCustomers(List<CustomerDto> list) async {
    for (final c in list) {
      await db
          .into(db.customers)
          .insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: c.id,
              tenantId: c.tenantId,
              createdAt: c.createdAt,
              updatedAt: Value(c.updatedAt),
              companyName: c.companyName,
              taxId: Value(c.taxId),
              address: Value(c.address),
              city: Value(c.city),
              postalCode: Value(c.postalCode),
              country: Value(c.country),
              phone: Value(c.phone),
              email: Value(c.email),
              contactPerson: Value(c.contactPerson),
              notes: Value(c.notes),
              isActive: Value(c.isActive),
              // Written even when null: the server's value is authoritative, so a customer whose
              // agent was removed must lose it here too.
              agentId: Value(c.agentId),
            ),
          );
    }
  }

  Future<void> _upsertLocations(List<LocationDto> list) async {
    for (final l in list) {
      await db
          .into(db.locations)
          .insertOnConflictUpdate(
            LocationsCompanion.insert(
              id: l.id,
              tenantId: l.tenantId,
              createdAt: l.createdAt,
              updatedAt: Value(l.updatedAt),
              customerId: l.customerId,
              name: l.name,
              address: Value(l.address),
              city: Value(l.city),
              postalCode: Value(l.postalCode),
              country: Value(l.country),
              latitude: Value(l.latitude),
              longitude: Value(l.longitude),
              phone: Value(l.phone),
              notes: Value(l.notes),
              isActive: Value(l.isActive),
            ),
          );
    }
  }

  Future<void> _upsertTickets(List<TicketDto> list) async {
    for (final t in list) {
      await db
          .into(db.tickets)
          .insertOnConflictUpdate(
            TicketsCompanion.insert(
              id: t.id,
              tenantId: t.tenantId,
              createdAt: t.createdAt,
              updatedAt: Value(t.updatedAt),
              title: t.title,
              numero: Value(t.numero),
              description: Value(t.description),
              customerId: t.customerId,
              locationId: t.locationId,
              assignedUserId: Value(t.assignedUserId),
              statusId: t.statusId,
              typeId: t.typeId,
              agentId: Value(t.agentId),
              closedAt: Value(t.closedAt),
              technicianNotes: Value(t.technicianNotes),
              internalNotes: Value(t.internalNotes),
              contractId: Value(t.contractId),
              prodottoAssistenzaId: Value(t.prodottoAssistenzaId),
              commessaId: Value(t.commessaId),
              cantiereId: Value(t.cantiereId),
              priority: Value(t.priority),
              dueDate: Value(formatDateOnly(t.dueDate)),
              tagsJson: Value(jsonEncode(t.tags)),
            ),
          );
    }
  }

  Future<void> _upsertSchedules(List<ScheduleDto> list) async {
    for (final s in list) {
      await db
          .into(db.schedules)
          .insertOnConflictUpdate(
            SchedulesCompanion.insert(
              id: s.id,
              tenantId: s.tenantId,
              createdAt: s.createdAt,
              updatedAt: Value(s.updatedAt),
              ticketId: Value(s.ticketId),
              activityDate: s.activityDate,
              timeStartMinutes: ScheduleDto.parseTimeToMinutes(s.timeStart),
              timeEndMinutes: ScheduleDto.parseTimeToMinutes(s.timeEnd),
              userId: s.userId,
              statusId: s.statusId,
              locationId: s.locationId,
              allDay: Value(s.allDay),
              title: s.title,
              description: s.description,
            ),
          );

      // Replaced wholesale rather than merged: the payload is the whole truth about who is on
      // this schedule, and someone removed from a squadra must stop appearing on the device the
      // same way they stop appearing on the server.
      await (db.delete(
        db.scheduleAssignees,
      )..where((t) => t.scheduleId.equals(s.id))).go();

      for (final a in s.assignees) {
        await db
            .into(db.scheduleAssignees)
            .insertOnConflictUpdate(
              ScheduleAssigneesCompanion.insert(
                scheduleId: s.id,
                userId: a.userId,
                isUserActive: Value(a.isUserActive),
                isDirect: Value(a.isDirect),
                isLead: Value(a.isLead),
                isTeam: Value(a.isTeam),
                isLegacyStaff: Value(a.isLegacyStaff),
              ),
            );
      }
    }
  }

  Future<void> _upsertDraftReports(List<ReportDto> list) async {
    for (final r in list) {
      // A local draft the technician is still actively working on is authoritative over whatever
      // a background sync tick just fetched — the same rule rapportini_list_screen.dart's
      // _confirmDeleteDraft already states for deletion ("local state is authoritative for a
      // Bozza the technician is still working on").
      //
      // This id space collision became reachable the moment createCantiereReportDraft (cantiere-
      // only rapportino creation) started reusing the backend-issued Report id for the local
      // draft row, instead of minting a fresh client GUID like every other creation path. The
      // mobile sync's own `draftReports`/`submittedReports` payload is "every Bozza this user
      // authored" (MobileUserSyncService, backend) — which now includes that very report from the
      // instant it exists server-side, with a blank title/details (the create call passes none)
      // and isLocalOnly unset. Without this guard, HomeShell's periodic sync (every 60s, plus on
      // resume/reconnect) would silently overwrite whatever the technician had already typed and
      // saved locally, and flip isLocalOnly back to false mid-edit — exactly the invariant this
      // function's own "Synced-down reports are never local-only" comment below assumes never
      // collides with a row still being edited locally.
      final local = await (db.select(
        db.draftReports,
      )..where((t) => t.id.equals(r.id))).getSingleOrNull();
      if (local != null && local.isLocalOnly) {
        continue;
      }

      await db
          .into(db.draftReports)
          .insertOnConflictUpdate(
            DraftReportsCompanion.insert(
              id: r.id,
              tenantId: r.tenantId,
              createdAt: r.createdAt,
              updatedAt: Value(r.updatedAt),
              title: r.title,
              scheduleId: Value(r.scheduleId),
              ticketId: Value(r.ticketId),
              customerId: Value(r.customerId),
              cantiereId: Value(r.cantiereId),
              details: Value(r.details),
              diagnosi: Value(r.diagnosi),
              soluzione: Value(r.soluzione),
              insertedUserId: r.insertedUserId,
              locationId: r.locationId,
              startedAt: Value(r.startedAt),
              endedAt: Value(r.endedAt),
              documentTemplateId: Value(r.documentTemplateId),
              customerSignatureAllegatoId: Value(r.customerSignatureAllegatoId),
              technicianSignatureAllegatoId: Value(
                r.technicianSignatureAllegatoId,
              ),
              technicianNotes: Value(r.technicianNotes),
              closedAt: Value(r.closedAt),
              stato: Value(r.stato),
              inviatoAt: Value(r.inviatoAt),
              controllatoAt: Value(r.controllatoAt),
              controllatoDa: Value(r.controllatoDa),
              fatturatoAt: Value(r.fatturatoAt),
              materialiNotRequired: Value(r.materialiNotRequired),
              customerSignoffText: Value(r.customerSignoffText),
              customerSignoffAt: Value(r.customerSignoffAt),
              // Synced-down reports are never local-only
              isLocalOnly: const Value(false),
            ),
          );
    }
  }

  /// The full aggregate of every report in scope: staff lines, materials, answered checklist
  /// items, attachment metadata and row versions (O-8a).
  ///
  /// Two independent guards, both deliberate:
  ///
  /// * **Ownership.** Children are written only for a report row that exists locally and is NOT
  ///   this device's unsent working copy (`isLocalOnly`). Such a copy may hold staff, materials and
  ///   answers the server has never seen; replacing them with the server's would delete that work —
  ///   the same rule [_upsertDraftReports] already applies to the header.
  /// * **Authority.** `reportVersions` is the payload's cutoff-free in-scope report set. The
  ///   backend re-sends children in full for every report in it, because a child deleted in the
  ///   office stamps nothing the device can observe — a delta filter would leave the stale child
  ///   here for ever. So a report in that set with no child rows in the payload has none, and its
  ///   children are deleted here. A report absent from the set is no evidence of anything, and is
  ///   left alone.
  ///
  /// Deliberately silent when the payload carries neither member: an older backend must never look
  /// like "every report lost its children" (see [SyncResultDto.carriesReportAggregate]).
  Future<void> _applyReportAggregate(SyncResultDto payload) async {
    if (!payload.carriesReportAggregate && !payload.carriesAllegati) return;

    final owned = <String>{
      for (final r in await db.select(db.draftReports).get())
        if (!r.isLocalOnly) r.id,
    };
    final versions = <String, String>{
      for (final v in payload.reportVersions) v.reportId: v.version,
    };
    final inScope = versions.keys.toSet();

    if (payload.carriesReportAggregate && inScope.isNotEmpty) {
      final staff = <String, List<SyncReportStaffDto>>{};
      for (final s in payload.reportStaff) {
        (staff[s.reportId] ??= []).add(s);
      }
      final materiali = <String, List<SyncReportMaterialeDto>>{};
      for (final m in payload.reportMateriali) {
        (materiali[m.reportId] ??= []).add(m);
      }
      final controlli = <String, List<SyncReportControlloDto>>{};
      for (final c in payload.reportControlli) {
        (controlli[c.reportId] ??= []).add(c);
      }

      final replace = inScope.intersection(owned);
      if (replace.isNotEmpty) {
        // Delete first and insert after, per table: the payload is the complete set for these
        // report ids, so a merge would keep a child the office has already removed.
        await (db.delete(
          db.reportStaffTable,
        )..where((r) => r.reportId.isIn(replace))).go();
        await (db.delete(
          db.reportMateriali,
        )..where((r) => r.reportId.isIn(replace))).go();
        await (db.delete(
          db.reportControlli,
        )..where((r) => r.reportId.isIn(replace))).go();

        for (final reportId in replace) {
          for (final s in staff[reportId] ?? const <SyncReportStaffDto>[]) {
            await db
                .into(db.reportStaffTable)
                .insert(
                  ReportStaffTableCompanion.insert(
                    id: s.id,
                    tenantId: s.tenantId,
                    createdAt: s.createdAt,
                    updatedAt: Value(s.updatedAt),
                    reportId: reportId,
                    userId: s.userId,
                    hoursWorked: Value(s.hoursWorked),
                    kmTraveled: Value(s.kmTraveled),
                    vehicle: Value(s.vehicle),
                    costPerKm: Value(s.costPerKm),
                    notes: Value(s.notes),
                    startTime: Value(s.startTime),
                    endTime: Value(s.endTime),
                    pauseMinutes: Value(s.pauseMinutes),
                  ),
                );
          }
          for (final m in materiali[reportId] ?? const <SyncReportMaterialeDto>[]) {
            await db
                .into(db.reportMateriali)
                .insert(
                  ReportMaterialiCompanion.insert(
                    id: m.id,
                    tenantId: m.tenantId,
                    createdAt: m.createdAt,
                    updatedAt: Value(m.updatedAt),
                    reportId: reportId,
                    materialeId: Value(m.materialeId),
                    freeTextName: Value(m.freeTextName),
                    quantity: m.quantity,
                    unitOfMeasure: Value(m.unitOfMeasure),
                    unitPrice: Value(m.unitPrice),
                    notes: Value(m.notes),
                    magazzinoId: Value(m.magazzinoId),
                  ),
                );
          }
          for (final c
              in controlli[reportId] ?? const <SyncReportControlloDto>[]) {
            await db
                .into(db.reportControlli)
                .insert(
                  ReportControlliCompanion.insert(
                    id: c.id,
                    tenantId: c.tenantId,
                    createdAt: c.createdAt,
                    updatedAt: Value(c.updatedAt),
                    reportId: reportId,
                    controlId: c.ticketControlId,
                    stringValue: Value(c.stringValue),
                    boolValue: Value(c.boolValue),
                    dateValue: Value(c.dateValue?.toUtc()),
                    numberValue: Value(c.numberValue),
                    note: Value(c.note),
                  ),
                );
          }
        }

        // The version of the server copy, for exactly the rows this sync owns. The submit's
        // stale-copy guard compares against it; a local working copy keeps its own, captured when
        // it was imported (import_server_report.dart's own comment explains why that moment is the
        // only one that may set it).
        for (final reportId in replace) {
          await (db.update(
            db.draftReports,
          )..where((r) => r.id.equals(reportId))).write(
            DraftReportsCompanion(expectedVersion: Value(versions[reportId])),
          );
        }
      }
    }

    if (payload.carriesAllegati) {
      // Report entities: the report scope above is the authority. Ticket entities: only the ticket
      // manifest is — a delta ticket list says nothing about a ticket's files, so with no manifest
      // (an older backend) ticket attachments are never pruned.
      final reportEntities = inScope.intersection(owned);
      final ticketScope = payload.scope?.tickets?.toSet();

      final byEntity = <String, List<SyncReportAllegatoDto>>{};
      for (final a in payload.allegati) {
        final writable = a.entityType == AllegatoEntityType.report
            ? reportEntities.contains(a.entityId)
            : a.entityType == AllegatoEntityType.ticket &&
                  (ticketScope?.contains(a.entityId) ?? false);
        if (!writable) continue;
        (byEntity['${a.entityType}:${a.entityId}'] ??= []).add(a);
      }

      Future<void> replaceEntity(int entityType, Set<String> entities) async {
        if (entities.isEmpty) return;
        // A file captured here and not yet uploaded is this device's own work: the server does not
        // know about it, so its absence from the payload says nothing. `isPendingUpload` is the
        // existing marker for that state (see the table's own doc comment).
        await (db.delete(db.reportAllegati)..where(
              (a) => a.entityType.equals(entityType) & a.entityId.isIn(entities) &
                  a.isPendingUpload.equals(false),
            ))
            .go();
        for (final entityId in entities) {
          for (final a in byEntity['$entityType:$entityId'] ??
              const <SyncReportAllegatoDto>[]) {
            await db
                .into(db.reportAllegati)
                .insertOnConflictUpdate(
                  ReportAllegatiCompanion.insert(
                    id: a.id,
                    tenantId: a.tenantId,
                    createdAt: a.createdAt,
                    updatedAt: Value(a.updatedAt),
                    fileName: a.fileName,
                    contentType: a.contentType,
                    sizeBytes: a.sizeBytes,
                    // The bytes live on the server, so there is no local file to point at. Empty
                    // rather than a fake path: every reader tests `storagePath.isNotEmpty &&
                    // File(...).existsSync()` before drawing from it.
                    storagePath: '',
                    url: _attachmentContentPath(a.entityType, a.entityId, a.id),
                    entityType: a.entityType,
                    entityId: a.entityId,
                    uploadedByUserId: a.uploadedByUserId,
                    isActive: Value(a.isActive),
                    isPendingUpload: const Value(false),
                    kind: Value(a.kind),
                    contentHash: Value(a.contentHash),
                  ),
                );
          }
        }
      }

      await replaceEntity(AllegatoEntityType.report, reportEntities);
      if (ticketScope != null) await replaceEntity(AllegatoEntityType.ticket, ticketScope);
    }
  }

  /// The route a synced file's bytes are fetched from — the same strings the backend builds
  /// (`AttachmentService.ContentPath`), derived here rather than sent, because the payload carries
  /// metadata only.
  static String _attachmentContentPath(
    int entityType,
    String entityId,
    String allegatoId,
  ) => entityType == AllegatoEntityType.ticket
      ? '/api/tickets/$entityId/attachments/$allegatoId/content'
      : '/api/reports/$entityId/attachments/$allegatoId/content';

  Future<void> _upsertTicketStatuses(List<TicketStatusDto> list) async {
    for (final s in list) {
      await db
          .into(db.ticketStatuses)
          .insertOnConflictUpdate(
            TicketStatusesCompanion.insert(
              id: Value(s.id),
              tenantId: s.tenantId,
              name: s.name,
              isDefault: Value(s.isDefault),
              isClosed: Value(s.isClosed),
            ),
          );
    }
  }

  Future<void> _upsertTicketTypes(List<TicketTypeDto> list) async {
    for (final t in list) {
      await db
          .into(db.ticketTypes)
          .insertOnConflictUpdate(
            TicketTypesCompanion.insert(
              id: Value(t.id),
              tenantId: t.tenantId,
              name: t.name,
              description: Value(t.description),
            ),
          );
    }
  }
}

/// The id sets unsent local work still points at — the pins the authoritative-scope prune must
/// never delete. One field per manifest collection; `reports` is absent because a report is
/// either locally-owned (never pruned) or governed by its manifest, so it needs no pin.
class _UnsentPins {
  final Set<String> schedules = <String>{};
  final Set<String> tickets = <String>{};
  final Set<String> locations = <String>{};
  final Set<String> customers = <String>{};
  final Set<String> cantieri = <String>{};
  final Set<String> agents = <String>{};
  final Set<String> materiali = <String>{};
  final Set<String> strumenti = <String>{};
}

// ══════════════════════════════════════════════════════════════════════════════
// Riverpod provider
// ══════════════════════════════════════════════════════════════════════════════

/// Whether automatic background sync (the 60s foreground poll and the app-resume sync in
/// [HomeShell]) should run at all.
///
/// Defaults to true and is overridden in `main.dart` with the Impostazioni → "Modalità offline"
/// setting — same pattern as `gpsPreferenceProvider` in core/location: a core default here (data
/// layer must not import a feature), bound once in main.dart so no call site has to remember the
/// setting exists.
///
/// Deliberately does NOT gate the initial post-login sync or the reconnect-triggered flush of
/// queued offline writes (timbra, tickets, rapportini, …) — those exist to avoid losing or
/// silently staling data, not to keep it fresh in the background, so they stay on even with this
/// preference off.
final backgroundSyncPreferenceProvider = Provider<bool>((ref) => true);

/// Provides the [AppDatabase] singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Provides the [SyncService].
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    db: ref.watch(appDatabaseProvider),
    dio: ref.watch(dioProvider),
  );
});

/// Notifier that manages sync state (idle / syncing / error / done).
enum SyncStatus { idle, syncing, done, error }

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSync,
    this.errorMessage,
  });

  final SyncStatus status;
  final DateTime? lastSync;
  final String? errorMessage;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSync,
    String? errorMessage,
  }) => SyncState(
    status: status ?? this.status,
    lastSync: lastSync ?? this.lastSync,
    errorMessage: errorMessage,
  );
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._service, this._db, {this.prefetchAttachments}) : super(const SyncState()) {
    _loadLastSync();
  }

  final SyncService _service;
  final AppDatabase _db;

  /// Fills the attachment byte cache after a successful sync (O-8c). A callback, not the
  /// prefetcher itself, so this file stays free of the cache's own dependencies; the provider
  /// wires it and it is already a no-op unless the link is unmetered Wi-Fi.
  final Future<int> Function()? prefetchAttachments;

  Future<void> _loadLastSync() async {
    final last = await _db.getLastSync();
    if (last != null) {
      state = state.copyWith(lastSync: last);
    }
  }

  Future<void> performSync() async {
    if (state.status == SyncStatus.syncing) return;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      final ts = await _service.sync();
      state = SyncState(status: SyncStatus.done, lastSync: ts);
      // Deliberately after the state is published and never awaited: the technician sees the
      // fresh data immediately, and a slow or failing prefetch cannot hold the sync hostage.
      final prefetch = prefetchAttachments;
      if (prefetch != null) {
        unawaited(
          prefetch().catchError((Object e) {
            debugPrint('attachment prefetch failed: $e');
            return 0;
          }),
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(
    ref.watch(syncServiceProvider),
    ref.watch(appDatabaseProvider),
    prefetchAttachments: () => ref.read(attachmentPrefetcherProvider).run(),
  );
});
