// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereSessionRepository
//
// Local-first event log for cantiere (worksite) timbratura, mirroring
// work_session_repository.dart's shape exactly. One row per raw event
// ('ingresso'/'uscita') in the Drift `cantiere_punches` table — the table has
// existed since schema 7 but nothing ever read or wrote it; this is that seam.
//
// Writing here first (before any network call) is what makes clock-in/out
// survive being offline: the technician's tap is durable the instant this
// returns, and CantiereTimbraSyncService pushes it to the server whenever a
// connection exists. See cantiere_session_assembler.dart for how raw events
// fold into intervals, and cantiere_timbra_sync_service.dart for the push.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';

import '../local/app_database.dart';

/// Marker written into `CantierePunche.notes` (mirrors `reconciledOrphanMarker` in
/// work_session_repository.dart) by [CantiereWorkLogReconciler] when a local 'ingresso' turns
/// out to be a site visit the server has already closed elsewhere. `CantiereTimbraSyncService`
/// excludes marked openers from what it resends.
const String cantiereReconciledOrphanMarker = 'reconciled_orphan';

// ══════════════════════════════════════════════════════════════════════════════
// ICantiereSessionRepository
// ══════════════════════════════════════════════════════════════════════════════

abstract interface class ICantiereSessionRepository {
  /// Persist one cantiere clock event ('ingresso' / 'uscita').
  ///
  /// [cantiereId]/[customerId]/[ticketId]/[description] are the site context — meaningful only
  /// on 'ingresso' (interval-opening); left null on 'uscita', which only needs a timestamp (see
  /// cantiere_session_assembler.dart, which inherits the opener's context for the whole
  /// interval).
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    String? cantiereId,
    String? customerId,
    String? ticketId,
    String? description,
    double? latitude,
    double? longitude,
  });

  /// Stream of today's events in chronological order.
  Stream<List<CantierePunche>> watchTodayEvents();

  /// Snapshot of today's events in chronological order (one-shot).
  Future<List<CantierePunche>> getTodayEvents();

  /// Mark the given event ids as synced (isPendingSync = false).
  Future<void> markSynced(List<String> ids);

  /// Records a sync failure against the given event id (surfaced as a pending-sync indicator,
  /// mirrors the personal-timbra `hasPendingSyncProvider` pattern).
  Future<void> markSyncError(String id, String message);

  /// Marks event [id] (an 'ingresso' opener) as a stale interval the server has already closed
  /// elsewhere. See [cantiereReconciledOrphanMarker].
  Future<void> markReconciledOrphan(String id);

  /// Delete all events for today (tests / reset).
  Future<void> clearToday();
}

// ══════════════════════════════════════════════════════════════════════════════
// CantiereSessionRepository — Drift implementation.
// ══════════════════════════════════════════════════════════════════════════════

class CantiereSessionRepository implements ICantiereSessionRepository {
  CantiereSessionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    String? cantiereId,
    String? customerId,
    String? ticketId,
    String? description,
    double? latitude,
    double? longitude,
  }) async {
    await _db.into(_db.cantierePunches).insert(
      CantierePunchesCompanion.insert(
        id: id,
        eventTime: eventTime,
        eventType: eventType,
        cantiereId: Value(cantiereId),
        customerId: Value(customerId),
        ticketId: Value(ticketId),
        description: Value(description),
        latitude: Value(latitude),
        longitude: Value(longitude),
      ),
    );
  }

  (DateTime, DateTime) _todayBounds() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    return (start, start.add(const Duration(days: 1)));
  }

  @override
  Stream<List<CantierePunche>> watchTodayEvents() {
    final (start, end) = _todayBounds();
    return (_db.select(_db.cantierePunches)
          ..where(
            (t) => t.eventTime.isBiggerOrEqualValue(start) & t.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .watch();
  }

  @override
  Future<List<CantierePunche>> getTodayEvents() {
    final (start, end) = _todayBounds();
    return (_db.select(_db.cantierePunches)
          ..where(
            (t) => t.eventTime.isBiggerOrEqualValue(start) & t.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  @override
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.cantierePunches)..where((t) => t.id.isIn(ids))).write(
      const CantierePunchesCompanion(isPendingSync: Value(false), syncError: Value(null)),
    );
  }

  @override
  Future<void> markSyncError(String id, String message) async {
    await (_db.update(_db.cantierePunches)..where((t) => t.id.equals(id))).write(
      CantierePunchesCompanion(syncError: Value(message)),
    );
  }

  @override
  Future<void> markReconciledOrphan(String id) async {
    await (_db.update(_db.cantierePunches)..where((t) => t.id.equals(id))).write(
      const CantierePunchesCompanion(notes: Value(cantiereReconciledOrphanMarker)),
    );
  }

  @override
  Future<void> clearToday() async {
    final (start, end) = _todayBounds();
    await (_db.delete(_db.cantierePunches)
          ..where(
            (t) => t.eventTime.isBiggerOrEqualValue(start) & t.eventTime.isSmallerThanValue(end),
          ))
        .go();
  }
}
