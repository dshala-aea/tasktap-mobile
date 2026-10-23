// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/checklist_read_repository.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider, syncServiceProvider;
import '../../domain/checklist/checklist_models.dart';
import '../../domain/checklist/required_controls_mirror.dart';
import '../../presentation/providers/report_editor_providers.dart';

final checklistReadRepositoryProvider = Provider<ChecklistReadRepository>(
  (ref) => ChecklistReadRepository(ref.watch(appDatabaseProvider)),
);

/// The asset checklists of one ticket, straight from the local mirror (works offline).
final ticketChecklistProvider = StreamProvider.autoDispose.family<TicketChecklist, String>(
  (ref, ticketId) => ref.watch(checklistReadRepositoryProvider).watchTicketChecklist(ticketId),
);

/// Whether [ticketId] itself ever reached this device's mirror.
///
/// The per-ticket counterpart of `hasSyncedAtLeastOnceProvider`: a ticket the device knows has
/// mirror rows that are its own complete answer, empty included — the sync payload replaces a
/// ticket's fabbisogno and checklist wholesale, so absence there is the tenant's answer, not a
/// gap. A ticket the device does not know proves nothing at all, and a tab rendering its empty
/// mirror as "nessun fabbisogno" / "questo ticket non ha asset con una checklist" was turning
/// "not downloaded" into a statement about the customer's site.
///
/// Wraps the repository's own test rather than repeating the query: it is a plain "is there a
/// `tickets` row", and a second copy would be free to drift from the first.
final ticketMirrorKnownProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  ticketId,
) {
  return ref.watch(checklistReadRepositoryProvider).hasSyncedTicket(ticketId);
});

/// "Scarica checklist": the per-ticket REST backfill. A provider so tests can replace it.
final checklistBackfillProvider = Provider<Future<void> Function(String ticketId)>(
  (ref) =>
      (ticketId) => ref.read(syncServiceProvider).checklistRefetch.backfillTicket(ticketId),
);

/// The answers this report currently holds, keyed by TicketControl id. Fed by the editor's local
/// rows so the checklist screen and the Riepilogo warning read the same values the send will carry.
final controlAnswersProvider =
    Provider.autoDispose.family<Map<String, ChecklistAnswer>, String>((ref, reportId) {
  final rows = ref.watch(reportEditorProvider(reportId).select((s) => s.controlloRows));
  return {
    for (final r in rows)
      r.controlId: ChecklistAnswer(
        stringValue: r.stringValue,
        boolValue: r.boolValue,
        dateValue: r.dateValue,
        numberValue: r.numberValue,
        note: r.note,
      ),
  };
});

/// The client's mirror of the required-controls gate, or null when the report has no ticket yet
/// (or its checklist is not in the local mirror). Never blocks: it informs Riepilogo.
final assetChecklistStatusProvider =
    Provider.autoDispose.family<AssetChecklistStatus?, String>((ref, reportId) {
  final ticketId = ref.watch(reportEditorProvider(reportId).select((s) => s.ticketId));
  if (ticketId == null || ticketId.isEmpty) return null;
  final tree = ref.watch(ticketChecklistProvider(ticketId)).valueOrNull;
  if (tree == null) return null;
  final answers = ref.watch(controlAnswersProvider(reportId));
  return assetChecklistStatus(tree, (id) => answers[id]);
});
