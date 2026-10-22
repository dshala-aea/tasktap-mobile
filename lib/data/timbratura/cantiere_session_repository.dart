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

import '../../core/time/business_time.dart';
import '../local/app_database.dart';
import 'cantiere_session_assembler.dart';

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

  /// The most recent event of the whole log, on ANY business day, or null when it is empty.
  ///
  /// This is what "am I currently on site" needs: pairing is sequential, so a local session is
  /// open exactly when the last row is an 'ingresso'. Scoping that question to today drops a
  /// check-in recorded yesterday evening and never closed — the screen would then offer "Ingresso"
  /// again, and the second opener would orphan the first interval. Reconciler corrections are
  /// skipped: they are not what the technician punched.
  Stream<CantierePunche?> watchLatestPunch();

  /// Every event still waiting to reach the server, on ANY business day, in chronological order.
  ///
  /// Same day-agnostic queue as `IWorkSessionRepository.getPendingSessions`: a site check-in
  /// recorded offline must be sent the next day too. Reconciler corrections are included (pending
  /// by construction); the sync filters them out via [cantiereReconciledOrphanMarker].
  Future<List<CantierePunche>> getPendingEvents();

  /// This device's CLOSED cantiere intervals for [cantiereId], on any business day (P2-6).
  ///
  /// The local answer to "what has this phone clocked on this site?", used for two things that
  /// used to need the network: the Ore step's cantiere-tier hours suggestion while offline, and
  /// the punch ids a cantiere-originated rapportino claims as consumed
  /// (**[getClosedIntervalClientIds]**). Deliberately computed from ALL local events, not just the
  /// pending ones: which rows already reached the server depends on upload order, which is none of
  /// either caller's business, and a claim on an already-consumed punch is a server-side no-op.
  /// Open intervals are excluded — they have no hours to have counted yet.
  Future<List<CantiereWorkInterval>> getClosedIntervalsFor(String cantiereId);

  /// Client ids of [getClosedIntervalsFor] — exactly the opening 'ingresso' event's id, which is
  /// also `CantiereWorkLog.ClientId` server-side, so the value is usable whether the punch was
  /// already uploaded or is still queued.
  Future<List<String>> getClosedIntervalClientIds(String cantiereId);

  /// How many cantiere events still have to reach the server, on any day — the cantiere half of
  /// the app's unsent-work counter. Excludes this device's own reconciler corrections (never
  /// pushed). A row holding a permanent sync error still counts: it is work that never reached the
  /// server.
  Future<int> getPendingCount();

  /// Mark the given event ids as synced (isPendingSync = false).
  Future<void> markSynced(List<String> ids);

  /// Records a permanent sync failure against the given event id: the message is shown to the
  /// technician and the row is held out of the automatic retry sweep (it stays `isPendingSync`,
  /// so it still counts as unsent and the reconciler still leaves the phone's own view in charge).
  /// Pass null to release the hold (a manual sync does this before retrying).
  Future<void> markSyncError(String id, String? message);

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
  CantiereSessionRepository(this._db, {BusinessTime? businessTime})
    : _businessTime = businessTime ?? BusinessTime.fallback();

  final AppDatabase _db;
  final BusinessTime _businessTime;

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
    await _db
        .into(_db.cantierePunches)
        .insert(
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

  /// The one definition of "today": the tenant business day as a half-open UTC window.
  (DateTime, DateTime) _todayRange() => _businessTime.todayRangeUtc();

  /// Every unsynced row, with no day window at all — the upload queue.
  SimpleSelectStatement<$CantierePunchesTable, CantierePunche> _pendingQuery() =>
      _db.select(_db.cantierePunches)
        ..where((t) => t.isPendingSync.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]);

  /// Pending rows that still need the server, i.e. excluding our own reconciler corrections.
  Expression<bool> get _countablePending =>
      _db.cantierePunches.isPendingSync.equals(true) &
      (_db.cantierePunches.notes.isNull() |
          _db.cantierePunches.notes.equals(cantiereReconciledOrphanMarker).not());

  @override
  Stream<List<CantierePunche>> watchTodayEvents() {
    final (start, end) = _todayRange();
    return (_db.select(_db.cantierePunches)
          ..where(
            (t) => t.eventTime.isBiggerOrEqualValue(start) & t.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .watch();
  }

  @override
  Stream<CantierePunche?> watchLatestPunch() =>
      (_db.select(_db.cantierePunches)
            ..where(
              (t) =>
                  t.notes.isNull() | t.notes.equals(cantiereReconciledOrphanMarker).not(),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.eventTime),
              // Two punches can share an instant (a rapid ingresso→uscita correction recorded in
              // the same millisecond); the id tiebreak keeps "the last one" deterministic rather
              // than whatever order the storage engine happens to return.
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(1))
          .watchSingleOrNull();

  @override
  Future<List<CantierePunche>> getTodayEvents() {
    final (start, end) = _todayRange();
    return (_db.select(_db.cantierePunches)
          ..where(
            (t) => t.eventTime.isBiggerOrEqualValue(start) & t.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  @override
  Future<List<CantierePunche>> getPendingEvents() => _pendingQuery().get();

  @override
  Future<List<CantiereWorkInterval>> getClosedIntervalsFor(String cantiereId) async {
    // Every local event: 'uscita' rows carry no cantiereId of their own, so the pairing (and the
    // filtering by cantiere) has to happen in the assembler, which is also the one definition of
    // how events fold into intervals.
    final events =
        await (_db.select(_db.cantierePunches)
              ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
            .get();
    final intervals = assembleCantiereIntervals(
      events,
      businessDateOf: _businessTime.businessDateOf,
    );
    // Re-stamped to UTC on the way out: Drift hands a `DateTimeColumn` back as a LOCAL-kind
    // `DateTime` for the same instant, while [CantiereWorkInterval] documents its instants as UTC
    // and every consumer serialises them with `toUtc()`. Same moment either way — this just keeps
    // the type's own contract true, so a future caller that prints `toIso8601String()` without the
    // conversion cannot emit a local wall-clock time the server would read in its own zone.
    return [
      for (final i in intervals)
        if (i.cantiereId == cantiereId && i.endTime != null)
          CantiereWorkInterval(
            clientId: i.clientId,
            cantiereId: i.cantiereId,
            customerId: i.customerId,
            ticketId: i.ticketId,
            description: i.description,
            startTime: i.startTime.toUtc(),
            endTime: i.endTime?.toUtc(),
            latitude: i.latitude,
            longitude: i.longitude,
          ),
    ];
  }

  @override
  Future<List<String>> getClosedIntervalClientIds(String cantiereId) async =>
      [for (final i in await getClosedIntervalsFor(cantiereId)) i.clientId];

  @override
  Future<int> getPendingCount() async {
    final count = _db.cantierePunches.id.count();
    final query = _db.selectOnly(_db.cantierePunches)
      ..addColumns([count])
      ..where(_countablePending);
    return (await query.getSingle()).read(count) ?? 0;
  }

  @override
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.cantierePunches)..where((t) => t.id.isIn(ids))).write(
      const CantierePunchesCompanion(isPendingSync: Value(false), syncError: Value(null)),
    );
  }

  @override
  Future<void> markSyncError(String id, String? message) async {
    await (_db.update(
      _db.cantierePunches,
    )..where((t) => t.id.equals(id))).write(CantierePunchesCompanion(syncError: Value(message)));
  }

  @override
  Future<void> markReconciledOrphan(String id) async {
    await (_db.update(_db.cantierePunches)..where((t) => t.id.equals(id))).write(
      const CantierePunchesCompanion(notes: Value(cantiereReconciledOrphanMarker)),
    );
  }

  @override
  Future<void> clearToday() async {
    final (start, end) = _todayRange();
    await (_db.delete(_db.cantierePunches)..where(
          (t) => t.eventTime.isBiggerOrEqualValue(start) & t.eventTime.isSmallerThanValue(end),
        ))
        .go();
  }
}
