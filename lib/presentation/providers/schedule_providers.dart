import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

// ── Today's schedules ──────────────────────────────────────────────────────────

/// Stream of today's schedules from the local Drift DB (fully offline).
final todaySchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now();
  final todayDate =
      DateTime(today.year, today.month, today.day).toUtc();
  final tomorrowDate = todayDate.add(const Duration(days: 1));

  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(todayDate) &
              s.activityDate.isSmallerThanValue(tomorrowDate),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.timeStartMinutes)]))
      .watch();
});

/// Stream of schedules in [today, today+7d] from the local Drift DB.
final weekSchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day).toUtc();
  final end = start.add(const Duration(days: 8));

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

// ── Customer / Location look-ups ───────────────────────────────────────────────

/// Look up a single [Customer] by id from the local cache.
final customerByIdProvider =
    StreamProvider.autoDispose.family<Customer?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.customers)
        ..where((c) => c.id.equals(id)))
      .watchSingleOrNull();
});

/// Look up a single [Location] by id from the local cache.
final locationByIdProvider =
    StreamProvider.autoDispose.family<Location?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)
        ..where((l) => l.id.equals(id)))
      .watchSingleOrNull();
});

/// Look up a single [Ticket] by id from the local cache.
final ticketByIdProvider =
    StreamProvider.autoDispose.family<Ticket?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.id.equals(id)))
      .watchSingleOrNull();
});

// ── Draft reports ──────────────────────────────────────────────────────────────

/// Stream of all draft reports for the current user from the local Drift DB.
final draftReportsProvider =
    StreamProvider.autoDispose<List<DraftReport>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.draftReports)
        ..where((r) => r.stato.equals('Bozza'))
        ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
      .watch();
});

// ── All cached customers/locations/materiali (for pickers) ────────────────────

final allCustomersProvider =
    StreamProvider.autoDispose<List<Customer>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.customers)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.companyName)]))
      .watch();
});

final allMaterialiProvider =
    StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)
        ..where((m) => m.isActive.equals(true))
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .watch();
});
