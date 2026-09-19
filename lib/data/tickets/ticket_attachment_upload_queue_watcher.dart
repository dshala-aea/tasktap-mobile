// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ticket/ticket_detail_api_client.dart';
import '../../features/ticket/ticket_providers.dart';
import '../sync/connectivity_provider.dart';
import '../sync/sync_service.dart';
import 'pending_ticket_attachment_repository.dart';
import 'ticket_attachment_upload_queue.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TicketAttachmentUploadQueueWatcher
//
// Mirrors ticket_creation_queue_watcher.dart: registers a reconnect hook so an
// attachment picked while offline is uploaded automatically once connectivity
// is restored.
//
// Call [initTicketAttachmentUploadQueueWatcher] once from the root widget
// (after auth) — see HomeShell.initState, alongside
// initTicketCreationQueueWatcher.
// ══════════════════════════════════════════════════════════════════════════════

final pendingTicketAttachmentRepositoryProvider = Provider<PendingTicketAttachmentRepository>((
  ref,
) {
  return PendingTicketAttachmentRepository(ref.watch(appDatabaseProvider));
});

/// Provides the real [TicketAttachmentUploadQueue]. On every successful upload it invalidates the
/// server-fetched attachment list for that ticket, so the file appears in the Allegati tab
/// without the technician having to leave and reopen it.
final ticketAttachmentUploadQueueProvider = Provider<TicketAttachmentUploadQueue>((ref) {
  final repo = ref.watch(pendingTicketAttachmentRepositoryProvider);
  final apiClient = ref.watch(ticketDetailApiClientProvider);
  return TicketAttachmentUploadQueue(
    repo: repo,
    apiClient: apiClient,
    onUploaded: (ticketId) => ref.invalidate(ticketAttachmentsProvider(ticketId)),
  );
});

/// Call once on app start. Registers the offline→online reconnect hook that flushes
/// `pendingSync` attachments — the ones picked while genuinely offline, whose upload request was
/// therefore never sent and is safe to resend automatically. `failed` attachments (sent, outcome
/// unknown) are deliberately excluded — see [TicketAttachmentUploadQueue] doc comment.
///
/// Returns the cancel function to invoke from the caller's `dispose()` — see
/// timbra_sync_watcher.dart's doc comment for why this matters.
VoidCallback initTicketAttachmentUploadQueueWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  final cancel = connectivity.onReconnect(() {
    ref.read(ticketAttachmentUploadQueueProvider).processAll();
  });

  // Also attempt a flush immediately (covers attachments picked offline before this watcher was
  // registered, and startup when already online).
  Future.microtask(() {
    ref.read(ticketAttachmentUploadQueueProvider).processAll();
  });

  return cancel;
}
