// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// WorkLogRefreshCoordinator
//
// The single entry point for "the server's clock state may have changed — look again". Every
// trigger funnels here: the SignalR `WorkLogChanged` push (debounced), app resume, a timbra /
// dashboard screen appearing, the foreground poll and connectivity restore (immediate).
//
// A refresh does two things, in parallel, because two different pieces of state go stale:
//  - [reconcile]: mirrors the server's attendance state into the local Drift `work_sessions`
//    (what the timbra buttons and the offline-first punch path read).
//  - [refetchTrackers]: invalidates `activeTrackersProvider` so the dashboard's list (including
//    cantiere / ticket clocks, which have no local mirror) re-reads GET /worklog/active.
//
// Never throws: offline is the normal condition of a phone in the field.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/active_trackers_provider.dart' show activeTrackersProvider;
import 'work_log_reconciler.dart';

class WorkLogRefreshCoordinator {
  WorkLogRefreshCoordinator({
    required Future<void> Function() reconcile,
    required void Function() refetchTrackers,
    this.debounce = const Duration(seconds: 1),
  }) : _reconcile = reconcile,
       _refetchTrackers = refetchTrackers;

  final Future<void> Function() _reconcile;
  final void Function() _refetchTrackers;

  /// Collapses a burst of pushes (start + break + resume in quick succession, or one action
  /// echoed by several devices) into a single refresh.
  final Duration debounce;

  Timer? _timer;
  bool _disposed = false;

  /// Debounced refresh, for pushed events. The window restarts on every call.
  void requestRefresh() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(refreshNow()));
  }

  /// Refreshes right now (resume, screen appearing, poll tick, reconnect), superseding any
  /// pending debounced refresh.
  Future<void> refreshNow() async {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _refetchTrackers();
    try {
      await _reconcile();
    } catch (_) {
      // Best effort — see header.
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

final workLogRefreshCoordinatorProvider = Provider<WorkLogRefreshCoordinator>((ref) {
  final coordinator = WorkLogRefreshCoordinator(
    reconcile: () => ref.read(workLogReconcilerProvider).reconcile(),
    refetchTrackers: () => ref.invalidate(activeTrackersProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
