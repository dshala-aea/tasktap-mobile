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
final inProgressSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
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
final completedTodaySchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
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
final upcomingSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now().toUtc();
  final base = DateTime.utc(today.year, today.month, today.day);
  final start = base.add(const Duration(days: 1));
  final end = base.add(const Duration(days: 8));
  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(start) & s.activityDate.isSmallerThanValue(end),
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
  final completed = ref.watch(completedTodaySchedulesProvider).valueOrNull ?? [];
  final upcoming = ref.watch(upcomingSchedulesProvider).valueOrNull ?? [];
  return DashboardStats(
    todayCount: today.length,
    inProgressCount: inProgress.length,
    completedCount: completed.length,
    upcomingCount: upcoming.length,
  );
});
