// ══════════════════════════════════════════════════════════════════════════════
// WorkLogReconciler
//
// Corrects local timbratura state against the server's authoritative view.
//
// The gap this closes: `timbraStateProvider` (features/timbra/timbra_providers.dart) derives
// isOnShift/isOnPause purely from the local Drift `work_sessions` table, which is only ever
// written by this device's own punch/pause actions. If the SAME account clocks in, pauses or
// clocks out from another surface (the office web app, a second phone), the server's worklog
// changes but this device's local table never learns about it.
//
// Source of truth: `GET /api/worklog/active` (the same call the dashboard's activeTrackersProvider
// makes). Its attendance row carries `state` (Working | OnBreak), `shiftStartedAtUtc` and, while
// on a break, `startedAtUtc` = the break start — all true UTC. This replaced `GET
// /worklog/mobile/today`, whose `startTime` is a bare "HH:mm:ss" TimeSpan (Rome-local, no date)
// that cannot be turned into an instant, which made the old backfill silently no-op.
//
// Triggers (all funnel through WorkLogRefreshCoordinator): SignalR `WorkLogChanged`, app resume,
// reconnect, the timbra/dashboard screens appearing, and a foreground poll. Idempotent: it only
// acts when local disagrees with the server, so once they agree every call is a no-op.
//
// What it does, given the server's attendance row (or its absence):
// - server open, local has no open shift → backfill 'ingresso' at the shift start; if the server
//   is OnBreak also 'pausa' at the break start.
// - server Working, local OnBreak → 'ripresa' (break ended elsewhere).
// - server OnBreak, local Working → 'pausa' at the break start (break started elsewhere).
// - server has no open attendance, local has an open shift → 'fine' (clocked out elsewhere) and
//   the stale opener is marked.
//
// LOCAL UNSYNCED EVENTS ALWAYS WIN. A phone in a basement records punches offline and pushes them
// later (TimbraSyncService). Until that push lands the server legitimately disagrees, and
// "correcting" local state then would erase the technician's own punch. So when any local event
// is still pending (and is not one of our own marked corrections) the reconciler does nothing
// this round; the next pass, after the push, converges.
//
// Resurrection guard: every event written here is marked with `reconciledOrphanMarker` (an
// existing, previously-unused `notes` column — no schema migration needed); TimbraSyncService
// excludes marked events from its push, so a correction that only changes what this device
// *displays* is never re-sent as a fresh local-origin punch. See timbra_sync_service.dart.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/timbra/timbra_providers.dart'
    show deriveShiftState, workSessionRepositoryProvider;
import '../api/dio_client.dart';
import '../local/app_database.dart' show WorkSession;
import '../worklogs/active_tracker_api_client.dart';
import 'work_session_repository.dart';

const _uuid = Uuid();

// ── Server snapshot ───────────────────────────────────────────────────────────

/// The server's view of the caller's attendance, reduced to exactly what reconciliation needs.
class ServerWorkLogSnapshot {
  const ServerWorkLogSnapshot({
    required this.isOnShift,
    required this.isOnPause,
    this.activeStartTime,
    this.breakStartTime,
  });

  final bool isOnShift;
  final bool isOnPause;

  /// When the open working day started (true UTC). Null whenever [isOnShift] is false, or when the
  /// server supplied no usable instant — reconciliation only backfills a missing local shift when
  /// this is present, never guesses a start time.
  final DateTime? activeStartTime;

  /// When the open break started; only set while [isOnPause].
  final DateTime? breakStartTime;

  /// Reduces `GET /worklog/active` to an attendance snapshot. Cantiere/ticket rows are ignored:
  /// they have no local mirror and say nothing about the working day. No attendance row = the
  /// server has no open day.
  factory ServerWorkLogSnapshot.fromActiveTrackers(List<ActiveTracker> trackers) {
    final att = trackers.where((t) => t.kind == ActiveTrackerKind.attendance).firstOrNull;
    if (att == null) return const ServerWorkLogSnapshot(isOnShift: false, isOnPause: false);

    final onBreak = att.state == ActiveTrackerState.onBreak;
    return ServerWorkLogSnapshot(
      isOnShift: true,
      isOnPause: onBreak,
      // Older servers send no shiftStartedAtUtc; then startedAtUtc IS the day start (and can only
      // be trusted as such while not on a break, when it would be the break start).
      activeStartTime: att.shiftStartedAtUtc ?? att.startedAtUtc,
      breakStartTime: onBreak ? att.startedAtUtc : null,
    );
  }
}

// ── Reconciler ────────────────────────────────────────────────────────────────

class WorkLogReconciler {
  WorkLogReconciler({
    required IWorkSessionRepository repo,
    required Future<List<ActiveTracker>> Function() fetchActive,
  }) : _repo = repo,
       _fetchActive = fetchActive;

  final IWorkSessionRepository _repo;
  final Future<List<ActiveTracker>> Function() _fetchActive;

  // Reentrancy guard: resume, reconnect, a push and the poll can all fire close together. Without
  // it two overlapping reads of local state could both see the same stale "open" shift and each
  // append their own correction. A request that arrives mid-run is NOT dropped: the in-flight
  // fetch may have been answered before the change it describes, so we run once more afterwards.
  bool _running = false;
  bool _rerun = false;

  /// Fetches the server's running trackers and reconciles local state against them.
  ///
  /// Network/parse errors are swallowed, matching every other sync path in this app: offline is
  /// the normal condition of a phone in the field, not a failure to report. Without a server
  /// answer there is nothing safe to correct.
  Future<void> reconcile() async {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        try {
          final trackers = await _fetchActive();
          await _reconcileWith(ServerWorkLogSnapshot.fromActiveTrackers(trackers));
        } catch (_) {
          // Swallow — see doc comment above.
        }
      } while (_rerun);
    } finally {
      _running = false;
    }
  }

  /// Reconciles local state against an already-known [server] snapshot.
  ///
  /// Exposed separately from [reconcile] so the correction logic is testable without a network
  /// round trip. Not reentrancy-guarded itself (only [reconcile] is).
  Future<void> reconcileWith(ServerWorkLogSnapshot server) => _reconcileWith(server);

  Future<void> _reconcileWith(ServerWorkLogSnapshot server) async {
    final sessions = await _repo.getTodaySessions();

    // Local unsynced events win — see header. Our own marked corrections are excluded: they are
    // pending by construction but never pushed, and must not freeze reconciliation forever.
    final hasUnsynced = sessions.any((s) => s.isPendingSync && s.notes != reconciledOrphanMarker);
    if (hasUnsynced) return;

    final local = deriveShiftState(sessions);

    if (server.isOnShift) {
      if (!local.isOnShift) {
        await _backfillMissingShift(server);
        return;
      }
      if (server.isOnPause && !local.isOnPause) {
        await _addMarked('pausa', server.breakStartTime ?? DateTime.now().toUtc());
      } else if (!server.isOnPause && local.isOnPause) {
        // The instant the break ended elsewhere is not in the snapshot; "now" only affects what
        // this device displays (the event is never pushed).
        await _addMarked('ripresa', DateTime.now().toUtc());
      }
      return;
    }

    // Local still thinks a shift is open that the server has already closed (clocked out from
    // another surface, same account).
    if (!local.isOnShift) return;

    final opener = _findOpenOpener(sessions);
    if (opener != null) {
      await _repo.markReconciledOrphan(opener.id);
    }
    await _addMarked('fine', DateTime.now().toUtc());
  }

  /// Server has an open day this device has no local record of (started elsewhere, or a fresh
  /// install). Backfills 'ingresso' anchored on the server's own start — never `DateTime.now()`,
  /// which would understate worked time — and, when the server is on a break, the 'pausa' too so
  /// local state equals the server's. No-ops without a start time: fabricating one is worse than
  /// staying briefly stale.
  Future<void> _backfillMissingShift(ServerWorkLogSnapshot server) async {
    final start = server.activeStartTime;
    if (start == null) return;

    await _addMarked('ingresso', start);
    if (server.isOnPause) {
      final breakStart = server.breakStartTime;
      if (breakStart != null) {
        // Events are ordered by time; keep the pausa strictly after its ingresso even if the
        // server reports them equal.
        await _addMarked('pausa', breakStart.isAfter(start) ? breakStart : start.add(_epsilon));
      }
    }
  }

  static const _epsilon = Duration(milliseconds: 1);

  Future<void> _addMarked(String type, DateTime time) async {
    final id = _uuid.v4();
    await _repo.addEvent(id: id, eventTime: time, eventType: type);
    await _repo.markReconciledOrphan(id);
  }

  /// The most recent ingresso/ripresa that has no closing fine/pausa after it — i.e. the opener
  /// of the interval [deriveShiftState] is currently reporting as open.
  WorkSession? _findOpenOpener(List<WorkSession> sessions) {
    WorkSession? candidate;
    for (final s in sessions) {
      switch (s.eventType) {
        case 'ingresso':
        case 'ripresa':
          candidate = s;
        case 'fine':
        case 'pausa':
          candidate = null;
      }
    }
    return candidate;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final workLogReconcilerProvider = Provider<WorkLogReconciler>((ref) {
  final client = ActiveTrackerApiClient(ref.watch(dioProvider));
  return WorkLogReconciler(
    repo: ref.watch(workSessionRepositoryProvider),
    fetchActive: client.getActive,
  );
});
