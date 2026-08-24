import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/schedule_providers.dart';

/// Dashboard-derived stats (plain class, computed synchronously from async values).
class DashboardStats {
  const DashboardStats({
    required this.todayCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.upcomingCount,
  });

  final int todayCount;
  final int inProgressCount;
  final int completedCount;
  final int upcomingCount;
}

/// statusId == 2 → "In corso" (server WorkSchedule status-table convention).
const int _kStatusInProgress = 2;

/// statusId == 5 → "Completato".
const int _kStatusCompleted = 5;

/// Today's schedules with statusId == 2 (In corso).
final inProgressSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now().toUtc();
  final start = DateTime.utc(today.year, today.month, today.day);
  final end = start.add(const Duration(days: 1));
  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(start) &
              s.activityDate.isSmallerThanValue(end) &
              s.statusId.equals(_kStatusInProgress),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.timeStartMinutes)]))
      .watch();
});

/// Today's schedules with statusId == 5 (Completato).
final completedTodaySchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      final today = DateTime.now().toUtc();
      final start = DateTime.utc(today.year, today.month, today.day);
      final end = start.add(const Duration(days: 1));
      return (db.select(db.schedules)..where(
            (s) =>
                s.activityDate.isBiggerOrEqualValue(start) &
                s.activityDate.isSmallerThanValue(end) &
                s.statusId.equals(_kStatusCompleted),
          ))
          .watch();
    });

/// Schedules in [today+1 day, today+8 days) — next 7 days, excluding today.
final upcomingSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now().toUtc();
  final base = DateTime.utc(today.year, today.month, today.day);
  final start = base.add(const Duration(days: 1));
  final end = base.add(const Duration(days: 8));
  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(start) &
              s.activityDate.isSmallerThanValue(end),
        )
        ..orderBy([
          (s) => OrderingTerm.asc(s.activityDate),
          (s) => OrderingTerm.asc(s.timeStartMinutes),
        ]))
      .watch();
});

/// Computed 2×2 stats from the three stream providers above + todaySchedulesProvider.
/// Uses [AsyncValue.valueOrNull] so it reads synchronously without blocking.
final dashboardStatsProvider = Provider.autoDispose<DashboardStats>((ref) {
  final today = ref.watch(todaySchedulesProvider).valueOrNull ?? [];
  final inProgress = ref.watch(inProgressSchedulesProvider).valueOrNull ?? [];
  final completed =
      ref.watch(completedTodaySchedulesProvider).valueOrNull ?? [];
  final upcoming = ref.watch(upcomingSchedulesProvider).valueOrNull ?? [];
  return DashboardStats(
    todayCount: today.length,
    inProgressCount: inProgress.length,
    completedCount: completed.length,
    upcomingCount: upcoming.length,
  );
});

// ── Work queue ───────────────────────────────────────────────────────────────
//
// statusId == 4 → "In attesa" (server WorkSchedule status-table convention, same table
// scheduleStatusName reads).
const int _kStatusWaiting = 4;

/// statusId == 6 → "Chiuso". Folds into the same downweighted tier as Completato — both read as
/// "nothing left to do here" from the dashboard, even though they are distinct states in Storico.
const int _kStatusClosed = 6;

/// statusId == 7 → "Annullato". Dropped from the queue entirely: a cancelled job is not
/// outstanding work in any bucket, and showing it in Programmato would misstate the day ahead.
const int _kStatusCancelled = 7;

/// The dashboard's work queue, bucketed by what a technician can explain about each job without
/// reading it — not ranked by an opaque score. See PRODUCT.md-adjacent reasoning: the ID plate
/// says who/when, this queue says what matters now, and only Live/Da fare carry a call to action.
class WorkQueueBuckets {
  const WorkQueueBuckets({
    required this.live,
    required this.daFare,
    required this.programmato,
    required this.inAttesa,
    required this.fatto,
  });

  /// statusId == 2 (In corso) today. Usually the same job(s) a running clock names in the hero's
  /// tracker strip — that strip controls the clock, this names the job.
  final List<Schedule> live;

  /// The single next actionable job today — first by time among today's schedules that are
  /// neither live, waiting, nor done. Null on a day with nothing left to start.
  final Schedule? daFare;

  /// Everything not-yet-actionable: the rest of today's queue behind [daFare], plus the next
  /// seven days. One tier, not two — "later today" and "next week" are both just "not now."
  final List<Schedule> programmato;

  /// statusId == 4 (In attesa) today — blocked on something outside the technician's control.
  final List<Schedule> inAttesa;

  /// statusId == 5 or 6 (Completato/Chiuso) today.
  final List<Schedule> fatto;
}

final workQueueProvider = Provider.autoDispose<WorkQueueBuckets>((ref) {
  final today = ref.watch(todaySchedulesProvider).valueOrNull ?? [];
  final upcoming = ref.watch(upcomingSchedulesProvider).valueOrNull ?? [];

  final live = today.where((s) => s.statusId == _kStatusInProgress).toList();
  final inAttesa = today.where((s) => s.statusId == _kStatusWaiting).toList();
  final fatto = today
      .where((s) => s.statusId == _kStatusCompleted || s.statusId == _kStatusClosed)
      .toList();

  // Neither live, waiting, nor done: an open job still ahead today, in time order.
  final actionableToday = today.where((s) {
    return s.statusId != _kStatusInProgress &&
        s.statusId != _kStatusWaiting &&
        s.statusId != _kStatusCompleted &&
        s.statusId != _kStatusClosed &&
        s.statusId != _kStatusCancelled;
  }).toList();

  final daFare = actionableToday.isEmpty ? null : actionableToday.first;
  final restOfToday = actionableToday.isEmpty ? const <Schedule>[] : actionableToday.skip(1);
  final programmato = [
    ...restOfToday,
    ...upcoming.where((s) => s.statusId != _kStatusCancelled),
  ];

  return WorkQueueBuckets(
    live: live,
    daFare: daFare,
    programmato: programmato,
    inAttesa: inAttesa,
    fatto: fatto,
  );
});
