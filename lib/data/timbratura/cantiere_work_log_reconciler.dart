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
    final opener = _findOpenOpener(events);
    // Local believes no session is open (no unmatched 'ingresso') — nothing to correct. Mirrors
    // WorkLogReconciler: only correct the one direction this bug produces (local open, server
    // closed); never manufacture a local 'ingresso' the device never recorded.
    if (opener == null) return;

    await _repo.markReconciledOrphan(opener.id);
    await _repo.addEvent(id: _uuid.v4(), eventTime: DateTime.now().toUtc(), eventType: 'uscita');
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
