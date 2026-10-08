// dart format width=100
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/checklist/checklist_models.dart';
import '../../domain/checklist/control_type.dart';
import 'app_database.dart';

/// Reads the per-asset checklist mirror as a [TicketChecklist]. Everything here is local: it works
/// with zero network.
class ChecklistReadRepository {
  ChecklistReadRepository(this._db);

  final AppDatabase _db;

  Stream<TicketChecklist> watchTicketChecklist(String ticketId) {
    final controls =
        (_db.select(_db.ticketControls)..where(
              (c) => c.ticketId.equals(ticketId) & c.prodottoAssistenzaId.isNotNull(),
            ))
            .watch();
    final coverage = (_db.select(_db.ticketAssets)..where((a) => a.ticketId.equals(ticketId))).watch();
    final assets = _db.select(_db.assets).watch();
    final groups = _db.select(_db.controlGroups).watch();
    final omitted =
        (_db.select(_db.checklistOmittedTickets)..where((o) => o.ticketId.equals(ticketId))).watch();
    return Rx.combineLatest5<List<TicketControlRow>, List<TicketAssetRow>, List<AssetRow>,
        List<ControlGroupRow>, List<ChecklistOmittedTicketRow>, TicketChecklist>(
      controls,
      coverage,
      assets,
      groups,
      omitted,
      (c, cov, a, g, o) => buildTree(
        ticketId: ticketId,
        coverage: cov,
        assets: a,
        controls: c,
        groups: g,
        omitted: o.isNotEmpty,
      ),
    );
  }

  static TicketChecklist buildTree({
    required String ticketId,
    required List<TicketAssetRow> coverage,
    required List<AssetRow> assets,
    required List<TicketControlRow> controls,
    required List<ControlGroupRow> groups,
    required bool omitted,
  }) {
    final assetById = {for (final a in assets) a.id: a};
    final groupById = {for (final g in groups) g.id: g};
    final coverageById = {for (final c in coverage) c.prodottoAssistenzaId: c};
    final rowsByAsset = <String, List<TicketControlRow>>{};
    for (final c in controls) {
      final id = c.prodottoAssistenzaId;
      if (id != null) (rowsByAsset[id] ??= []).add(c);
    }
    final ids = {...coverageById.keys, ...rowsByAsset.keys};

    AssetChecklist make(String id) {
      final cov = coverageById[id];
      final row = assetById[id];
      final rows = rowsByAsset[id] ?? const <TicketControlRow>[];
      return AssetChecklist(
        assetId: id,
        name: row?.name ?? 'Asset',
        matricola: row?.matricola ?? row?.serialNumber,
        templated: cov?.maintenanceTemplateVersionId != null || rows.isNotEmpty,
        legacyControllato: cov?.controllato ?? false,
        legacyNote: cov?.note,
        coveredNow: cov != null,
        groups: _groupTree(rows, groupById),
      );
    }

    final made = {for (final id in ids) id: make(id)};
    final childrenOf = <String, List<String>>{};
    final childIds = <String>{};
    for (final id in ids) {
      final row = assetById[id];
      if (row == null) continue;
      for (final lib in _libretti(row)) {
        if (lib != id && coverageById.containsKey(lib)) {
          (childrenOf[lib] ??= []).add(id);
          childIds.add(id);
        }
      }
    }

    int byName(AssetChecklist a, AssetChecklist b) => naturalCompare(a.name, b.name);
    final librettos = [
      for (final e in childrenOf.entries)
        LibrettoGroup(
          libretto: made[e.key]!,
          children: [for (final c in e.value) made[c]!]..sort(byName),
        ),
    ]..sort((x, y) => byName(x.libretto, y.libretto));
    final standalone = [
      for (final id in ids)
        if (!childrenOf.containsKey(id) && !childIds.contains(id)) made[id]!,
    ]..sort(byName);

    return TicketChecklist(
      ticketId: ticketId,
      librettos: librettos,
      standalone: standalone,
      omitted: omitted,
    );
  }

  static List<String> _libretti(AssetRow row) {
    try {
      return (jsonDecode(row.librettoIdsJson) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  static ChecklistControl _toControl(TicketControlRow r) => ChecklistControl(
    id: r.id,
    ticketId: r.ticketId,
    assetId: r.prodottoAssistenzaId,
    templateControlId: r.templateControlId,
    lineageId: r.controlLineageId,
    groupId: r.groupId,
    label: r.label,
    description: r.description,
    type: controlTypeFromWire(r.type),
    isRequired: r.isRequired,
    options: r.options,
    sortOrder: r.sortOrder,
    status: r.status,
    stored: ChecklistAnswer(
      stringValue: r.stringValue,
      boolValue: r.boolValue,
      dateValue: r.dateValue,
      numberValue: r.numberValue,
      note: r.note,
    ),
    isRetained: r.isRetained,
  );

  static List<ChecklistControl> _sortedControls(List<ChecklistControl>? list) =>
      [...?list]..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : naturalCompare(a.label, b.label);
      });

  static List<ControlGroupRow> _sortedGroups(List<ControlGroupRow>? list) =>
      [...?list]..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : naturalCompare(a.name, b.name);
      });

  static List<ChecklistGroup> _groupTree(
    List<TicketControlRow> rows,
    Map<String, ControlGroupRow> groupById,
  ) {
    if (rows.isEmpty) return const [];
    final byGroup = <String, List<ChecklistControl>>{};
    for (final r in rows) {
      (byGroup[r.groupId] ??= []).add(_toControl(r));
    }
    // Every group on the path from a used group up to its root.
    final needed = <String>{};
    for (final gid in byGroup.keys) {
      var cur = groupById[gid];
      while (cur != null && needed.add(cur.id)) {
        cur = cur.parentGroupId == null ? null : groupById[cur.parentGroupId!];
      }
    }
    final children = <String?, List<ControlGroupRow>>{};
    for (final id in needed) {
      final g = groupById[id]!;
      // A parent that never arrived makes its child a root rather than losing it.
      final parent = g.parentGroupId != null && groupById.containsKey(g.parentGroupId) ? g.parentGroupId : null;
      (children[parent] ??= []).add(g);
    }
    ChecklistGroup node(ControlGroupRow g) => ChecklistGroup(
      id: g.id,
      name: g.name,
      sortOrder: g.sortOrder,
      subgroups: [for (final c in _sortedGroups(children[g.id])) node(c)],
      controls: _sortedControls(byGroup[g.id]),
    );
    final roots = [for (final g in _sortedGroups(children[null])) node(g)];
    // Rows whose group is unknown are never dropped: one synthetic section.
    final orphans = [
      for (final e in byGroup.entries)
        if (!groupById.containsKey(e.key)) ...e.value,
    ];
    if (orphans.isNotEmpty) {
      roots.add(
        ChecklistGroup(
          id: 'orphan',
          name: 'Altri controlli',
          sortOrder: 1 << 30,
          controls: _sortedControls(orphans),
        ),
      );
    }
    return roots;
  }
}
