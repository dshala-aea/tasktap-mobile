// ══════════════════════════════════════════════════════════════════════════════
// TicketTimerRepository
//
// Local-first store for ticket timer sessions, over the Drift `ticket_timers`
// table. The ticket timer bar writes here first when the device is offline (and
// when a write fails for lack of signal), so the technician's tap is durable the
// instant it returns; `TicketTimerSyncService` pushes what is still pending.
//
// Two kinds of row live in the same table:
//   * a server row, delivered by sync — `isPendingSync` false, `clientId` set only
//     when the session was born on a phone;
//   * a row this device started and has not managed to send — `isPendingSync`
//     true, its own uuid as both `id` and `clientId` until the server answers.
//
// The Rome-local frame (`workDate` + time-of-day) is what every ticket worklog
// reader displays; the UTC instants are what the batch endpoint accepts. A row
// born here carries both from the start, so it renders and uploads without a
// round trip.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../../core/time/business_time.dart';
import '../local/app_database.dart';

class TicketTimerRepository {
  TicketTimerRepository(
    this._db, {
    BusinessTime? businessTime,
    DateTime Function()? clock,
  }) : _businessTime = businessTime ?? BusinessTime.fallback(clock: clock),
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BusinessTime _businessTime;
  final DateTime Function() _clock;

  /// Records the start of a timer for [ticketId]. A session the server has not confirmed, so the
  /// caller must trigger a sync; the row is visible (and stoppable) immediately either way.
  Future<TicketTimer> start({
    required String ticketId,
    required String userId,
    String? description,
  }) async {
    final now = _clock().toUtc();
    final id = const Uuid().v4();
    final rome = _inLegacyFrame(now);
    await _db
        .into(_db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: id,
            clientId: Value(id),
            ticketId: ticketId,
            userId: Value(userId),
            workDate: Value(DateTime.utc(rome.year, rome.month, rome.day)),
            startSeconds: Value(_secondsOfDay(rome)),
            startUtc: Value(now),
            description: Value(description),
            isPendingSync: const Value(true),
          ),
        );
    return _asUtc(
      await (_db.select(
        _db.ticketTimers,
      )..where((t) => t.id.equals(id))).getSingle(),
    );
  }

  /// Closes the timer this device is running for [ticketId], if any.
  ///
  /// Only a row with no end is touched: a stopped session is finished work, and re-closing it
  /// would move the end the technician already set. [now] defaults to the clock.
  Future<TicketTimer?> stop(String ticketId, {DateTime? now}) async {
    final open =
        await (_db.select(_db.ticketTimers)..where(
              (t) =>
                  t.ticketId.equals(ticketId) &
                  t.endUtc.isNull() &
                  t.endSeconds.isNull(),
            ))
            .get();
    if (open.isEmpty) return null;
    final row = open.first;
    final end = (now ?? _clock()).toUtc();
    final rome = _inLegacyFrame(end);
    await (_db.update(
      _db.ticketTimers,
    )..where((t) => t.id.equals(row.id))).write(
      TicketTimersCompanion(
        endUtc: Value(end),
        endSeconds: Value(_secondsOfDay(rome)),
        // A close always has to reach the server, whether the row was born here or synced as
        // still running.
        isPendingSync: const Value(true),
      ),
    );
    return _asUtc(
      await (_db.select(
        _db.ticketTimers,
      )..where((t) => t.id.equals(row.id))).getSingle(),
    );
  }

  /// Every timer on one ticket, newest first, open row first among equals — the same ordering the
  /// online list arrives in.
  Future<List<TicketTimer>> forTicket(String ticketId) async =>
      (await (_db.select(_db.ticketTimers)
                ..where((t) => t.ticketId.equals(ticketId))
                ..orderBy([
                  (t) => OrderingTerm.desc(t.workDate),
                  (t) => OrderingTerm.desc(t.startSeconds),
                ]))
              .get())
          .map(_asUtc)
          .toList();

  /// The session this device currently has running, on any ticket.
  ///
  /// A pending start is included on purpose: the technician started it, and hiding it until the
  /// server confirms would let a second timer be started on another ticket.
  Future<TicketTimer?> running() async {
    final rows =
        await (_db.select(_db.ticketTimers)
              ..where((t) => t.endUtc.isNull() & t.endSeconds.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.startSeconds)])
              ..limit(1))
            .get();
    return rows.isEmpty ? null : _asUtc(rows.first);
  }

  /// Rows the server has not confirmed, oldest first.
  Future<List<TicketTimer>> pending() async =>
      (await (_db.select(_db.ticketTimers)
                ..where((t) => t.isPendingSync.equals(true))
                ..orderBy([(t) => OrderingTerm.asc(t.startUtc)]))
              .get())
          .map(_asUtc)
          .toList();

  /// The server accepted [clientId]'s session: adopt its id and stop counting the row as unsent.
  Future<void> markSynced(String clientId, String serverId) async {
    final matches =
        await (_db.select(_db.ticketTimers)..where(
              (t) =>
                  (t.clientId.equals(clientId) | t.id.equals(clientId)) &
                  t.isPendingSync.equals(true),
            ))
            .get();
    for (final row in matches) {
      if (row.id == serverId) {
        await (_db.update(
          _db.ticketTimers,
        )..where((t) => t.id.equals(row.id))).write(
          const TicketTimersCompanion(
            isPendingSync: Value(false),
            syncError: Value(null),
          ),
        );
        continue;
      }
      // The local uuid is not the server's id: move the payload across and drop the placeholder,
      // so the Ore tab holds one row for this session rather than two.
      await _db.transaction(() async {
        await _db
            .into(_db.ticketTimers)
            .insertOnConflictUpdate(
              TicketTimersCompanion.insert(
                id: serverId,
                clientId: Value(row.clientId),
                ticketId: row.ticketId,
                userId: Value(row.userId),
                workDate: Value(row.workDate),
                startSeconds: Value(row.startSeconds),
                endSeconds: Value(row.endSeconds),
                startUtc: Value(row.startUtc),
                endUtc: Value(row.endUtc),
                approvalStatus: Value(row.approvalStatus),
                description: Value(row.description),
                isManualEntry: Value(row.isManualEntry),
                isPendingSync: const Value(false),
                updatedAt: Value(row.updatedAt),
              ),
            );
        await (_db.delete(
          _db.ticketTimers,
        )..where((t) => t.id.equals(row.id))).go();
      });
    }
  }

  /// Holds a refused row out of the automatic sweep and says why, in the technician's language.
  Future<void> markSyncError(String id, String? message) =>
      (_db.update(_db.ticketTimers)..where((t) => t.id.equals(id))).write(
        TicketTimersCompanion(syncError: Value(message)),
      );

  /// Re-stamps a row's instants on the way out.
  ///
  /// Drift hands a `DateTimeColumn` back as a LOCAL-kind `DateTime` for the same instant. Both
  /// `startUtc`/`endUtc` and the `workDate` civil day pinned at UTC midnight are documented as
  /// UTC, and `DateTime.==` includes `isUtc` — so without this a caller comparing a row against
  /// the value it wrote sees "different" for the same moment, and a caller that serialises
  /// `startUtc` without remembering a `toUtc()` emits a local wall-clock time the server reads in
  /// its own zone. Same moment either way; this just makes the field names true.
  static TicketTimer _asUtc(TicketTimer row) => row.copyWith(
    workDate: Value(row.workDate?.toUtc()),
    startUtc: Value(row.startUtc?.toUtc()),
    endUtc: Value(row.endUtc?.toUtc()),
    updatedAt: Value(row.updatedAt?.toUtc()),
  );

  /// The office's zone, taken from [BusinessTime] rather than re-derived here: the workDate and the
  /// time of day this table stores are the legacy label frame every worklog reader displays, and a
  /// second opinion about which zone that is would be a second source of truth.
  tz.TZDateTime _inLegacyFrame(DateTime instant) =>
      tz.TZDateTime.from(instant, _businessTime.location);

  static int _secondsOfDay(tz.TZDateTime t) =>
      t.hour * 3600 + t.minute * 60 + t.second;
}
