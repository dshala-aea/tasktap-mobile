// dart format width=100
import 'package:drift/drift.dart';

import '../local/app_database.dart';

// ══════════════════════════════════════════════════════════════════════════════
// IWorkSessionRepository — seam for future backend sync (ClickUp D6).
// ══════════════════════════════════════════════════════════════════════════════

abstract interface class IWorkSessionRepository {
  /// Persist one clock event (ingresso / fine / pausa / ripresa).
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
  });

  /// Stream of today's events in chronological order.
  Stream<List<WorkSession>> watchTodaySessions();

  /// Delete all sessions for today (used in tests / reset).
  Future<void> clearToday();
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
  }) async {
    await _db.into(_db.workSessions).insert(
          WorkSessionsCompanion.insert(
            id: id,
            eventTime: eventTime,
            eventType: eventType,
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
            (s) =>
                s.eventTime.isBiggerOrEqualValue(start) &
                s.eventTime.isSmallerThanValue(end),
          )
          ..orderBy([(s) => OrderingTerm.asc(s.eventTime)]))
        .watch();
  }

  @override
  Future<void> clearToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));
    await (_db.delete(_db.workSessions)
          ..where(
            (s) =>
                s.eventTime.isBiggerOrEqualValue(start) &
                s.eventTime.isSmallerThanValue(end),
          ))
        .go();
  }
}
