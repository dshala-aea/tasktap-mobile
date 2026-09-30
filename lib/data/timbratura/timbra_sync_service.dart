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
// Shifts started on another device (orphan-marked opener) are NOT sent through the batch: their
// Fine / Pausa / Ripresa taps are executed against POST /worklog/end, break/start, break/end.
// See remote_shift.dart for the model, the online-only/TTL policy and the backend follow-up.
//
// Resurrection guard:
// - Sessions whose opener (ingresso/ripresa) WorkLogReconciler has flagged with
//   `reconciledOrphanMarker` are excluded before assembling intervals. Those openers represent a
//   shift the server has already told this device (via GET /worklog/today) is closed elsewhere
//   — a stale local push of that same interval, still "active" (endTime null) from this device's
//   point of view, would re-open or extend a worklog the server considers finished. See
//   work_log_reconciler.dart for the write side of this marker.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/timbra/timbra_providers.dart' show workSessionRepositoryProvider;
import '../api/dio_client.dart';
import '../local/app_database.dart' show WorkSession;
import '../worklogs/active_tracker_api_client.dart';
import 'remote_shift.dart';
import 'timbra_notice.dart';
import 'timbra_session_assembler.dart';
import 'work_log_refresh_coordinator.dart';
import 'work_session_repository.dart';
import 'worklog_api_client.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final Provider<TimbraSyncService> timbraSyncServiceProvider = Provider<TimbraSyncService>((ref) {
  final repo = ref.watch(workSessionRepositoryProvider);
  final dio = ref.watch(dioProvider);
  final apiClient = WorklogApiClient(dio);
  var seq = 0;
  return TimbraSyncService(
    repo: repo,
    apiClient: apiClient,
    fetchActive: ActiveTrackerApiClient(dio).getActive,
    // After a REST command lands, is retired or a batch is refused, re-read the server so
    // local == server. sync:false: we are the sync, do not loop back into it.
    onRemoteCommandsApplied: () =>
        ref.read(workLogRefreshCoordinatorProvider).refreshNow(sync: false),
    onNotice: (m) => ref.read(timbraNoticeProvider.notifier).state = TimbraNotice(m, ++seq),
  );
});

// ── Service ───────────────────────────────────────────────────────────────────

class TimbraSyncService {
  TimbraSyncService({
    required IWorkSessionRepository repo,
    required WorklogApiClient apiClient,
    Future<List<ActiveTracker>> Function()? fetchActive,
    void Function()? onRemoteCommandsApplied,
    void Function(String message)? onNotice,
    DateTime Function()? clock,
  }) : _repo = repo,
       _apiClient = apiClient,
       _fetchActive = fetchActive,
       _onRemoteCommandsApplied = onRemoteCommandsApplied,
       _onNotice = onNotice,
       _clock = clock ?? DateTime.now;

  final IWorkSessionRepository _repo;
  final WorklogApiClient _apiClient;
  final Future<List<ActiveTracker>> Function()? _fetchActive;
  final void Function()? _onRemoteCommandsApplied;
  final void Function(String message)? _onNotice;
  final DateTime Function() _clock;

  bool _running = false;
  bool _rerun = false;

  /// True once this instance has sent any remote command. Only the very first send of an instance,
  /// on a tap younger than [_freshTap], may skip the server-state check: anything else could be a
  /// retry of a send whose response was lost (possibly by a previous process — nothing about
  /// "already attempted" survives a restart, so it is never trusted).
  bool _sentAny = false;
  static const _freshTap = Duration(seconds: 3);

  // ── Batch refusal hold (non-conflict 4xx) ───────────────────────────────────
  // A refused batch is atomic and may carry the technician's only record of the day, so it is never
  // discarded: the events stay pending. To avoid hammering the server we back off in memory and
  // give up after [_maxBatchAttempts] until the next app start or a manual sync.
  static const _maxBatchAttempts = 5;
  int _batchFailures = 0;
  DateTime? _batchRetryAt;
  final Set<String> _noticeKinds = {};

  /// Sync all of today's work intervals to the server.
  ///
  /// - Taps on a shift that started on ANOTHER device are executed first, as REST commands (see
  ///   [_runRemoteCommands]).
  /// - The remaining, locally-originated events are assembled into intervals and POSTed
  ///   (idempotent — safe to resend everything every time).
  /// - On success marks every event that contributed as isPendingSync = false.
  /// - A transient failure is swallowed: offline use is unaffected and the events stay pending.
  ///   A PERMANENT batch refusal (4xx, e.g. 409 active_session_exists because another device
  ///   already has an open row) retires the dead events instead of retrying forever, because
  ///   pending events also freeze the reconciler (local unsynced events always win).
  ///
  /// Reentrancy: overlapping calls (punch + reconnect + poll) must not execute the same REST
  /// command twice, so a call arriving mid-run schedules one more pass instead of running beside.
  ///
  /// [manual] (a user-initiated sync) clears the refusal hold so a held batch is tried again.
  Future<void> syncNow({bool manual = false}) async {
    if (manual) {
      _batchFailures = 0;
      _batchRetryAt = null;
    }
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
      // Nothing of ours is waiting (our own marked corrections are pending by construction but are
      // never sent): every trigger — poll, resume, push — calls this, so do not re-POST a day of
      // already-synced events for nothing.
      if (!allSessions.any((s) => s.isPendingSync && s.notes != reconciledOrphanMarker)) return;

      final remote = analyseRemoteShifts(allSessions);
      await _runRemoteCommands(remote);

      // Resurrection guard — see class doc comment above. Remote-shift events never go through
      // the batch: it matches by clientId and would create a duplicate row for that shift.
      final sessions = allSessions
          .where((s) => s.notes != reconciledOrphanMarker && !remote.ids.contains(s.id))
          .toList();
      if (sessions.isEmpty) return;
      if (_batchHeld()) return;

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

      try {
        await _apiClient.upsertSessions(dtos);
        _batchFailures = 0;
        _batchRetryAt = null;
      } catch (e) {
        if (!_isTransient(e) && e is DioException && e.response != null) {
          await _handleRefusedBatch(sessions, e);
        }
        return; // transient: keeps isPendingSync = true for the next attempt.
      }

      // Mark every local event as synced (by event id, which is the clientId
      // of the interval it opened; non-opener events share the interval).
      final syncedIds = sessions.map((s) => s.id).toList();
      await _repo.markSynced(syncedIds);
    } catch (_) {
      // Swallow: keeps isPendingSync = true for the next attempt.
    }
  }

  bool _batchHeld() {
    if (_batchFailures >= _maxBatchAttempts) return true;
    final at = _batchRetryAt;
    return at != null && _clock().isBefore(at);
  }

  /// The batch endpoint is whole-batch atomic (one refused item fails everything), so what to do
  /// depends on WHY, read from the ProblemDetails `code`:
  ///
  /// - 409 `active_session_exists`: another device already holds the open row. The punch can never
  ///   be accepted as a new shift, so the pending events are retired — kept for support under
  ///   [syncFailedMarker], hidden, never uploaded — the user is told (with how many events were
  ///   kept) and the reconciler adopts the server's shift.
  /// - EVERYTHING ELSE (403, 400, 404, 413, 422, `payroll_period_locked`, other 409s): the server
  ///   refused, but the data is the technician's record. Nothing is retired or discarded; events
  ///   stay pending. We back off (30s, 60s, 120s, ...), stop after 5 attempts per app session, and
  ///   show ONE accurate message per failure kind. Held events count as unsynced, so the
  ///   reconciler leaves the phone's own view in charge and visible — the safe payroll direction —
  ///   until the office resolves it or a later attempt succeeds.
  Future<void> _handleRefusedBatch(List<WorkSession> sessions, DioException e) async {
    final data = e.response?.data;
    final code = data is Map ? data['code'] as String? : null;
    final detail = data is Map ? data['detail'] as String? : null;

    if (e.response?.statusCode == 409 && code == 'active_session_exists') {
      final dead = sessions.where((s) => s.isPendingSync).toList();
      if (dead.isEmpty) return;
      for (final s in dead) {
        await _repo.markSyncFailed(s.id);
      }
      debugPrint(
        'TimbraSyncService: batch refused (409 active_session_exists); retained '
        '${dead.length} event(s) as $syncFailedMarker: '
        '${dead.map((s) => '${s.eventType}@${s.eventTime.toIso8601String()}#${s.id}').join(', ')}',
      );
      final n = dead.length;
      _onNotice?.call(
        '$batchConflictMessage ($n ${n == 1 ? 'evento conservato' : 'eventi conservati'})',
      );
      _onRemoteCommandsApplied?.call();
      return;
    }

    _batchFailures++;
    final backoff = Duration(seconds: 30 * (1 << (_batchFailures - 1).clamp(0, 6)));
    _batchRetryAt = _clock().add(backoff);

    final payroll = code == 'payroll_period_locked';
    final kind = payroll ? 'payroll' : 'server';
    if (_noticeKinds.add(kind)) {
      _onNotice?.call(
        payroll
            ? (detail != null && detail.trim().isNotEmpty ? detail : payrollLockedMessage)
            : serverErrorMessage,
      );
    }
    debugPrint(
      'TimbraSyncService: batch refused (${e.response?.statusCode} $code); held '
      '${sessions.where((s) => s.isPendingSync).length} pending event(s), attempt $_batchFailures/'
      '$_maxBatchAttempts',
    );
  }

  // ── Shifts started on another device ────────────────────────────────────────

  /// Executes this device's own taps (unmarked, pending fine/pausa/ripresa) on a remote-origin
  /// shift against the REST endpoints, in tap order. The pending local event IS the queued
  /// command (persisted in Drift, id = idempotency key). Endpoint choice follows the service:
  /// Fine → `end` (ends the open row; in a break that closes the day), Pausa → `break/start`,
  /// Ripresa → `break/end`.
  ///
  /// The endpoints stamp the SERVER clock, so a tap is only worth sending while it is fresh — see
  /// remote_shift.dart for why (payroll) and the backend follow-up. Rules, in order:
  /// - A Pausa immediately followed by a Ripresa, both still pending, are never sent (a
  ///   zero-length paid break); both are retired and the reconciler converges.
  /// - A tap older than [remoteCommandTtl] is dropped with a visible message.
  /// - A command already attempted once (response possibly lost), older than
  ///   3s old, or not the first send of this instance is re-validated against
  ///   `GET /worklog/active` before sending — see [_verdict]. If that read fails it stays queued.
  /// - Transient failure (no response, 5xx, 401, 408, 429): stop, keep queued (later taps must not
  ///   overtake it). Any other 4xx: the server already disagrees, retire and reconcile — no loop.
  Future<void> _runRemoteCommands(RemoteShiftAnalysis remote) async {
    final commands = remote.commands;
    if (commands.isEmpty) return;

    var settled = false;
    var sentOrChecked = false;
    final now = _clock();

    for (var i = 0; i < commands.length; i++) {
      final c = commands[i];
      final e = c.event;

      // Pausa+Ripresa queued together: cancel out, never send.
      if (e.eventType == 'pausa' &&
          i + 1 < commands.length &&
          commands[i + 1].event.eventType == 'ripresa') {
        await _repo.markSynced([e.id, commands[i + 1].event.id]);
        settled = true;
        i++;
        continue;
      }

      final age = now.difference(e.eventTime);
      if (age > remoteCommandTtl) {
        await _repo.markSynced([e.id]);
        _onNotice?.call(remoteCommandDroppedMessage);
        settled = true;
        continue;
      }

      final mustCheck = _sentAny || sentOrChecked || age >= _freshTap;
      final fetch = _fetchActive;
      if (mustCheck && fetch != null) {
        final List<ActiveTracker> active;
        try {
          active = await fetch();
        } catch (_) {
          break; // cannot verify: never send blind, keep queued (TTL bounds it)
        }
        sentOrChecked = true;
        if (_verdict(c, active) == _Verdict.done) {
          await _repo.markSynced([e.id]);
          settled = true;
          continue;
        }
      }

      _sentAny = true;
      try {
        switch (e.eventType) {
          case 'fine':
            await _apiClient.endWork();
          case 'pausa':
            await _apiClient.startBreak();
          case 'ripresa':
            await _apiClient.endBreak();
        }
      } catch (err) {
        if (_isTransient(err)) break;
        // Permanent refusal: retire the command, converge through the reconciler.
      }
      sentOrChecked = true;
      await _repo.markSynced([e.id]);
      settled = true;
    }
    if (settled) _onRemoteCommandsApplied?.call();
  }

  /// What the server currently holds versus what [c] assumes. `send` only when the very shift the
  /// tap was made on is open in the state the tap expects; anything else means the tap is already
  /// reflected (or moot) and must NOT be sent — a newer shift started elsewhere is never touched.
  _Verdict _verdict(RemoteCommand c, List<ActiveTracker> active) {
    final att = active.where((t) => t.kind == ActiveTrackerKind.attendance).firstOrNull;
    if (att == null) return _Verdict.done; // the shift is gone: Fine already effective

    // Same shift? The opener may have been clamped forward by the reconciler (overnight, refused
    // stop), so the server start may be EARLIER than the opener; a LATER start is another shift.
    final serverStart = att.shiftStartedAtUtc ?? att.startedAtUtc;
    if (serverStart.isAfter(c.openerTime.add(const Duration(seconds: 60)))) return _Verdict.done;

    final onBreak = att.state == ActiveTrackerState.onBreak;
    switch (c.event.eventType) {
      case 'fine':
        return _Verdict.send; // ends the open row in either state
      case 'pausa':
        return onBreak ? _Verdict.done : _Verdict.send;
      case 'ripresa':
        return onBreak ? _Verdict.send : _Verdict.done;
    }
    return _Verdict.done;
  }

  static bool _isTransient(Object e) {
    if (e is! DioException) return false;
    final status = e.response?.statusCode;
    if (status == null) return e.type != DioExceptionType.badResponse;
    return status >= 500 || status == 401 || status == 408 || status == 429;
  }
}

enum _Verdict { send, done }
