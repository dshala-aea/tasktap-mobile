import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

// ── Today's schedules ──────────────────────────────────────────────────────────

/// Stream of today's schedules from the local Drift DB (fully offline).
final todaySchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  // "Today" is the UTC calendar day — schedules' activityDate is stored as a
  // UTC-midnight date, so the window must be UTC to bucket correctly across the
  // local/UTC date boundary (a local-midnight window misbuckets near midnight).
  final today = DateTime.now().toUtc();
  final todayDate = DateTime.utc(today.year, today.month, today.day);
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
  final today = DateTime.now().toUtc();
  final start = DateTime.utc(today.year, today.month, today.day);
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

/// The materiali catalogue, from the local mirror the sync fills.
///
/// Consumers (`step_materiali_fold.dart`) still degrade to a free-text field when the list is
/// empty — a first run before the first sync, or a tenant with no catalogue — so a technician is
/// never blocked from recording a materiale by name.
final allMaterialiProvider =
    StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)
        ..where((m) => m.isActive.equals(true))
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .watch();
});

final allLocationsProvider =
    StreamProvider.autoDispose<List<Location>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)
        ..where((l) => l.isActive.equals(true))
        ..orderBy([(l) => OrderingTerm.asc(l.name)]))
      .watch();
});

final allTicketsProvider =
    StreamProvider.autoDispose<List<Ticket>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// The cantieri, from the local mirror the sync fills.
///
/// Consumers (`step_dettagli.dart`'s `_TicketCantierePicker`) still degrade to a free-text field
/// when the list is empty, so report submission is never blocked.
final allCantieriProvider =
    StreamProvider.autoDispose<List<CantieriData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});
