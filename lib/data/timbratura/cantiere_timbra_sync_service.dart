// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereTimbraSyncService
//
// Assembles the cantiere intervals this device still owes the server from its local
// events, sends them to the backend via CantiereWorklogApiClient's batch upsert, and
// marks the synced events locally. Mirrors timbra_sync_service.dart.
//
// Design:
// - syncNow() is idempotent: the server upserts by clientId, so re-sending is
//   always safe even if a previous sync already succeeded.
// - The queue is NOT day-scoped: today's events plus EVERY pending event from any
//   earlier day, one POST per business day (see _byBusinessDay). A site check-in
//   recorded offline before midnight used to be dropped on the floor.
// - Failures are classified, never swallowed blindly:
//     * transient (no response, timeout, 5xx, 401, 408, 429) → the events stay
//       pending and the next attempt backs off in memory (30s, 60s, 120s…, capped
//       at _maxBatchAttempts per app session, or immediately after a manual sync).
//     * any other 4xx is PERMANENT: the server has answered and will answer the
//       same way to the same bytes. The day's events stay `isPendingSync` (so they
//       still count as unsent, still show the pending indicator, and the reconciler
//       still leaves the phone's own view in charge) and get a human-readable
//       `syncError` via markSyncError, which holds them out of the automatic sweep.
//       Nothing is discarded and nothing is orphan-marked.
//
// Resurrection guard: an 'ingresso' CantiereWorkLogReconciler has flagged with
// `cantiereReconciledOrphanMarker` is excluded before assembling intervals — see
// cantiere_work_log_reconciler.dart and work_log_reconciler.dart (the personal-timbra
// equivalent) for why.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time.dart';
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/utils/error_message.dart';
import '../local/app_database.dart' show CantierePunche;
import '../sync/sync_service.dart' show appDatabaseProvider;
import 'cantiere_session_assembler.dart';
import 'cantiere_session_repository.dart';
import 'cantiere_worklog_api_client.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final cantiereSessionRepositoryProvider = Provider<ICantiereSessionRepository>((ref) {
  return CantiereSessionRepository(
    ref.watch(appDatabaseProvider),
    businessTime: ref.watch(businessTimeProvider),
  );
});

final cantiereTimbraSyncServiceProvider = Provider<CantiereTimbraSyncService>((ref) {
  final repo = ref.watch(cantiereSessionRepositoryProvider);
  final client = ref.watch(cantiereWorklogApiClientProvider);
  return CantiereTimbraSyncService(
    repo: repo,
    apiClient: client,
    businessTime: ref.watch(businessTimeProvider),
  );
});

// ── Service ───────────────────────────────────────────────────────────────────

class CantiereTimbraSyncService {
  CantiereTimbraSyncService({
    required ICantiereSessionRepository repo,
    required CantiereWorklogApiClient apiClient,
    DateTime Function()? clock,
    BusinessTime? businessTime,
  }) : _repo = repo,
       _apiClient = apiClient,
       _clock = clock ?? DateTime.now,
       _businessTime = businessTime ?? BusinessTime.fallback(clock: clock);

  final ICantiereSessionRepository _repo;
  final CantiereWorklogApiClient _apiClient;
  final DateTime Function() _clock;

  /// The tenant's business calendar: decides which events belong to the same day when the batch
  /// carries a backlog from more than one (see [_byBusinessDay]).
  final BusinessTime _businessTime;

  // ── Backoff ─────────────────────────────────────────────────────────────────
  // A refused batch may carry the technician's only record of a site visit, so it is never
  // discarded. To avoid hammering the server we back off in memory and stop after
  // [_maxBatchAttempts] until the next app start or a manual sync.
  static const _maxBatchAttempts = 5;
  int _batchFailures = 0;
  DateTime? _batchRetryAt;

  /// Pushes every cantiere event this device still owes the server.
  ///
  /// [manual] (a user-initiated sync) clears the backoff and releases the rows held back by a
  /// previous permanent refusal, so they are tried again.
  Future<void> syncNow({bool manual = false}) async {
    if (manual) {
      _batchFailures = 0;
      _batchRetryAt = null;
    }
    try {
      if (manual) await _clearSyncErrors();
      final allEvents = await _openUploadQueue();
      // Resurrection guard — see class doc comment above.
      final events = allEvents
          .where((e) => e.notes != cantiereReconciledOrphanMarker)
          .toList();
      if (events.isEmpty) return;

      for (final day in _byBusinessDay(events)) {
        if (_batchHeld()) return;
        // A day holding a permanent refusal waits for a human (a manual sync re-arms it): sending
        // the rest of that day without the refused events would post half a visit.
        if (day.any((e) => e.syncError != null)) continue;
        if (!await _pushDay(day)) return;
      }
    } catch (_) {
      // Swallow: keeps isPendingSync = true for the next attempt.
    }
  }

  /// Everything this device has to show the server about, in chronological order: today's events
  /// (the display day) plus every still-pending event from ANY day (the upload backlog).
  Future<List<CantierePunche>> _openUploadQueue() async {
    final byId = <String, CantierePunche>{};
    for (final e in await _repo.getTodayEvents()) {
      byId[e.id] = e;
    }
    for (final e in await _repo.getPendingEvents()) {
      byId[e.id] = e;
    }
    return byId.values.toList()..sort((a, b) => a.eventTime.compareTo(b.eventTime));
  }

  /// [events] (chronological) grouped by the business day the interval they belong to STARTED on,
  /// days ascending. Same rule as TimbraSyncService: a close belongs to the day of the interval it
  /// closes, so an overnight site visit is sent closed, in the day it began — not split so that its
  /// 'uscita' sits alone in the next day's group (where the assembler ignores it and it stays
  /// pending forever).
  List<List<CantierePunche>> _byBusinessDay(List<CantierePunche> events) {
    final days = <DateTime, List<CantierePunche>>{};
    DateTime? openStart;
    for (final e in events) {
      final DateTime day;
      if (e.eventType == 'ingresso') {
        day = _businessTime.businessDateOf(e.eventTime);
        openStart = e.eventTime;
      } else if (e.eventType == 'uscita') {
        day = _businessTime.businessDateOf(openStart ?? e.eventTime);
        openStart = null;
      } else {
        day = _businessTime.businessDateOf(e.eventTime);
      }
      (days[day] ??= <CantierePunche>[]).add(e);
    }
    return days.values.toList();
  }

  bool _batchHeld() {
    if (_batchFailures >= _maxBatchAttempts) return true;
    final at = _batchRetryAt;
    return at != null && _clock().isBefore(at);
  }

  /// Assembles and POSTs one business day's events. Returns false when the run must stop: a day
  /// that could not be sent says nothing good about the next one, and both the backoff and the
  /// refusal hold live for the whole run.
  Future<bool> _pushDay(List<CantierePunche> day) async {
    // Days already fully synced are common (today's events are always in the read).
    if (!day.any((e) => e.isPendingSync)) return true;

    final intervals = assembleCantiereIntervals(day, businessDateOf: _businessTime.businessDateOf);
    if (intervals.isEmpty) return true;

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
            departureLatitude: i.departureLatitude,
            departureLongitude: i.departureLongitude,
            safetyNotes: i.safetyNotes,
            workOrderNumber: i.workOrderNumber,
            equipmentUsed: i.equipmentUsed,
            teamSize: i.teamSize,
            weatherConditions: i.weatherConditions,
          ),
        )
        .toList();

    try {
      await _apiClient.upsertSessions(dtos);
      _batchFailures = 0;
      _batchRetryAt = null;
    } catch (e) {
      if (_isPermanent(e)) {
        await _handleRefusedBatch(day, e);
        return false;
      }
      _batchFailures++;
      final backoff = Duration(seconds: 30 * (1 << (_batchFailures - 1).clamp(0, 6)));
      _batchRetryAt = _clock().add(backoff);
      debugPrint(
        'CantiereTimbraSyncService: transient failure (${_describe(e)}); '
        '${day.where((p) => p.isPendingSync).length} pending event(s) held, '
        'attempt $_batchFailures/$_maxBatchAttempts',
      );
      return false;
    }

    // Mark every local event of this day as synced (by event id, which is the clientId of the
    // interval it opened; the matching 'uscita' event shares the interval and is marked too).
    await _repo.markSynced(day.where((e) => e.isPendingSync).map((e) => e.id).toList());
    return true;
  }

  /// The server answered and refused: this exact request will never be accepted, so retrying it
  /// unattended is pointless and hiding it is worse. Every still-pending event of the day gets the
  /// sentence the technician can act on, through [ICantiereSessionRepository.markSyncError], which
  /// also takes it out of the automatic sweep. Nothing is deleted, nothing is orphan-marked.
  Future<void> _handleRefusedBatch(List<CantierePunche> day, Object error) async {
    final message = humanErrorMessage(error, azione: 'inviare la timbratura cantiere');
    final held = day.where((e) => e.isPendingSync).toList();
    for (final e in held) {
      await _repo.markSyncError(e.id, message);
    }
    debugPrint(
      'CantiereTimbraSyncService: batch refused (${_describe(error)}); marked '
      '${held.length} event(s) with a sync error (${held.map((e) => e.id).join(', ')})',
    );
  }

  /// Releases rows held by a permanent refusal so a user-initiated sync tries them again. The
  /// events stay pending either way — only the hold (the message) is dropped.
  Future<void> _clearSyncErrors() async {
    for (final e in await _repo.getPendingEvents()) {
      if (e.syncError != null) await _repo.markSyncError(e.id, null);
    }
  }

  static String _describe(Object e) =>
      e is DioException ? '${e.response?.statusCode ?? e.type.name}' : e.runtimeType.toString();

  /// Whether the server ANSWERED and refused in a way retrying cannot fix: any non-transient
  /// response. Anything with no response at all (radio down, timeout, a programming error) is not
  /// permanent — nothing was decided server-side, and marking the technician's punch refused on the
  /// strength of it would be a lie. Mirrors timbra_sync_service.dart's `_handleRefusedBatch` gate.
  static bool _isPermanent(Object e) =>
      e is DioException && e.response != null && !_isTransient(e);

  /// Whether retrying the same request unattended could plausibly succeed: no response at all
  /// (radio/timeout), a server fault (5xx), or explicit back-pressure (408/429). 401 counts too:
  /// the auth interceptor's silent refresh can leave the original 401 surfacing when the refresh
  /// failed for a non-definitive reason, and the retry cap bounds it. Mirrors
  /// timbra_sync_service.dart / submission_queue.dart.
  static bool _isTransient(Object e) {
    if (e is! DioException) return false;
    final status = e.response?.statusCode;
    if (status == null) return e.type != DioExceptionType.badResponse;
    return status >= 500 || status == 401 || status == 408 || status == 429;
  }
}
