// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// TimbraSyncService
//
// Assembles today's work intervals from local events, sends them to the
// backend via WorklogApiClient, and marks the synced events locally.
//
// Design:
// - syncNow() is idempotent: the server upserts by clientId, so re-sending
//   is always safe even if a previous sync already succeeded.
// - Errors are silently swallowed: timbra stays fully functional offline;
//   isPendingSync remains true so the next sync attempt will retry.
//
// Resurrection guard:
// - Sessions whose opener (ingresso/ripresa) WorkLogReconciler has flagged with
//   `reconciledOrphanMarker` are excluded before assembling intervals. Those openers represent a
//   shift the server has already told this device (via GET /worklog/today) is closed elsewhere
//   — a stale local push of that same interval, still "active" (endTime null) from this device's
//   point of view, would re-open or extend a worklog the server considers finished. See
//   work_log_reconciler.dart for the write side of this marker.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import 'timbra_session_assembler.dart';
import 'work_session_repository.dart';
import 'worklog_api_client.dart';
import '../../features/timbra/timbra_providers.dart' show workSessionRepositoryProvider;

// ── Provider ──────────────────────────────────────────────────────────────────

final timbraSyncServiceProvider = Provider<TimbraSyncService>((ref) {
  final repo = ref.watch(workSessionRepositoryProvider);
  final dio = ref.watch(dioProvider);
  final apiClient = WorklogApiClient(dio);
  return TimbraSyncService(repo: repo, apiClient: apiClient);
});

// ── Service ───────────────────────────────────────────────────────────────────

class TimbraSyncService {
  TimbraSyncService({required IWorkSessionRepository repo, required WorklogApiClient apiClient})
    : _repo = repo,
      _apiClient = apiClient;

  final IWorkSessionRepository _repo;
  final WorklogApiClient _apiClient;

  /// Sync all of today's work intervals to the server.
  ///
  /// - Assembles intervals from today's local events.
  /// - POSTs them (idempotent — safe to resend everything every time).
  /// - On success marks every event that contributed to a synced interval as
  ///   isPendingSync = false.
  /// - On any error: swallows silently so offline use is unaffected.
  Future<void> syncNow() async {
    try {
      final allSessions = await _repo.getTodaySessions();
      if (allSessions.isEmpty) return;

      // Resurrection guard — see class doc comment above.
      final sessions = allSessions.where((s) => s.notes != reconciledOrphanMarker).toList();
      if (sessions.isEmpty) return;

      final intervals = assembleIntervals(sessions);
      if (intervals.isEmpty) return;

      final dtos = intervals
          .map(
            (i) => MobileSessionDto(
              clientId: i.clientId,
              startTime: i.startTime,
              endTime: i.endTime,
              // Captured at punch time when available (PunchNotifier) — see WorkInterval's own
              // doc comment for why only the opener's position is carried. Still null whenever no
              // position was captured (GPS off, permission never granted, or a pre-existing
              // event from before this capture existed); simple timbra keeps working either way.
              latitude: i.latitude,
              longitude: i.longitude,
            ),
          )
          .toList();

      await _apiClient.upsertSessions(dtos);

      // Mark every local event as synced (by event id, which is the clientId
      // of the interval it opened; non-opener events share the interval).
      final syncedIds = sessions.map((s) => s.id).toList();
      await _repo.markSynced(syncedIds);
    } catch (_) {
      // Swallow: keeps isPendingSync = true for the next attempt.
    }
  }
}
