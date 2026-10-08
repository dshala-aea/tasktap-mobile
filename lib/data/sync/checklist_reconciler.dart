// dart format width=100
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/time/business_time.dart' show formatWorkDate;
import '../../domain/checklist/control_type.dart';
import '../local/app_database.dart';
import 'checklist_sync_dto.dart';
import 'sync_dto.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Checklist reconciler — the one place that writes the per-asset checklist mirror.
//
// Three producers feed it: the sync payload, the batched re-request of omitted tickets and the
// per-ticket REST backfill. They all describe "these tickets' checklist state, completely", which
// is why the write is wholesale per ticket (hand-off section 3: row-level since-filtering and
// tombstones are deferred, a retired asset disappears because its ticket is re-described).
//
// What it will NOT do, each pinned by a test:
//  * touch a ticket it was not told is authoritative (including omitted ones: "nothing implies
//    deletion");
//  * delete a row the technician already answered on a local Bozza — it is kept as `isRetained`
//    (the server still accepts observations on retained rows, owner ruling 2026-10-06);
//  * run at all for a payload from an older backend (`carriesChecklist` false).
// ══════════════════════════════════════════════════════════════════════════════

class ChecklistBatch {
  const ChecklistBatch({
    required this.authoritativeTicketIds,
    this.omittedTicketIds = const {},
    this.controlGroups = const [],
    this.ticketControls = const [],
    this.ticketAssets = const [],
    this.assets = const [],
  });

  /// Tickets whose checklist state this batch fully describes (rows may be zero).
  final Set<String> authoritativeTicketIds;

  /// Tickets the server left out: local data stays, the id is remembered for a re-request.
  final Set<String> omittedTicketIds;
  final List<SyncControlGroupDto> controlGroups;
  final List<SyncTicketControlDto> ticketControls;
  final List<SyncTicketAssetDto> ticketAssets;
  final List<SyncAssetDto> assets;

  /// Authoritative = (tickets that carry rows) + (tickets in `tickets` for which the phone already
  /// holds checklist rows — this is what clears a ticket whose assets were all removed), minus the
  /// omitted ones. A ticket that is in neither set is left exactly as it is.
  factory ChecklistBatch.fromSync(
    SyncResultDto p, {
    required Set<String> payloadTicketIds,
    required Set<String> ticketsWithLocalChecklist,
  }) {
    final omitted = p.checklistOmittedTicketIds.toSet();
    final authoritative = <String>{
      ...p.ticketControls.map((c) => c.ticketId),
      ...p.ticketAssets.map((a) => a.ticketId),
      ...payloadTicketIds.intersection(ticketsWithLocalChecklist),
    }..removeAll(omitted);
    return ChecklistBatch(
      authoritativeTicketIds: authoritative,
      omittedTicketIds: omitted,
      controlGroups: p.controlGroups,
      ticketControls: p.ticketControls,
      ticketAssets: p.ticketAssets,
      assets: p.assets,
    );
  }
}

/// Ticket ids the phone currently holds any checklist row or coverage row for.
Future<Set<String>> ticketIdsWithLocalChecklist(AppDatabase db) async {
  final fromControls = await db
      .customSelect(
        'SELECT DISTINCT ticket_id AS t FROM ticket_controls',
        readsFrom: {db.ticketControls},
      )
      .get();
  final fromCoverage = await db
      .customSelect(
        'SELECT DISTINCT ticket_id AS t FROM ticket_assets',
        readsFrom: {db.ticketAssets},
      )
      .get();
  return {...fromControls.map((r) => r.read<String>('t')), ...fromCoverage.map((r) => r.read<String>('t'))};
}

Future<void> applyChecklistBatch(AppDatabase db, ChecklistBatch b) {
  return db.transaction(() async {
    final auth = b.authoritativeTicketIds;

    if (auth.isNotEmpty) {
      // Answers the technician typed on a Bozza that still lives on this device: rows they refer
      // to must survive even if the server stops listing them.
      final localDrafts = (await (db.select(db.draftReports)
                ..where((r) => r.isLocalOnly.equals(true)))
              .get())
          .map((r) => r.id)
          .toList();
      final answered = localDrafts.isEmpty
          ? <String>{}
          : (await (db.select(db.reportControlli)..where((c) => c.reportId.isIn(localDrafts))).get())
                .map((c) => c.controlId)
                .toSet();

      final incoming = {for (final c in b.ticketControls) c.id};
      final existing =
          await (db.select(db.ticketControls)..where((c) => c.ticketId.isIn(auth))).get();
      for (final row in existing) {
        if (incoming.contains(row.id)) continue; // replaced by the insert below
        if (answered.contains(row.id)) {
          await (db.update(db.ticketControls)..where((c) => c.id.equals(row.id))).write(
            const TicketControlsCompanion(isRetained: Value(true)),
          );
        } else {
          await (db.delete(db.ticketControls)..where((c) => c.id.equals(row.id))).go();
        }
      }
      await (db.delete(db.ticketAssets)..where((a) => a.ticketId.isIn(auth))).go();
    }

    await db.batch((batch) {
      batch.insertAll(
        db.controlGroups,
        [
          for (final g in b.controlGroups)
            ControlGroupsCompanion.insert(
              id: g.id,
              parentGroupId: Value(g.parentGroupId),
              maintenanceTemplateVersionId: g.maintenanceTemplateVersionId,
              name: g.name,
              sortOrder: g.sortOrder,
            ),
        ],
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        db.ticketControls,
        [
          for (final c in b.ticketControls)
            TicketControlsCompanion.insert(
              id: c.id,
              ticketId: c.ticketId,
              prodottoAssistenzaId: Value(c.prodottoAssistenzaId),
              templateControlId: c.templateControlId,
              controlLineageId: c.controlLineageId,
              groupId: c.groupId,
              label: c.label,
              description: Value(c.description),
              type: controlTypeToWire(c.type),
              isRequired: Value(c.isRequired),
              options: Value(c.options),
              sortOrder: Value(c.sortOrder),
              status: Value(c.status),
              stringValue: Value(c.stringValue),
              boolValue: Value(c.boolValue),
              dateValue: Value(c.dateValue),
              numberValue: Value(c.numberValue),
              note: Value(c.note),
            ),
        ],
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        db.ticketAssets,
        [
          for (final a in b.ticketAssets)
            TicketAssetsCompanion.insert(
              ticketId: a.ticketId,
              prodottoAssistenzaId: a.prodottoAssistenzaId,
              controllato: Value(a.controllato),
              note: Value(a.note),
              maintenanceTemplateVersionId: Value(a.maintenanceTemplateVersionId),
            ),
        ],
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        db.assets,
        [
          for (final a in b.assets)
            AssetsCompanion.insert(
              id: a.id,
              name: a.name,
              serialNumber: Value(a.serialNumber),
              matricola: Value(a.matricola),
              librettoIdsJson: Value(jsonEncode(a.librettoIds)),
            ),
        ],
        mode: InsertMode.insertOrReplace,
      );
    });

    // Bookkeeping for the re-request: remember what was left out (never reset an attempt counter),
    // forget what has now been delivered.
    for (final id in b.omittedTicketIds) {
      await db
          .into(db.checklistOmittedTickets)
          .insert(ChecklistOmittedTicketsCompanion.insert(ticketId: id), mode: InsertMode.insertOrIgnore);
    }
    if (auth.isNotEmpty) {
      await (db.delete(db.checklistOmittedTickets)..where((o) => o.ticketId.isIn(auth))).go();
    }

    await _pruneGroups(db);
    await _pruneAssets(db);
  });
}

/// Drops groups no checklist row uses (directly or as an ancestor of a used group).
Future<void> _pruneGroups(AppDatabase db) async {
  final used = (await db
          .customSelect('SELECT DISTINCT group_id AS g FROM ticket_controls', readsFrom: {db.ticketControls})
          .get())
      .map((r) => r.read<String>('g'))
      .toSet();
  final all = await db.select(db.controlGroups).get();
  final byId = {for (final g in all) g.id: g};
  final keep = <String>{};
  for (final id in used) {
    var cur = byId[id];
    while (cur != null && keep.add(cur.id)) {
      cur = cur.parentGroupId == null ? null : byId[cur.parentGroupId!];
    }
  }
  final drop = all.where((g) => !keep.contains(g.id)).map((g) => g.id).toList();
  if (drop.isNotEmpty) {
    await (db.delete(db.controlGroups)..where((g) => g.id.isIn(drop))).go();
  }
}

/// Drops asset identities nothing refers to (no coverage row, no checklist row — retained rows
/// count, they still need their asset name).
Future<void> _pruneAssets(AppDatabase db) async {
  final fromCoverage = await db
      .customSelect('SELECT DISTINCT prodotto_assistenza_id AS a FROM ticket_assets', readsFrom: {db.ticketAssets})
      .get();
  final fromRows = await db
      .customSelect(
        'SELECT DISTINCT prodotto_assistenza_id AS a FROM ticket_controls '
        'WHERE prodotto_assistenza_id IS NOT NULL',
        readsFrom: {db.ticketControls},
      )
      .get();
  final refs = {...fromCoverage.map((r) => r.read<String>('a')), ...fromRows.map((r) => r.read<String>('a'))};
  final all = await db.select(db.assets).get();
  final drop = all.where((a) => !refs.contains(a.id)).map((a) => a.id).toList();
  if (drop.isNotEmpty) {
    await (db.delete(db.assets)..where((a) => a.id.isIn(drop))).go();
  }
}

/// Forgets omitted-ticket bookkeeping for tickets the phone no longer holds.
Future<void> pruneOmittedWithoutTicket(AppDatabase db) {
  return db.customStatement(
    'DELETE FROM checklist_omitted_tickets WHERE ticket_id NOT IN (SELECT id FROM tickets)',
  );
}

/// The instrument catalogue, replaced wholesale (the server sends every active tenant instrument
/// each time; an empty list means the user lost `team.strumento.read`). A civil date is stored as
/// 'yyyy-MM-dd' text.
Future<void> replaceStrumenti(AppDatabase db, List<SyncStrumentoDto> list) {
  return db.transaction(() async {
    await db.delete(db.strumenti).go();
    await db.batch(
      (b) => b.insertAll(
        db.strumenti,
        [
          for (final s in list)
            StrumentiCompanion.insert(
              id: s.id,
              name: s.name,
              matricola: s.matricola,
              calibrationExpiry: Value(_label(s.calibrationExpiry)),
              certificateReference: Value(s.certificateReference),
              isMine: Value(s.isMine),
            ),
        ],
        mode: InsertMode.insertOrReplace,
      ),
    );
  });
}

/// Instruments the server holds for this user's Bozza reports. Replaced per report that is in the
/// payload, EXCEPT reports whose local row is `isLocalOnly` (the technician's working copy is
/// authoritative — the same rule `_upsertDraftReports` applies to the header).
Future<void> replaceServerReportStrumenti(
  AppDatabase db, {
  required Iterable<String> reportIdsInPayload,
  required List<SyncReportStrumentoDto> rows,
}) {
  return db.transaction(() async {
    final ids = reportIdsInPayload.toSet();
    if (ids.isEmpty) return;
    final local = (await (db.select(db.draftReports)
              ..where((r) => r.id.isIn(ids) & r.isLocalOnly.equals(true)))
            .get())
        .map((r) => r.id)
        .toSet();
    final replace = ids.difference(local);
    if (replace.isEmpty) return;
    await (db.delete(db.reportStrumenti)
          ..where((s) => s.reportId.isIn(replace) & s.isLocal.equals(false)))
        .go();
    await db.batch(
      (b) => b.insertAll(
        db.reportStrumenti,
        [
          for (final s in rows.where((s) => replace.contains(s.reportId)))
            ReportStrumentiCompanion.insert(
              id: s.id,
              reportId: s.reportId,
              strumentoId: Value(s.strumentoId),
              name: s.name,
              matricola: s.matricola,
              calibrationExpiry: Value(_label(s.calibrationExpiry)),
              certificateReference: Value(s.certificateReference),
              expiredAtUse: Value(s.expiredAtUse),
              expiredAcknowledged: Value(s.expiredAcknowledged),
            ),
        ],
        mode: InsertMode.insertOrReplace,
      ),
    );
  });
}

String? _label(DateTime? civil) => civil == null ? null : formatWorkDate(civil, 'yyyy-MM-dd');
