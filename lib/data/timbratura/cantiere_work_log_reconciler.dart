// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereWorkLogReconciler
//
// Corrects local cantiere-timbra state against the server's authoritative view. Mirrors
// work_log_reconciler.dart's approach exactly, for the cantiere (worksite) session instead of
// personal attendance.
//
// The gap this closes: the active-session UI derives "am I on site" from local `cantiere_punches`
// events (see cantiereActiveSessionProvider in cantiere_timbra_screen.dart), written by this
// device's own check-in/check-out. If the same account ends the site visit from another surface
// (the office web, or the online endCantiere path succeeding on a retry after this device already
// queued its own local close), local state can be left believing a session is still open. This
// service compares GET /api/cantiereworklog (filtered to active) against local state and, when
// local thinks a site visit is open but the server does not, appends a local 'uscita' event so the
// derived state converges — mirroring WorkLogReconciler's 'fine' correction.
//
// Triggered the same way as WorkLogReconciler: app resume, reconnect, and the 60s foreground poll
// (see home_shell.dart).
//
// LOCAL UNSYNCED EVENTS ALWAYS WIN. When any local event is still pending (and is not one of our
// own marked corrections) this does nothing for that round: the server cannot know about a punch
// that has not been pushed, so "correcting" then would orphan the technician's own clock-in — and
// the sync filters orphan-marked openers out, so it would never be sent. See [_reconcileWith].
//
// Resurrection guard: the opener being closed is marked with `cantiereReconciledOrphanMarker` so
// CantiereTimbraSyncService never resends it — see cantiere_session_repository.dart.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../local/app_database.dart' show CantierePunche;
import 'cantiere_session_repository.dart';
import 'cantiere_timbra_sync_service.dart' show cantiereSessionRepositoryProvider;
import 'cantiere_worklog_api_client.dart';

const _uuid = Uuid();

class CantiereWorkLogReconciler {
  CantiereWorkLogReconciler({
    required ICantiereSessionRepository repo,
    required CantiereWorklogApiClient apiClient,
  }) : _repo = repo,
       _apiClient = apiClient;

  final ICantiereSessionRepository _repo;
  final CantiereWorklogApiClient _apiClient;

  // Reentrancy guard — mirrors WorkLogReconciler's, same reason (resume/reconnect/poll can
  // overlap).
  bool _running = false;

  /// Fetches the server's currently-active cantiere session and reconciles local state against
  /// it. Network/parse errors are swallowed — offline is normal, not a failure to report.
  Future<void> reconcile() async {
    if (_running) return;
    _running = true;
    try {
      final active = await _apiClient.getActive();
      await _reconcileWith(serverHasActiveSession: active.isNotEmpty);
    } catch (_) {
      // Swallow — see doc comment above.
    } finally {
      _running = false;
    }
  }

  /// Reconciles local state against an already-known server answer. Exposed separately so the
  /// correction logic is testable without a network round trip.
  Future<void> reconcileWith({required bool serverHasActiveSession}) =>
      _reconcileWith(serverHasActiveSession: serverHasActiveSession);

  Future<void> _reconcileWith({required bool serverHasActiveSession}) async {
    if (serverHasActiveSession) return;

    final events = await _repo.getTodayEvents();

    // LOCAL UNSYNCED EVENTS ALWAYS WIN — the same guard, for the same reason, as
    // WorkLogReconciler (see its class doc). A phone in a basement records a site check-in
    // offline and pushes it later; until that push lands the server legitimately has no active
    // session, and "correcting" local state then would orphan-mark the technician's own clock-in
    // and append an 'uscita' over it. The sync then filters the orphan out, so the check-in is
    // never sent at all: the punch is lost. The next reconcile pass, after the push, converges.
    //
    // Our own corrections are excluded: they are pending by construction (markReconciledOrphan
    // leaves isPendingSync true) but are never pushed, and must not freeze reconciliation forever.
    final hasUnsynced = events.any(
      (e) => e.isPendingSync && e.notes != cantiereReconciledOrphanMarker,
    );
    if (hasUnsynced) return;

    final opener = _findOpenOpener(events);
    // Local believes no session is open (no unmatched 'ingresso') — nothing to correct. Mirrors
    // WorkLogReconciler: only correct the one direction this bug produces (local open, server
    // closed); never manufacture a local 'ingresso' the device never recorded.
    if (opener == null) return;

    await _repo.markReconciledOrphan(opener.id);
    final id = _uuid.v4();
    await _repo.addEvent(id: id, eventTime: DateTime.now().toUtc(), eventType: 'uscita');
    // The correction is display-only, exactly like every event WorkLogReconciler writes: marked so
    // the sync never pushes it (it has no opener in the batch anyway, so it would sit pending
    // forever) and so it cannot freeze this reconciler's own unsynced-events guard.
    await _repo.markReconciledOrphan(id);
  }

  /// The most recent 'ingresso' that has no closing 'uscita' after it.
  CantierePunche? _findOpenOpener(List<CantierePunche> events) {
    CantierePunche? candidate;
    for (final e in events) {
      switch (e.eventType) {
        case 'ingresso':
          candidate = e;
        case 'uscita':
          candidate = null;
      }
    }
    return candidate;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final cantiereWorkLogReconcilerProvider = Provider<CantiereWorkLogReconciler>((ref) {
  return CantiereWorkLogReconciler(
    repo: ref.watch(cantiereSessionRepositoryProvider),
    apiClient: ref.watch(cantiereWorklogApiClientProvider),
  );
});
