// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereTimbraSyncService
//
// Assembles today's cantiere intervals from local events, sends them to the
// backend via CantiereWorklogApiClient's batch upsert, and marks the synced
// events locally. Mirrors timbra_sync_service.dart exactly.
//
// Design:
// - syncNow() is idempotent: the server upserts by clientId, so re-sending is
//   always safe even if a previous sync already succeeded.
// - Errors are silently swallowed: cantiere timbra stays fully functional
//   offline; isPendingSync remains true so the next sync attempt retries.
//
// Resurrection guard: an 'ingresso' CantiereWorkLogReconciler has flagged with
// `cantiereReconciledOrphanMarker` is excluded before assembling intervals — see
// cantiere_work_log_reconciler.dart and work_log_reconciler.dart (the personal-timbra
// equivalent) for why.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_service.dart' show appDatabaseProvider;
import 'cantiere_session_assembler.dart';
import 'cantiere_session_repository.dart';
import 'cantiere_worklog_api_client.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final cantiereSessionRepositoryProvider = Provider<ICantiereSessionRepository>((ref) {
  return CantiereSessionRepository(ref.watch(appDatabaseProvider));
});

final cantiereTimbraSyncServiceProvider = Provider<CantiereTimbraSyncService>((ref) {
  final repo = ref.watch(cantiereSessionRepositoryProvider);
  final client = ref.watch(cantiereWorklogApiClientProvider);
  return CantiereTimbraSyncService(repo: repo, apiClient: client);
});

// ── Service ───────────────────────────────────────────────────────────────────

class CantiereTimbraSyncService {
  CantiereTimbraSyncService({
    required ICantiereSessionRepository repo,
    required CantiereWorklogApiClient apiClient,
  }) : _repo = repo,
       _apiClient = apiClient;

  final ICantiereSessionRepository _repo;
  final CantiereWorklogApiClient _apiClient;

  /// Sync all of today's cantiere intervals to the server.
  ///
  /// - Assembles intervals from today's local events.
  /// - POSTs them (idempotent — safe to resend everything every time).
  /// - On success marks every event that contributed to a synced interval as isPendingSync =
  ///   false.
  /// - On any error: swallows silently so offline use is unaffected.
  Future<void> syncNow() async {
    try {
      final allEvents = await _repo.getTodayEvents();
      if (allEvents.isEmpty) return;

      // Resurrection guard — see class doc comment above.
      final events = allEvents.where((e) => e.notes != cantiereReconciledOrphanMarker).toList();
      if (events.isEmpty) return;

      final intervals = assembleCantiereIntervals(events);
      if (intervals.isEmpty) return;

      final dtos = intervals
          .map(
            (i) => CantiereMobileSessionDto(
              clientId: i.clientId,
              cantiereId: i.cantiereId,
              customerId: i.customerId,
              ticketId: i.ticketId,
              description: i.description,
              startTime: i.startTime,
              endTime: i.endTime,
              latitude: i.latitude,
              longitude: i.longitude,
            ),
          )
          .toList();

      await _apiClient.upsertSessions(dtos);

      // Mark every local event as synced (by event id, which is the clientId of the interval it
      // opened; the matching 'uscita' event shares the interval and is marked too).
      final syncedIds = events.map((e) => e.id).toList();
      await _repo.markSynced(syncedIds);
    } catch (_) {
      // Swallow: keeps isPendingSync = true for the next attempt.
    }
  }
}
