// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// WorkLogReconcileWatcher
//
// Mirrors auth_reconnect_watcher.dart / timbra_sync_watcher.dart: registers a
// reconnect hook plus a startup pass so a punch closed on another surface
// (same account, e.g. the office web) is picked up as soon as connectivity
// allows — not just on the next periodic poll or app resume.
//
// The other two trigger points (app foreground resume, 60s periodic poll while
// foregrounded) live in HomeShell, alongside the equivalent lifecycle-driven
// triggers for sync/timbra — see home_shell.dart's WidgetsBindingObserver.
//
// Call [initWorkLogReconcileWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/connectivity_provider.dart';
import 'work_log_reconciler.dart';

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
/// Registers the offline→online reconnect hook for worklog reconciliation.
///
/// Returns the cancel function to invoke from the caller's `dispose()` — see
/// timbra_sync_watcher.dart's doc comment for why this matters.
VoidCallback initWorkLogReconcileWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  final cancel = connectivity.onReconnect(() {
    ref.read(workLogReconcilerProvider).reconcile();
  });

  // Also reconcile immediately on startup (covers a stop that happened on another surface while
  // this device was closed, and the common case of already being online).
  Future.microtask(() {
    ref.read(workLogReconcilerProvider).reconcile();
  });

  return cancel;
}
