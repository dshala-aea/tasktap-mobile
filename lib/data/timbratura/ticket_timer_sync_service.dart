// ══════════════════════════════════════════════════════════════════════════════
// TicketTimerSyncService
//
// Pushes the ticket timer sessions this device still owes the server, through
// the idempotent batch upsert (POST /api/tickets/worklogs/mobile/sessions). The
// direct analogue of CantiereTimbraSyncService, minus the event assembly: a
// ticket timer is already a session.
//
// Re-sending is always safe — the server matches on (tenant, user, clientId) and
// only ever CLOSES a session it already holds — so the queue is not day-scoped
// and not pruned after success: a row leaves it when the server answers for it.
//
// Failures are classified, never swallowed blindly:
//   * transient (no response, timeout, 5xx, 401, 408, 429) → the rows stay
//     pending and the next attempt backs off in memory;
//   * any other 4xx is PERMANENT: the server answered and will answer the same
//     way to the same bytes. The rows get a human-readable `syncError` and are
//     held out of the automatic sweep until a manual sync releases them.
//     Nothing is discarded.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time.dart';
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/utils/error_message.dart';
import '../local/app_database.dart' show TicketTimer;
import '../sync/sync_service.dart' show appDatabaseProvider;
import 'ticket_timer_api_client.dart';
import 'ticket_timer_repository.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final ticketTimerRepositoryProvider = Provider<TicketTimerRepository>((ref) {
  return TicketTimerRepository(
    ref.watch(appDatabaseProvider),
    businessTime: ref.watch(businessTimeProvider),
  );
});

final ticketTimerSyncServiceProvider = Provider<TicketTimerSyncService>((ref) {
  return TicketTimerSyncService(
    repo: ref.watch(ticketTimerRepositoryProvider),
    apiClient: ref.watch(ticketTimerApiClientProvider),
    businessTime: ref.watch(businessTimeProvider),
  );
});

/// The Dio instance is watched here rather than inside the API client's own provider so tests can
/// override either one; the client itself stays a thin wrapper (see its file).

// ── Service ───────────────────────────────────────────────────────────────────

class TicketTimerSyncService {
  TicketTimerSyncService({
    required TicketTimerRepository repo,
    required TicketTimerApiClient apiClient,
    DateTime Function()? clock,
    BusinessTime? businessTime,
  }) : _repo = repo,
       _apiClient = apiClient,
       _clock = clock ?? DateTime.now,
       _businessTime = businessTime ?? BusinessTime.fallback(clock: clock);

  final TicketTimerRepository _repo;
  final TicketTimerApiClient _apiClient;
  final DateTime Function() _clock;
  final BusinessTime _businessTime;

  static const _maxBatchAttempts = 5;
  int _batchFailures = 0;
  DateTime? _batchRetryAt;

  /// Pushes every session this device still owes the server.
  ///
  /// [manual] (a user-initiated sync) clears the backoff and releases rows held by a permanent
  /// refusal, so they are tried again.
  Future<void> syncNow({bool manual = false}) async {
    if (manual) {
      _batchFailures = 0;
      _batchRetryAt = null;
      await _clearSyncErrors();
    }
    if (_batchHeld()) return;

    final rows = (await _repo.pending())
        .where((r) => r.syncError == null)
        .toList();
    if (rows.isEmpty) return;

    final dtos = rows.map(_toDto).toList();
    try {
      final results = await _apiClient.upsertSessions(dtos);
      _batchFailures = 0;
      _batchRetryAt = null;
      // The server echoes one result per session. A session missing from the echo stays pending:
      // guessing that it landed would risk logging the hours twice.
      for (final result in results) {
        await _repo.markSynced(result.clientId, result.ticketWorkLogId);
      }
    } catch (e) {
      if (_isPermanent(e)) {
        await _handleRefusedBatch(rows, e);
        return;
      }
      _batchFailures++;
      final backoff = Duration(seconds: 30 * (1 << (_batchFailures - 1).clamp(0, 6)));
      _batchRetryAt = _clock().add(backoff);
      debugPrint(
        'TicketTimerSyncService: transient failure (${_describe(e)}); '
        '${rows.length} pending session(s) held, attempt $_batchFailures/$_maxBatchAttempts',
      );
    }
  }

  /// A row as the batch endpoint takes it. The instants are preferred and the Rome-local frame is
  /// the fallback for a legacy server row that never carried them — the same precedence every
  /// worklog reader applies.
  TicketMobileSessionDto _toDto(TicketTimer row) {
    final workDate = row.workDate;
    final startSeconds = row.startSeconds;
    final start =
        row.startUtc ??
        (workDate != null && startSeconds != null
            ? _businessTime.instantOfLegacyLabel(
                workDate,
                Duration(seconds: startSeconds),
              )
            : null);
    final end =
        row.endUtc ??
        (workDate != null && row.endSeconds != null
            ? _businessTime.instantOfLegacyLabel(
                workDate,
                Duration(seconds: row.endSeconds!),
              )
            : null);
    if (start == null) {
      // Cannot happen for a row this device wrote (it always stamps startUtc). Fail loudly rather
      // than send a fabricated instant, which would book hours at the wrong time.
      throw StateError('Timer ${row.id} has no start instant');
    }
    return TicketMobileSessionDto(
      clientId: row.clientId ?? row.id,
      ticketId: row.ticketId,
      startTime: start,
      endTime: end,
      description: row.description,
    );
  }

  bool _batchHeld() {
    if (_batchFailures >= _maxBatchAttempts) return true;
    final at = _batchRetryAt;
    return at != null && _clock().isBefore(at);
  }

  /// The server answered and refused: this exact request will never be accepted, so retrying it
  /// unattended is pointless and hiding it is worse.
  Future<void> _handleRefusedBatch(List<TicketTimer> rows, Object error) async {
    final message = humanErrorMessage(error, azione: 'inviare le ore del ticket');
    for (final row in rows) {
      await _repo.markSyncError(row.id, message);
    }
    debugPrint(
      'TicketTimerSyncService: batch refused (${_describe(error)}); marked '
      '${rows.length} session(s) with a sync error',
    );
  }

  Future<void> _clearSyncErrors() async {
    for (final row in await _repo.pending()) {
      if (row.syncError != null) await _repo.markSyncError(row.id, null);
    }
  }

  static String _describe(Object e) =>
      e is DioException ? '${e.response?.statusCode ?? e.type.name}' : e.runtimeType.toString();

  static bool _isPermanent(Object e) =>
      e is DioException && e.response != null && !_isTransient(e);

  /// Mirrors CantiereTimbraSyncService._isTransient: anything with no response at all, a 5xx, or
  /// explicit back-pressure could plausibly succeed on retry. Nothing was decided server-side.
  static bool _isTransient(Object e) {
    if (e is! DioException) return false;
    final status = e.response?.statusCode;
    if (status == null) return e.type != DioExceptionType.badResponse;
    return status >= 500 || status == 401 || status == 408 || status == 429;
  }
}
