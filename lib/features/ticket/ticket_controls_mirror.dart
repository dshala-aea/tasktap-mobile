// dart format width=100
import '../../data/local/app_database.dart';
import '../../domain/checklist/checklist_models.dart' show naturalCompare;
import 'ticket_detail_api_client.dart';

/// Builds the checklist groups `GET /api/tickets/{id}/controls` returns from the rows the
/// checklist sync already mirrors locally — so the Controllo tab can render a ticket's controls
/// with zero network.
///
/// The shape is [TicketDetailApiClient.fetchControls]' own: a `subgroups`/`controls` tree whose
/// roots are the groups with no parent, groups ordered by `sortOrder` then name, controls by
/// `sortOrder` then label. Rows and groups arrive raw from
/// [ChecklistReadRepository.watchTicketControlRows]/`watchControlGroups` — the Drift row types are
/// reused so this file owns the conversion the data layer is not allowed to know about.
///
/// Only the groups on a path from a used group up to its root are emitted: the `control_groups`
/// table is shared by every ticket pinned to the same template version, so the table as a whole is
/// not this ticket's tree. Only ticket-level rows (`prodottoAssistenzaId` null) are emitted too —
/// `fetchControls` returns the ticket-level groups, per-asset groups ride in `assetChecklists`.
///
/// What the mirror cannot carry:
/// * `TicketControlDto.valoreLimite` — the sync payload has no such column, so it is always null
///   here rather than invented from the row's `options`/values.
/// * `TicketControlGroupDto.description` — `control_groups` has no description column either, so it
///   is always null.
List<TicketControlGroupDto> ticketControlGroupsFromMirror({
  required List<TicketControlRow> controls,
  required List<ControlGroupRow> groups,
}) {
  final groupById = {for (final g in groups) g.id: g};
  final rowsByGroup = <String, List<TicketControlDto>>{};
  for (final row in controls) {
    // `fetchControls`' `groups` are the ticket-level tree only: per-asset rows reach the screen
    // through `assetChecklists` online and through the asset card (`watchTicketChecklist`) offline.
    // Including them here would list every asset's controls a second time in the flat list.
    if (row.prodottoAssistenzaId != null) continue;
    (rowsByGroup[row.groupId] ??= []).add(_toDto(row));
  }

  // Every group on the path from a used group up to its root — never the whole shared table.
  final needed = <String>{};
  for (final groupId in rowsByGroup.keys) {
    var current = groupById[groupId];
    while (current != null && needed.add(current.id)) {
      current = current.parentGroupId == null ? null : groupById[current.parentGroupId!];
    }
  }

  final children = <String?, List<ControlGroupRow>>{};
  for (final id in needed) {
    final group = groupById[id]!;
    // A parent that never arrived makes its child a root rather than losing it — same rule as the
    // repository's own asset tree.
    final parent =
        group.parentGroupId != null && groupById.containsKey(group.parentGroupId)
        ? group.parentGroupId
        : null;
    (children[parent] ??= []).add(group);
  }

  TicketControlGroupDto node(ControlGroupRow group) => TicketControlGroupDto(
    id: group.id,
    name: group.name,
    description: null,
    sortOrder: group.sortOrder,
    subgroups: [for (final child in _sortedGroups(children[group.id])) node(child)],
    controls: _sortedControls(rowsByGroup[group.id]),
  );

  final roots = <TicketControlGroupDto>[
    for (final group in _sortedGroups(children[null])) node(group),
  ];

  // A row whose group is unknown is never dropped: one synthetic section, exactly as the asset
  // tree does. The server never sends this shape; a local drift between rows and groups can.
  final orphans = [
    for (final entry in rowsByGroup.entries)
      if (!groupById.containsKey(entry.key)) ...entry.value,
  ];
  if (orphans.isNotEmpty) {
    roots.add(
      TicketControlGroupDto(
        id: 'orphan',
        name: 'Altri controlli',
        sortOrder: 1 << 30,
        controls: _sortedControls(orphans),
      ),
    );
  }
  return roots;
}

/// One mirrored row as the wire DTO. Every field the mirror stores is carried across;
/// `valoreLimite` stays null because the sync payload does not have it (see this file's header),
/// and `prodottoAssistenzaId` is always null here because the ticket-level tree holds no asset
/// rows — the field is still mapped rather than dropped, so the DTO never claims an asset.
TicketControlDto _toDto(TicketControlRow row) => TicketControlDto(
  id: row.id,
  templateControlId: row.templateControlId,
  label: row.label,
  description: row.description,
  type: controlTypeFromWire(row.type),
  isRequired: row.isRequired,
  options: row.options,
  valoreLimite: null,
  sortOrder: row.sortOrder,
  status: row.status,
  stringValue: row.stringValue,
  boolValue: row.boolValue,
  dateValue: row.dateValue,
  numberValue: row.numberValue,
  controlLineageId: row.controlLineageId,
  note: row.note,
  prodottoAssistenzaId: row.prodottoAssistenzaId,
);

List<TicketControlDto> _sortedControls(List<TicketControlDto>? list) =>
    [...?list]..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : naturalCompare(a.label, b.label);
    });

List<ControlGroupRow> _sortedGroups(List<ControlGroupRow>? list) =>
    [...?list]..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : naturalCompare(a.name, b.name);
    });
