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
// Idempotent by construction: reconcileWith only acts when local disagrees with the server in
// the one direction this bug produces (local thinks it's on shift, server says it isn't).
// Once local agrees, every subsequent call is a no-op — see work_log_reconciler_test.dart.
//
// Resurrection guard: correcting local state means appending a 'fine' event, which is exactly
// the kind of event TimbraSyncService would otherwise resend. To stop that from re-opening or
// extending a worklog the server already closed, the *opener* this correction is closing is
// marked with `reconciledOrphanMarker` (an existing, previously-unused `notes` column — no
// schema migration needed) and TimbraSyncService excludes marked openers from its push. See
// timbra_sync_service.dart.
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
  const ServerWorkLogSnapshot({required this.isOnShift, required this.isOnPause});

  final bool isOnShift;
  final bool isOnPause;

  /// `Working` and `OnBreak` both mean a shift is open; `OnBreak` additionally means the break
  /// inside it is open. `ClockedOut` (or anything unrecognised) means neither is.
  factory ServerWorkLogSnapshot.fromGiornata(GiornataDto giornata) {
    final isOnPause = giornata.status == 'OnBreak';
    final isOnShift = isOnPause || giornata.status == 'Working';
    return ServerWorkLogSnapshot(isOnShift: isOnShift, isOnPause: isOnPause);
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
      await _reconcileWith(ServerWorkLogSnapshot.fromGiornata(giornata));
    } catch (_) {
      // Swallow — see doc comment above.
    } finally {
      _running = false;
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

    // The only direction this bug produces: local still thinks a shift is open that the server
    // has already closed (clocked out from another surface, same account). The reverse — server
    // says open but local doesn't know about it — is intentionally left alone: manufacturing a
    // local 'ingresso' the device never recorded risks inventing a second, overlapping shift,
    // which is a worse failure mode than a dashboard that is briefly behind.
    if (!local.isOnShift || server.isOnShift) return;

    final opener = _findOpenOpener(sessions);
    if (opener != null) {
      await _repo.markReconciledOrphan(opener.id);
    }

    await _repo.addEvent(id: _uuid.v4(), eventTime: DateTime.now().toUtc(), eventType: 'fine');
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
