// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/checklist_read_repository.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider, syncServiceProvider;
import '../../domain/checklist/checklist_models.dart';

final checklistReadRepositoryProvider = Provider<ChecklistReadRepository>(
  (ref) => ChecklistReadRepository(ref.watch(appDatabaseProvider)),
);

/// The asset checklists of one ticket, straight from the local mirror (works offline).
final ticketChecklistProvider = StreamProvider.autoDispose.family<TicketChecklist, String>(
  (ref, ticketId) => ref.watch(checklistReadRepositoryProvider).watchTicketChecklist(ticketId),
);

/// "Scarica checklist": the per-ticket REST backfill. A provider so tests can replace it.
final checklistBackfillProvider = Provider<Future<void> Function(String ticketId)>(
  (ref) =>
      (ticketId) => ref.read(syncServiceProvider).checklistRefetch.backfillTicket(ticketId),
);
