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

import 'package:dio/dio.dart';

import '../api/dio_client.dart';
import '../local/app_database.dart' show WorkSession;
import 'work_log_refresh_coordinator.dart';
import 'timbra_session_assembler.dart';
import 'work_session_repository.dart';
import 'worklog_api_client.dart';
import '../../features/timbra/timbra_providers.dart' show workSessionRepositoryProvider;

// ── Provider ──────────────────────────────────────────────────────────────────

final timbraSyncServiceProvider = Provider<TimbraSyncService>((ref) {
  final repo = ref.watch(workSessionRepositoryProvider);
  final dio = ref.watch(dioProvider);
  final apiClient = WorklogApiClient(dio);
  return TimbraSyncService(
    repo: repo,
    apiClient: apiClient,
    // After a REST command lands (or is refused) re-read the server so local == server.
    onRemoteCommandsApplied: () => ref.read(workLogRefreshCoordinatorProvider).refreshNow(),
  );
});

// ── Service ───────────────────────────────────────────────────────────────────

class TimbraSyncService {
  TimbraSyncService({
    required IWorkSessionRepository repo,
    required WorklogApiClient apiClient,
    void Function()? onRemoteCommandsApplied,
  }) : _repo = repo,
       _apiClient = apiClient,
       _onRemoteCommandsApplied = onRemoteCommandsApplied;

  final IWorkSessionRepository _repo;
  final WorklogApiClient _apiClient;
  final void Function()? _onRemoteCommandsApplied;

  bool _running = false;
  bool _rerun = false;

  /// Sync all of today's work intervals to the server.
  ///
  /// - Taps on a shift that started on ANOTHER device are executed first, as REST commands (see
  ///   [_remoteCommands]).
  /// - The remaining, locally-originated events are assembled into intervals and POSTed
  ///   (idempotent — safe to resend everything every time).
  /// - On success marks every event that contributed as isPendingSync = false.
  /// - On any error: swallows silently so offline use is unaffected.
  ///
  /// Reentrancy: overlapping calls (punch + reconnect + poll) must not execute the same REST
  /// command twice, so a call arriving mid-run schedules one more pass instead of running beside.
  Future<void> syncNow() async {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        await _syncOnce();
      } while (_rerun);
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce() async {
    try {
      final allSessions = await _repo.getTodaySessions();
      if (allSessions.isEmpty) return;

      final remoteIds = _remoteSegmentIds(allSessions);
      await _runRemoteCommands(allSessions, remoteIds);

      // Resurrection guard — see class doc comment above. Remote-shift events never go through
      // the batch: it matches by clientId and would create a duplicate row for that shift.
      final sessions = allSessions
          .where((s) => s.notes != reconciledOrphanMarker && !remoteIds.contains(s.id))
          .toList();
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
              gpsAccuracyMeters: i.gpsAccuracyMeters,
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

  // ── Shifts started on another device ────────────────────────────────────────

  /// Ids of every event belonging to a shift whose opener the reconciler backfilled (orphan-marked
  /// `ingresso`): that shift lives on the server under a row this device never created. A local
  /// `ingresso` (unmarked) starts a device-owned shift; a `fine` ends whichever kind is open.
  Set<String> _remoteSegmentIds(List<WorkSession> sessions) {
    final ids = <String>{};
    var remote = false;
    for (final s in sessions) {
      switch (s.eventType) {
        case 'ingresso':
          remote = s.notes == reconciledOrphanMarker;
          if (remote) ids.add(s.id);
        case 'pausa':
        case 'ripresa':
          if (remote) ids.add(s.id);
        case 'fine':
          if (remote) ids.add(s.id);
          remote = false;
      }
    }
    return ids;
  }

  /// Executes this device's own taps (unmarked, pending fine/pausa/ripresa) on a remote-origin
  /// shift against the REST endpoints, in tap order. The pending local event IS the queued
  /// command (persisted in Drift, id = idempotency key), so an offline tap survives restarts.
  ///
  /// Endpoint choice follows the service: Fine → `end` (ends the open row, in a break that closes
  /// the day), Pausa → `break/start`, Ripresa → `break/end`. The server stamps its own clock, so an
  /// offline tap takes effect at the moment it is delivered.
  ///
  /// Failure handling (same split as SubmissionQueue): transient (no response, 5xx, 401, 408, 429)
  /// stops the run and keeps the command queued — later taps must not overtake it. Any other 4xx
  /// (404 nothing open, 400 wrong state, 409 conflict, 422) means the server already disagrees with
  /// what the tap assumed (e.g. the shift ended elsewhere): retrying can never help, so the command
  /// is retired and the reconciler pulls local state to the server's — never a loop.
  ///
  /// A crash between a successful call and markSynced replays the tap once; the replay is refused
  /// (404/400) and lands in the permanent branch above, so it is harmless.
  Future<void> _runRemoteCommands(List<WorkSession> all, Set<String> remoteIds) async {
    final commands = all
        .where(
          (s) =>
              remoteIds.contains(s.id) &&
              s.isPendingSync &&
              s.notes != reconciledOrphanMarker &&
              s.eventType != 'ingresso',
        )
        .toList();

    var settled = false;
    for (final c in commands) {
      try {
        switch (c.eventType) {
          case 'fine':
            await _apiClient.endWork();
          case 'pausa':
            await _apiClient.startBreak();
          case 'ripresa':
            await _apiClient.endBreak();
        }
      } catch (e) {
        if (_isTransient(e)) break;
        // Permanent refusal: retire the command, converge through the reconciler.
      }
      await _repo.markSynced([c.id]);
      settled = true;
    }
    if (settled) _onRemoteCommandsApplied?.call();
  }

  static bool _isTransient(Object e) {
    if (e is! DioException) return false;
    final status = e.response?.statusCode;
    if (status == null) return e.type != DioExceptionType.badResponse;
    return status >= 500 || status == 401 || status == 408 || status == 429;
  }
}
