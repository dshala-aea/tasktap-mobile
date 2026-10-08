// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../features/ticket/ticket_detail_api_client.dart' show TicketControlResponseDto;
import '../local/app_database.dart';
import 'checklist_reconciler.dart';
import 'checklist_rest_mapper.dart';
import 'sync_dto.dart';

/// Asks again for tickets whose checklist the server left out of a sync.
///
/// Two paths, one reconciler. [refetchOmitted] uses the batched `checklistTicketIds` parameter of
/// `GET /api/Sync/mobile` (plan 5b Task 0). It is bounded three ways — 50 ids per request, 4
/// requests per call, 5 attempts per ticket — and it disables itself for the session when the
/// backend ignores the parameter (the answer would then be the regular full delta, which is both
/// expensive and wrong to apply). [backfillTicket] reads one ticket through the existing
/// `GET /api/tickets/{id}/controls`, which needs no backend change.
class ChecklistRefetchService {
  ChecklistRefetchService({
    required this.db,
    required this.dio,
    this.maxAttempts = 5,
    this.batchSize = 50,
    this.maxBatches = 4,
  });

  final AppDatabase db;
  final Dio dio;
  final int maxAttempts;
  final int batchSize;
  final int maxBatches;

  bool _unsupported = false;
  bool _verified = false;

  /// True once the backend has been seen to ignore `checklistTicketIds` (this app session).
  bool get batchedUnsupported => _unsupported;

  Future<void> refetchOmitted() async {
    if (_unsupported) return;
    for (var i = 0; i < maxBatches; i++) {
      // The very first request of a session is a one-id probe: if the backend ignores the
      // parameter, the cost of finding out is one request, not fifty tickets' worth of delta.
      final pending = await _pending(_verified ? batchSize : 1);
      if (pending.isEmpty) return;

      final response = await dio.get<Map<String, dynamic>>(
        '/api/sync/mobile',
        queryParameters: {'checklistTicketIds': pending},
      );
      final dto = SyncResultDto.fromJson(response.data as Map<String, dynamic>);
      if (dto.tickets.isNotEmpty || dto.schedules.isNotEmpty || dto.customers.isNotEmpty) {
        _unsupported = true;
        debugPrint('checklist refetch: backend ignored checklistTicketIds; batched path disabled');
        return;
      }
      _verified = true;

      final omitted = dto.checklistOmittedTicketIds.toSet();
      await applyChecklistBatch(
        db,
        ChecklistBatch(
          // Requested and not omitted = fully described by this answer, even with zero rows
          // (empty checklist, or no longer actionable: nothing to show either way).
          authoritativeTicketIds: pending.toSet().difference(omitted),
          omittedTicketIds: omitted,
          controlGroups: dto.controlGroups,
          ticketControls: dto.ticketControls,
          ticketAssets: dto.ticketAssets,
          assets: dto.assets,
        ),
      );
      final stillOmitted = pending.where(omitted.contains).toList();
      await _countAttempt(stillOmitted);
      // The server's cap is full again: asking for the next batch right now would only be refused
      // the same way. Stop; the next sync tries again (bounded by [maxAttempts]).
      if (stillOmitted.isNotEmpty) return;
    }
  }

  /// Fetches [ticketId]'s checklist over REST and writes it through the same reconciler. Throws on
  /// any failure (the caller decides how to tell the technician); nothing is written then.
  Future<void> backfillTicket(String ticketId) async {
    final response = await dio.get<Map<String, dynamic>>('/api/tickets/$ticketId/controls');
    final r = TicketControlResponseDto.fromJson(response.data ?? const {});
    await applyChecklistBatch(db, checklistBatchFromRest(ticketId, r));
  }

  Future<List<String>> _pending(int limit) async {
    final rows =
        await (db.select(db.checklistOmittedTickets)
              ..where((o) => o.attempts.isSmallerThanValue(maxAttempts))
              ..orderBy([(o) => OrderingTerm.asc(o.attempts), (o) => OrderingTerm.asc(o.ticketId)])
              ..limit(limit))
            .get();
    return rows.map((o) => o.ticketId).toList();
  }

  Future<void> _countAttempt(Iterable<String> ids) async {
    final now = DateTime.now().toUtc();
    for (final id in ids) {
      final row = await (db.select(db.checklistOmittedTickets)..where((o) => o.ticketId.equals(id)))
          .getSingleOrNull();
      if (row == null) continue;
      await (db.update(db.checklistOmittedTickets)..where((o) => o.ticketId.equals(id))).write(
        ChecklistOmittedTicketsCompanion(attempts: Value(row.attempts + 1), lastAttemptAt: Value(now)),
      );
    }
  }
}
