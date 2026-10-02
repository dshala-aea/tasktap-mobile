// dart format width=100
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
import '../../core/time/business_time.dart';
import '../../core/time/business_time_providers.dart';
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
    DateTime Function() clock = DateTime.now,
    BusinessTime? businessTime,
  }) : _repo = repo,
       _fetchActive = fetchActive,
       _businessTime = businessTime ?? BusinessTime(kDefaultBusinessZoneId, clock: clock);

  final IWorkSessionRepository _repo;
  final Future<List<ActiveTracker>> Function() _fetchActive;

  /// Source of the business-day boundary used by the backfill (same one the session repositories
  /// window on); its clock is injectable so the boundary is testable.
  final BusinessTime _businessTime;

  // Reentrancy guard: resume, reconnect, a push and the poll can all fire close together. Without
  // it two overlapping reads of local state could both see the same stale "open" shift and each
  // append their own correction. A request that arrives mid-run is NOT dropped: the in-flight
  // fetch may have been answered before the change it describes, so we run once more afterwards.
  bool _running = false;
  bool _rerun = false;

  /// Bound on stale-fetch re-runs within one call, so a permanently busy sync cannot spin us.
  static const _maxPasses = 3;

  /// Fetches the server's running trackers and reconciles local state against them.
  ///
  /// The local snapshot is read BEFORE the network call and compared again when the answer
  /// arrives: if local events changed meanwhile (a concurrent sync marked a shift synced, a tap
  /// landed) the answer was computed against a world that no longer exists — acting on it could
  /// close or re-open a shift that was just changed — so it is discarded and re-fetched.
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
      var passes = 0;
      do {
        _rerun = false;
        passes++;
        try {
          final before = _signature(await _repo.getTodaySessions());
          final trackers = await _fetchActive();
          final snapshot = ServerWorkLogSnapshot.fromActiveTrackers(trackers);
          final now = await _repo.getTodaySessions();
          if (_signature(now) != before) {
            _rerun = true; // stale answer: discard, fetch again
            continue;
          }
          await _reconcileWithSessions(snapshot, now);
        } catch (_) {
          // Swallow — see doc comment above.
        }
      } while (_rerun && passes < _maxPasses);
    } finally {
      _running = false;
    }
  }

  static String _signature(List<WorkSession> s) =>
      s.map((e) => '${e.id}|${e.isPendingSync}|${e.notes}').join(';');

  /// Reconciles local state against an already-known [server] snapshot.
  ///
  /// Exposed separately from [reconcile] so the correction logic is testable without a network
  /// round trip. Not reentrancy-guarded itself (only [reconcile] is).
  Future<void> reconcileWith(ServerWorkLogSnapshot server) async =>
      _reconcileWithSessions(server, await _repo.getTodaySessions());

  Future<void> _reconcileWithSessions(
    ServerWorkLogSnapshot server,
    List<WorkSession> sessions,
  ) async {
    // Local unsynced events win — see header. Our own marked corrections are excluded: they are
    // pending by construction but never pushed, and must not freeze reconciliation forever.
    final hasUnsynced = sessions.any((s) => s.isPendingSync && s.notes != reconciledOrphanMarker);
    if (hasUnsynced) return;

    final local = deriveShiftState(sessions);
    final last = sessions.isEmpty ? null : sessions.last.eventTime;

    if (server.isOnShift) {
      if (!local.isOnShift) {
        await _backfillMissingShift(server, sessions);
        return;
      }
      if (server.isOnPause && !local.isOnPause) {
        await _addMarked('pausa', server.breakStartTime ?? DateTime.now().toUtc(), last);
      } else if (!server.isOnPause && local.isOnPause) {
        // The instant the break ended elsewhere is not in the snapshot; "now" only affects what
        // this device displays (the event is never pushed).
        await _addMarked('ripresa', DateTime.now().toUtc(), last);
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
    await _addMarked('fine', DateTime.now().toUtc(), last);
  }

  /// Server has an open day this device has no local record of (started elsewhere, or a fresh
  /// install). Backfills 'ingresso' anchored on the server's own start — never `DateTime.now()`,
  /// which would understate worked time — and, when the server is on a break, the 'pausa' too so
  /// local state equals the server's. No-ops without a start time: fabricating one is worse than
  /// staying briefly stale.
  ///
  /// CONVERGENCE: every event written by this class must actually change the derived local state,
  /// otherwise the next reconcile sees the same disagreement and inserts again, forever. Events
  /// are ordered by time, so:
  /// - pausa / ripresa / fine are clamped to `max(desired, lastLocalEvent + 1s)` — strictly the
  ///   newest event, hence always effective (this also absorbs a phone clock that is behind or
  ///   ahead of the server, and a Ripresa the server refused and the app retired);
  /// - an ingresso is anchored at the business-day midnight when the server start is earlier (overnight
  ///   shift; else it falls outside `getTodaySessions`). If it would still sort before the last
  ///   local event it is skipped — that is a stale server view of a stop this device just made
  ///   (writing a ghost shift would be wrong) — EXCEPT after a Fine that the server refused on a
  ///   remote-origin shift, where the shift really is still open and is re-opened after the stop.
  Future<void> _backfillMissingShift(
    ServerWorkLogSnapshot server,
    List<WorkSession> sessions,
  ) async {
    var start = server.activeStartTime;
    if (start == null) return;

    final midnight = _businessTime.todayRangeUtc().$1;
    if (start.isBefore(midnight)) start = midnight;

    final last = sessions.isEmpty ? null : sessions.last.eventTime;
    final refusedFine = _lastFineOfRemoteShift(sessions);
    if (last != null && !start.isAfter(last)) {
      if (refusedFine == null) return; // stale/skewed view: would be inert, insert nothing
      start = last.add(_gap);
    }

    await _addMarked('ingresso', start, null);
    if (server.isOnPause) {
      final breakStart = server.breakStartTime;
      if (breakStart != null) {
        // Events are ordered by time; keep the pausa strictly after its ingresso even if the
        // server reports them equal.
        await _addMarked('pausa', breakStart.isAfter(start) ? breakStart : start.add(_epsilon), null);
      }
    }
  }

  static const _epsilon = Duration(milliseconds: 1);
  static const _gap = Duration(seconds: 1);

  /// Writes a marked, never-pushed event at `max(time, [last] + 1s)` so it is always the newest.
  Future<void> _addMarked(String type, DateTime time, DateTime? last) async {
    var t = time;
    if (last != null && !t.isAfter(last)) t = last.add(_gap);
    final id = _uuid.v4();
    await _repo.addEvent(id: id, eventTime: t, eventType: type);
    await _repo.markReconciledOrphan(id);
  }

  /// Time of the last `fine` if it closed a shift whose opener was backfilled (remote-origin), else
  /// null. Only that kind of stop can be "refused by the server while local already shows stopped".
  DateTime? _lastFineOfRemoteShift(List<WorkSession> sessions) {
    var remote = false;
    DateTime? last;
    for (final s in sessions) {
      switch (s.eventType) {
        case 'ingresso':
          remote = s.notes == reconciledOrphanMarker;
        case 'fine':
          last = remote ? s.eventTime : null;
          remote = false;
      }
    }
    return last;
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
    businessTime: ref.watch(businessTimeProvider),
  );
});
