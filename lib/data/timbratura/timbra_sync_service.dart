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

  /// Commands this instance has already sent at least once (response possibly lost). A retry of
  /// one of these is re-validated against the server first. Not persisted: after a restart the
  /// 20s age rule covers the same case.
  final Set<String> _attempted = {};

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
      } catch (e) {
        if (!_isTransient(e) && e is DioException && e.response != null) {
          await _retireRefusedBatch(sessions, e);
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

  /// The server will never accept these pending events (a 4xx that is not back-pressure/auth).
  /// Marks them as reconciler-owned (so a still-open one behaves as a shift started elsewhere and
  /// later taps go through the REST path) and synced (so they stop blocking reconciliation), tells
  /// the user, and asks for a reconcile so local state converges to the server's.
  Future<void> _retireRefusedBatch(List<WorkSession> sessions, DioException e) async {
    final dead = sessions.where((s) => s.isPendingSync).toList();
    if (dead.isEmpty) return;
    for (final s in dead) {
      await _repo.markReconciledOrphan(s.id);
    }
    await _repo.markSynced(dead.map((s) => s.id).toList());
    _onNotice?.call(batchConflictMessage);
    _onRemoteCommandsApplied?.call();
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
  ///   [remoteCommandStateCheckAfter], or queued behind another one is re-validated against
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

      final mustCheck =
          sentOrChecked || _attempted.contains(e.id) || age > remoteCommandStateCheckAfter;
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

      _attempted.add(e.id);
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
