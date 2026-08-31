// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// WorkLogReconciler
//
// Corrects local timbratura state against the server's authoritative view.
//
// The gap this closes: `timbraStateProvider` (features/timbra/timbra_providers.dart) derives
// isOnShift/isOnPause purely from the local Drift `work_sessions` table, which is only ever
// written by this device's own punch/pause actions. If the SAME account clocks out from another
// surface (the office web app), the server's worklog closes but this device's local table never
// learns about it — mobile keeps showing "on shift" indefinitely.
//
// This service is the correctness mechanism, not a latency optimisation: it is triggered on app
// resume, on reconnect, and by a 60s foreground poll (see work_log_reconcile_watcher.dart and
// HomeShell), mirroring the cadence the dashboard's activeTrackersProvider already polls at. A
// later phase may add a push channel on top; this phase intentionally does not.
//
// Flow: GET /api/worklog/today → ServerWorkLogSnapshot → WorkLogReconciler → corrects local
// Drift `work_sessions` rows → timbraStateProvider (and, transitively, the dashboard's
// visibleTrackersProvider, which reads timbraStateProvider as its own root) read the corrected
// state. No provider needs to know reconciliation happened; it just sees consistent data.
//
// Idempotent by construction: reconcileWith only acts when local disagrees with the server.
// Once local agrees, every subsequent call is a no-op — see work_log_reconciler_test.dart.
//
// Two directions, both guarded the same way:
// - Local thinks it's on shift, server says it isn't (clocked out elsewhere) → append a local
//   'fine' event.
// - Local has no record of a shift at all, server says one is active (started elsewhere, or a
//   fresh install) → backfill a local 'ingresso', anchored on the server's own interval start
//   time, never `DateTime.now()`.
//
// Resurrection guard: either correction writes a local event that TimbraSyncService would
// otherwise resend as if it were a fresh local-origin punch — re-opening/extending a worklog the
// server already closed (direction 1), or re-creating as "new" an interval the server already
// has (direction 2). Both corrections mark the event with `reconciledOrphanMarker` (an existing,
// previously-unused `notes` column — no schema migration needed); TimbraSyncService excludes
// marked events from its push. See timbra_sync_service.dart.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/timbra/timbra_providers.dart'
    show deriveShiftState, workSessionRepositoryProvider;
import '../local/app_database.dart' show WorkSession;
import 'work_session_repository.dart';
import 'worklog_api_client.dart';

const _uuid = Uuid();

// ── Server snapshot ───────────────────────────────────────────────────────────

/// The server's view of today's shift, reduced to exactly what reconciliation needs.
///
/// Deliberately narrower than [GiornataDto]: reconciliation only cares whether a shift/break is
/// open, not workedMinutes or payroll-lock reasons (those stay [GiornataDto]'s job, consumed
/// separately by `giornataProvider`/`resolveGuard`).
class ServerWorkLogSnapshot {
  const ServerWorkLogSnapshot({required this.isOnShift, required this.isOnPause, this.activeStartTime});

  final bool isOnShift;
  final bool isOnPause;

  /// The active worklog's real start time, from `GET /api/worklog/mobile/today`. Null whenever
  /// [isOnShift] is false, or when the server is on-shift but that richer per-worklog fetch
  /// failed/raced/returned nothing — reconciliation only backfills a missing local shift when
  /// this is present (see `_backfillMissingShift`), never guesses a start time.
  final DateTime? activeStartTime;

  /// `Working` and `OnBreak` both mean a shift is open; `OnBreak` additionally means the break
  /// inside it is open. `ClockedOut` (or anything unrecognised) means neither is.
  factory ServerWorkLogSnapshot.fromGiornata(GiornataDto giornata, {DateTime? activeStartTime}) {
    final isOnPause = giornata.status == 'OnBreak';
    final isOnShift = isOnPause || giornata.status == 'Working';
    return ServerWorkLogSnapshot(
      isOnShift: isOnShift,
      isOnPause: isOnPause,
      activeStartTime: isOnShift ? activeStartTime : null,
    );
  }
}

// ── Reconciler ────────────────────────────────────────────────────────────────

class WorkLogReconciler {
  WorkLogReconciler({required IWorkSessionRepository repo, required WorklogApiClient apiClient})
    : _repo = repo,
      _apiClient = apiClient;

  final IWorkSessionRepository _repo;
  final WorklogApiClient _apiClient;

  // Reentrancy guard: app-resume, reconnect and the 60s poll can all fire close together (e.g.
  // reconnecting right as the app resumes). Without this, two overlapping reads of local state
  // could both see the same stale "open" shift and each append their own correction.
  bool _running = false;

  /// Fetches the server's current worklog status and reconciles local state against it.
  ///
  /// Network/parse errors are swallowed, matching every other sync path in this app (see
  /// TimbraSyncService, giornataProvider): offline is the normal condition of a phone in the
  /// field, not a failure to report. Without a server answer there is nothing safe to correct.
  Future<void> reconcile() async {
    if (_running) return;
    _running = true;
    try {
      final giornata = await _apiClient.getGiornata();
      await _reconcileWith(await _buildSnapshot(giornata));
    } catch (_) {
      // Swallow — see doc comment above.
    } finally {
      _running = false;
    }
  }

  /// Enriches the status summary with the active worklog's real start time when one is open —
  /// needed only for a possible backfill (direction 2 above), so the extra fetch is skipped
  /// entirely when the server says no shift is open. A failure here still yields a usable
  /// snapshot (just without a start time, so backfill will no-op) rather than aborting the whole
  /// reconciliation — the close-direction correction doesn't need this fetch to succeed.
  Future<ServerWorkLogSnapshot> _buildSnapshot(GiornataDto giornata) async {
    final base = ServerWorkLogSnapshot.fromGiornata(giornata);
    if (!base.isOnShift) return base;
    try {
      final today = await _apiClient.getToday();
      final active = today.where((w) => w.isActive);
      if (active.isEmpty) return base;
      return ServerWorkLogSnapshot.fromGiornata(giornata, activeStartTime: active.first.startTime);
    } catch (_) {
      return base;
    }
  }

  /// Reconciles local state against an already-known [server] snapshot.
  ///
  /// Exposed separately from [reconcile] so the correction logic is testable without a network
  /// round trip. Not reentrancy-guarded itself (only [reconcile] is): tests call this directly
  /// and rely on it running exactly once per invocation.
  Future<void> reconcileWith(ServerWorkLogSnapshot server) => _reconcileWith(server);

  Future<void> _reconcileWith(ServerWorkLogSnapshot server) async {
    final sessions = await _repo.getTodaySessions();
    final local = deriveShiftState(sessions);

    if (!local.isOnShift && server.isOnShift) {
      await _backfillMissingShift(server);
      return;
    }

    // Local still thinks a shift is open that the server has already closed (clocked out from
    // another surface, same account).
    if (!local.isOnShift || server.isOnShift) return;

    final opener = _findOpenOpener(sessions);
    if (opener != null) {
      await _repo.markReconciledOrphan(opener.id);
    }

    await _repo.addEvent(id: _uuid.v4(), eventTime: DateTime.now().toUtc(), eventType: 'fine');
  }

  /// Server has an active shift this device has no local record of at all (started elsewhere, or
  /// a fresh install/reinstall). Backfills a local 'ingresso' anchored on the server's own
  /// interval start time — never `DateTime.now()`, which would understate worked time — and
  /// immediately marks it with [reconciledOrphanMarker] so TimbraSyncService (which resends every
  /// unmarked opener idempotently) never re-uploads it as a "new" local-origin interval. This is
  /// what makes the backfill safe: it only ever changes what this device *displays*, never what
  /// it sends. No-ops when the server didn't supply a start time — fabricating one is worse than
  /// staying briefly stale.
  Future<void> _backfillMissingShift(ServerWorkLogSnapshot server) async {
    final startTime = server.activeStartTime;
    if (startTime == null) return;

    final id = _uuid.v4();
    await _repo.addEvent(id: id, eventTime: startTime, eventType: 'ingresso');
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
  return WorkLogReconciler(
    repo: ref.watch(workSessionRepositoryProvider),
    apiClient: ref.watch(worklogApiClientProvider),
  );
});
