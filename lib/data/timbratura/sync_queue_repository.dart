// dart format width=100
import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'work_session_repository.dart';

/// What a technician may do with the personal-timbra offline queue: see it, and delete an item.
///
/// A separate class, not new members of [IWorkSessionRepository]: that interface is implemented by
/// many fakes, and this is a support surface that nothing in the sync path depends on.
///
/// The queue is the rows not yet acknowledged by the server — `isPendingSync` (waiting) and
/// [syncFailedMarker] (the server refused them; kept on the phone for support). The reconciler's own
/// corrections ([reconciledOrphanMarker]) are pending by construction and never sent, so they are
/// not queue items.
class SyncQueueRepository {
  SyncQueueRepository(this._db);

  final AppDatabase _db;

  /// Queue items, oldest first.
  Stream<List<WorkSession>> watchQueue() =>
      (_db.select(_db.workSessions)
            ..where(
              (s) =>
                  (s.isPendingSync.equals(true) &
                      (s.notes.isNull() | s.notes.equals(reconciledOrphanMarker).not())) |
                  s.notes.equals(syncFailedMarker),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.eventTime)]))
          .watch();

  /// Whether [item] can be deleted on its own, given the whole [queue] (oldest first).
  ///
  /// The rule: a refused item (already retired, hidden from every state) is always deletable; a
  /// PENDING item only when no later PENDING item exists. Later events are interpreted relative to
  /// earlier ones (a pausa closes the ingresso before it, a ripresa reopens after the pausa), so
  /// removing the middle of a chain would leave a sequence the phone then sends as something the
  /// technician never did. Deleting from the newest end backwards is always consistent.
  static bool canDelete(WorkSession item, List<WorkSession> queue) {
    if (item.notes == syncFailedMarker) return true;
    return !queue.any(
      (o) =>
          o.id != item.id &&
          o.isPendingSync &&
          o.notes != syncFailedMarker &&
          o.eventTime.isAfter(item.eventTime),
    );
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.workSessions)..where((s) => s.id.equals(id))).go();
}
