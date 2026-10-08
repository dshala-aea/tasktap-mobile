// dart format width=100
import '../../features/ticket/ticket_detail_api_client.dart';
import 'checklist_reconciler.dart';
import 'checklist_sync_dto.dart';

/// Maps `GET /api/tickets/{id}/controls` onto the same [ChecklistBatch] the sync payload produces,
/// so a per-ticket backfill and a sync write the mirror identically.
///
/// Lossy in two documented ways: ticket-level groups carry no template version id (the REST shape
/// has none; they are stored with ''), and a child shows ONE libretto even when it sits under two
/// (the REST shape has one `librettoId`); the next sync that carries the ticket restores both.
ChecklistBatch checklistBatchFromRest(String ticketId, TicketControlResponseDto r) {
  final groups = <String, SyncControlGroupDto>{};
  final controls = <SyncTicketControlDto>[];

  void walk(
    List<TicketControlGroupDto> level, {
    String? parent,
    required String version,
    String? assetId,
  }) {
    for (final g in level) {
      groups[g.id] = SyncControlGroupDto(
        id: g.id,
        parentGroupId: parent,
        maintenanceTemplateVersionId: version,
        name: g.name,
        sortOrder: g.sortOrder,
      );
      for (final c in g.controls) {
        controls.add(
          SyncTicketControlDto(
            id: c.id,
            ticketId: ticketId,
            prodottoAssistenzaId: assetId ?? c.prodottoAssistenzaId,
            templateControlId: c.templateControlId,
            controlLineageId: c.controlLineageId,
            groupId: g.id,
            label: c.label,
            description: c.description,
            type: c.type,
            isRequired: c.isRequired,
            options: c.options,
            sortOrder: c.sortOrder,
            status: c.status,
            stringValue: c.stringValue,
            boolValue: c.boolValue,
            dateValue: c.dateValue,
            numberValue: c.numberValue,
            note: c.note,
          ),
        );
      }
      walk(g.subgroups, parent: g.id, version: version, assetId: assetId);
    }
  }

  walk(r.groups, version: '');

  final assets = <String, SyncAssetDto>{};
  final coverage = <SyncTicketAssetDto>[];
  for (final a in r.assetChecklists) {
    walk(a.groups, version: a.maintenanceTemplateVersionId, assetId: a.prodottoAssistenzaId);
    coverage.add(
      SyncTicketAssetDto(
        ticketId: ticketId,
        prodottoAssistenzaId: a.prodottoAssistenzaId,
        maintenanceTemplateVersionId: a.maintenanceTemplateVersionId,
      ),
    );
    assets[a.prodottoAssistenzaId] = SyncAssetDto(
      id: a.prodottoAssistenzaId,
      name: a.name,
      matricola: a.matricola,
      librettoIds: [if (a.librettoId != null) a.librettoId!],
    );
    final lib = a.librettoId;
    if (lib != null) {
      assets.putIfAbsent(lib, () => SyncAssetDto(id: lib, name: a.librettoName ?? ''));
    }
  }
  for (final p in r.assetProgress) {
    coverage.add(
      SyncTicketAssetDto(
        ticketId: ticketId,
        prodottoAssistenzaId: p.prodottoAssistenzaId,
        controllato: p.controllato,
        note: p.note,
      ),
    );
    assets.putIfAbsent(
      p.prodottoAssistenzaId,
      () => SyncAssetDto(id: p.prodottoAssistenzaId, name: p.prodottoAssistenzaName),
    );
  }

  return ChecklistBatch(
    authoritativeTicketIds: {ticketId},
    controlGroups: groups.values.toList(),
    ticketControls: controls,
    ticketAssets: coverage,
    assets: assets.values.toList(),
  );
}
