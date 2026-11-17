// ══════════════════════════════════════════════════════════════════════════════
// TicketTimerSyncWatcher
//
// Mirrors cantiere_timbra_sync_watcher.dart: registers a reconnect hook so ticket timer sessions
// recorded on the device are pushed as soon as connectivity is restored. Without it a session
// started in a basement and stopped there would only reach the server the next time the technician
// happened to open that ticket and tap again — hours are what the customer is billed from, so they
// must not wait on a screen being visited.
//
// Call [initTicketTimerSyncWatcher] once from the root widget (after auth), and cancel the
// returned callback on dispose — the same lifecycle rule the other watchers follow (see
// timbra_sync_watcher.dart's doc comment for what a stale registration breaks).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/connectivity_provider.dart';
import 'ticket_timer_sync_service.dart';

/// Registers the offline→online reconnect hook for ticket timer syncing.
VoidCallback initTicketTimerSyncWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  final cancel = connectivity.onReconnect(() {
    ref.read(ticketTimerSyncServiceProvider).syncNow();
  });

  // Also attempt a sync immediately: covers sessions queued before the reconnect event fires, and
  // startup when the device is already online.
  Future.microtask(() {
    ref.read(ticketTimerSyncServiceProvider).syncNow();
  });

  return cancel;
}
