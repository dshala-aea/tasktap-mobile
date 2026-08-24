// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereWorkLogReconcileWatcher
//
// Mirrors work_log_reconcile_watcher.dart: registers a reconnect hook plus a startup pass so a
// cantiere session closed on another surface is picked up as soon as connectivity allows.
//
// The other trigger points (app foreground resume, 60s periodic poll while foregrounded) live in
// HomeShell alongside the personal-timbra equivalent.
//
// Call [initCantiereWorkLogReconcileWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/connectivity_provider.dart';
import 'cantiere_work_log_reconciler.dart';

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
/// Registers the offline→online reconnect hook for cantiere worklog reconciliation.
void initCantiereWorkLogReconcileWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  connectivity.onReconnect(() {
    ref.read(cantiereWorkLogReconcilerProvider).reconcile();
  });

  Future.microtask(() {
    ref.read(cantiereWorkLogReconcilerProvider).reconcile();
  });
}
