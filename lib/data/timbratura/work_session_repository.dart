// dart format width=100
import 'package:drift/drift.dart';

import '../local/app_database.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Reconciliation marker
//
// Written into WorkSession.notes (an existing, previously-unused column — no schema
// migration needed) by WorkLogReconciler when it discovers a local opener event
// (ingresso/ripresa) whose interval the server has already closed elsewhere (e.g. the same
// account clocking out on the web). TimbraSyncService excludes marked openers from what it
// resends, so a stale local "still active" push can never re-open or extend a worklog the
// server already closed. See work_log_reconciler.dart and timbra_sync_service.dart.
// ══════════════════════════════════════════════════════════════════════════════

const String reconciledOrphanMarker = 'reconciled_orphan';

// ══════════════════════════════════════════════════════════════════════════════
// IWorkSessionRepository — seam for future backend sync (ClickUp D6).
// ══════════════════════════════════════════════════════════════════════════════

abstract interface class IWorkSessionRepository {
  /// Persist one clock event (ingresso / fine / pausa / ripresa).
  ///
  /// [latitude]/[longitude] are the GPS position captured at punch time — meaningful only for
  /// `ingresso`/`ripresa` (interval-opening events); left null for `fine`/`pausa`, for every event
  /// when GPS is unavailable/disabled, and for every caller that predates this parameter.
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
  });

  /// Stream of today's events in chronological order.
  Stream<List<WorkSession>> watchTodaySessions();

  /// Snapshot of today's events in chronological order (one-shot).
  Future<List<WorkSession>> getTodaySessions();

  /// Mark the given event ids as synced (isPendingSync = false).
  Future<void> markSynced(List<String> ids);

  /// Delete all sessions for today (used in tests / reset).
  Future<void> clearToday();

  /// Marks event [id] (an ingresso/ripresa opener) as a stale interval the server has already
  /// closed elsewhere. See [reconciledOrphanMarker].
  Future<void> markReconciledOrphan(String id);
}

// ══════════════════════════════════════════════════════════════════════════════
// WorkSessionRepository — Drift implementation (local-only until D6).
// ══════════════════════════════════════════════════════════════════════════════

class WorkSessionRepository implements IWorkSessionRepository {
  WorkSessionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
  }) async {
    await _db.into(_db.workSessions).insert(
      WorkSessionsCompanion.insert(
        id: id,
        eventTime: eventTime,
        eventType: eventType,
        latitude: Value(latitude),
        longitude: Value(longitude),
      ),
    );
  }

  @override
  Stream<List<WorkSession>> watchTodaySessions() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));
    return (_db.select(_db.workSessions)
          ..where(
            (s) => s.eventTime.isBiggerOrEqualValue(start) & s.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(s) => OrderingTerm.asc(s.eventTime)]))
        .watch();
  }

  @override
  Future<List<WorkSession>> getTodaySessions() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));
    return (_db.select(_db.workSessions)
          ..where(
            (s) => s.eventTime.isBiggerOrEqualValue(start) & s.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(s) => OrderingTerm.asc(s.eventTime)]))
        .get();
  }

  @override
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.workSessions)..where((s) => s.id.isIn(ids))).write(
      const WorkSessionsCompanion(isPendingSync: Value(false)),
    );
  }

  @override
  Future<void> clearToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));
    await (_db.delete(_db.workSessions)..where(
          (s) => s.eventTime.isBiggerOrEqualValue(start) & s.eventTime.isSmallerThanValue(end),
        ))
        .go();
  }

  @override
  Future<void> markReconciledOrphan(String id) async {
    await (_db.update(_db.workSessions)..where((s) => s.id.equals(id))).write(
      const WorkSessionsCompanion(notes: Value(reconciledOrphanMarker)),
    );
  }
}
