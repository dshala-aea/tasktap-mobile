// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// TimbraSyncWatcher
//
// Mirrors submission_queue_watcher.dart: registers a reconnect hook so that
// timbra punches stored offline are pushed to the server automatically when
// connectivity is restored.
//
// Call [initTimbraSyncWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/connectivity_provider.dart';
import 'timbra_sync_service.dart';

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
/// Registers the offline→online reconnect hook for timbra syncing.
void initTimbraSyncWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  connectivity.onReconnect(() {
    ref.read(timbraSyncServiceProvider).syncNow();
  });

  // Also attempt a sync immediately (covers sessions recorded while offline
  // before the reconnect event fires, and startup when already online).
  Future.microtask(() {
    ref.read(timbraSyncServiceProvider).syncNow();
  });
}
