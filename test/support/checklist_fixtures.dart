import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/checklist_reconciler.dart';
import 'package:tasktap_mobile/data/sync/checklist_sync_dto.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

/// Ticket `t1` covering libretto `lib` ("Libretto Nord") and [assets] children `a0..` named
/// "Caldaia 1..", each with 15 controls `c-<asset>-<k>`: k 0-9 Checkbox, 10-12 Number, 13 Text,
/// 14 Options ("A"/"B"); k < 5 required; lineage `l<k>`. All in one group "Sicurezza".
Future<void> seedBigTicket(AppDatabase db, {int assets = 200}) {
  ControlType typeOf(int k) => k < 10
      ? ControlType.checkbox
      : k < 13
      ? ControlType.number
      : k == 13
      ? ControlType.text
      : ControlType.options;
  return applyChecklistBatch(
    db,
    ChecklistBatch(
      authoritativeTicketIds: {'t1'},
      controlGroups: const [
        SyncControlGroupDto(id: 'g1', maintenanceTemplateVersionId: 'v1', name: 'Sicurezza', sortOrder: 0),
      ],
      ticketControls: [
        for (var a = 0; a < assets; a++)
          for (var k = 0; k < 15; k++)
            SyncTicketControlDto(
              id: 'c-$a-$k', ticketId: 't1', prodottoAssistenzaId: 'a$a', templateControlId: 'tc-$k',
              controlLineageId: 'l$k', groupId: 'g1', label: 'Controllo $k', type: typeOf(k),
              isRequired: k < 5, sortOrder: k, options: k == 14 ? '["A","B"]' : null,
            ),
      ],
      ticketAssets: [
        const SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'lib'),
        for (var a = 0; a < assets; a++)
          SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'a$a', maintenanceTemplateVersionId: 'v1'),
      ],
      assets: [
        const SyncAssetDto(id: 'lib', name: 'Libretto Nord'),
        for (var a = 0; a < assets; a++)
          SyncAssetDto(id: 'a$a', name: 'Caldaia ${a + 1}', matricola: 'M-${1000 + a}', librettoIds: const ['lib']),
      ],
    ),
  );
}
