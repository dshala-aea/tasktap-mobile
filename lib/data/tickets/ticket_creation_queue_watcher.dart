// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ticket/ticket_api_client.dart';
import '../sync/connectivity_provider.dart';
import '../sync/sync_service.dart';
import 'pending_ticket_repository.dart';
import 'ticket_creation_queue.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TicketCreationQueueWatcher
//
// Mirrors submission_queue_watcher.dart / timbra_sync_watcher.dart: registers
// a reconnect hook so tickets created while offline are pushed to the server
// automatically when connectivity is restored.
//
// Call [initTicketCreationQueueWatcher] once from the root widget (after
// auth) — see HomeShell.initState.
// ══════════════════════════════════════════════════════════════════════════════

final pendingTicketRepositoryProvider = Provider<PendingTicketRepository>((ref) {
  return PendingTicketRepository(ref.watch(appDatabaseProvider));
});

/// Provides the real [TicketCreationQueue]. On every successful create it
/// triggers a full sync so the just-created ticket — now with its real,
/// server-assigned tenantId/createdAt — is pulled down into the `tickets`
/// Drift table, which is what [ticketsProvider] watches. That's what makes
/// the new ticket appear in the list without an app restart.
final ticketCreationQueueProvider = Provider<TicketCreationQueue>((ref) {
  final repo = ref.watch(pendingTicketRepositoryProvider);
  final apiClient = ref.watch(ticketApiClientProvider);
  return TicketCreationQueue(
    repo: repo,
    apiClient: apiClient,
    onSubmitted: () => ref.read(syncProvider.notifier).performSync(),
  );
});

/// Call once on app start. Registers the offline→online reconnect hook that
/// flushes `pendingSync` tickets — the ones created while genuinely offline,
/// whose create request was therefore never sent and is safe to resend
/// automatically. `failed` tickets (sent, outcome unknown) are deliberately
/// excluded — see [TicketCreationQueue] doc comment.
void initTicketCreationQueueWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  connectivity.onReconnect(() {
    ref.read(ticketCreationQueueProvider).processAll();
  });

  // Also attempt a flush immediately (covers tickets created offline before
  // this watcher was registered, and startup when already online).
  Future.microtask(() {
    ref.read(ticketCreationQueueProvider).processAll();
  });
}
