// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereTimbraSyncWatcher
//
// Mirrors timbra_sync_watcher.dart: registers a reconnect hook so that cantiere punches stored
// offline are pushed to the server automatically when connectivity is restored.
//
// Call [initCantiereTimbraSyncWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/connectivity_provider.dart';
import 'cantiere_timbra_sync_service.dart';

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
/// Registers the offline→online reconnect hook for cantiere timbra syncing.
///
/// Returns the cancel function to invoke from the caller's `dispose()` — see
/// timbra_sync_watcher.dart's doc comment for why this matters.
VoidCallback initCantiereTimbraSyncWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  final cancel = connectivity.onReconnect(() {
    ref.read(cantiereTimbraSyncServiceProvider).syncNow();
  });

  // Also attempt a sync immediately (covers sessions recorded while offline before the reconnect
  // event fires, and startup when already online).
  Future.microtask(() {
    ref.read(cantiereTimbraSyncServiceProvider).syncNow();
  });

  return cancel;
}
