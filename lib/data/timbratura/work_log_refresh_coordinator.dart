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
import '../../features/timbra/timbra_providers.dart' show giornataProvider;
import 'punch_pipeline_flag.dart' show punchPipelineEnabledReaderProvider;
import 'punch_snapshot_providers.dart' show punchSnapshotRefresherProvider;
import 'timbra_sync_service.dart' show timbraSyncServiceProvider;
import 'work_log_reconciler.dart';

class WorkLogRefreshCoordinator {
  WorkLogRefreshCoordinator({
    required Future<void> Function() reconcile,
    required void Function() refetchTrackers,
    Future<void> Function()? syncPending,
    void Function()? refetchGiornata,
    this.debounce = const Duration(seconds: 1),
  }) : _reconcile = reconcile,
       _refetchTrackers = refetchTrackers,
       _syncPending = syncPending,
       _refetchGiornata = refetchGiornata;

  final Future<void> Function() _reconcile;
  final Future<void> Function()? _syncPending;
  final void Function() _refetchTrackers;

  /// Re-reads the server's `availableActions` (`giornataProvider`). The punch/pause guards judge
  /// the tap against it, so it must be fetched AFTER the sync + reconcile above have changed what
  /// this device believes: a copy read before (e.g. while not clocked in, ClockOut/StartBreak
  /// disabled as `not_clocked_in`) would otherwise block the very next tap once the local events
  /// are synced and no longer count as pending.
  final void Function()? _refetchGiornata;

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
  ///
  /// [sync] first retries queued timbratura commands (a Fine/Pausa/Ripresa on a shift started
  /// elsewhere that failed transiently — valid only within its short TTL), so the reconcile that
  /// follows sees their outcome. TimbraSyncService itself passes `sync: false` to avoid looping.
  Future<void> refreshNow({bool sync = true}) async {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _refetchTrackers();
    try {
      if (sync) await _syncPending?.call();
    } catch (_) {
      // A failing sync must not stop the reconcile.
    }
    try {
      await _reconcile();
    } catch (_) {
      // Best effort — see header.
    }
    if (_disposed) return;
    _refetchGiornata?.call();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

final Provider<WorkLogRefreshCoordinator> workLogRefreshCoordinatorProvider =
    Provider<WorkLogRefreshCoordinator>((ref) {
      final coordinator = WorkLogRefreshCoordinator(
        // On the unified pipeline the server's state replaces the phone's snapshot: nothing is invented
        // into the local log. The legacy reconciler stays for tenants that are not on the pipeline.
        reconcile: () async {
          if (await ref.read(punchPipelineEnabledReaderProvider)()) {
            await ref.read(punchSnapshotRefresherProvider).refresh();
          } else {
            await ref.read(workLogReconcilerProvider).reconcile();
          }
        },
        refetchTrackers: () => ref.invalidate(activeTrackersProvider),
        refetchGiornata: () => ref.invalidate(giornataProvider),
        syncPending: () => ref.read(timbraSyncServiceProvider).syncNow(),
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });
