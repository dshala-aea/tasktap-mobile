import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

// ── Today's schedules ──────────────────────────────────────────────────────────

/// Stream of today's schedules from the local Drift DB (fully offline).
final todaySchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
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
final weekSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now().toUtc();
  final start = DateTime.utc(today.year, today.month, today.day);
  final end = start.add(const Duration(days: 8));

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

// ── Customer / Location look-ups ───────────────────────────────────────────────

/// Look up a single [Customer] by id from the local cache.
final customerByIdProvider = StreamProvider.autoDispose.family<Customer?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.customers)..where((c) => c.id.equals(id))).watchSingleOrNull();
});

/// Look up a single [Location] by id from the local cache.
final locationByIdProvider = StreamProvider.autoDispose.family<Location?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)..where((l) => l.id.equals(id))).watchSingleOrNull();
});

/// Look up a single [Ticket] by id from the local cache.
final ticketByIdProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)..where((t) => t.id.equals(id))).watchSingleOrNull();
});

// ── Draft reports ──────────────────────────────────────────────────────────────

/// Stream of all draft reports for the current user from the local Drift DB.
final draftReportsProvider = StreamProvider.autoDispose<List<DraftReport>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.draftReports)
        ..where((r) => r.stato.equals('Bozza'))
        ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
      .watch();
});

// ── All cached customers/locations/materiali (for pickers) ────────────────────

final allCustomersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
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
final allMaterialiProvider = StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)
        ..where((m) => m.isActive.equals(true))
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .watch();
});

/// The colleagues who can be named on a rapportino, from the local mirror the sync fills.
///
/// Unlike the materiali picker this one has no free-text fallback, and deliberately so. A materiale
/// typed by name is still a readable line on an invoice; a *person* typed by name is not — the
/// server needs their user id to attribute the hours, and there is no way for a technician to know
/// or type one. When this list is empty the step says so and offers no way to invent an entry,
/// because the previous behaviour was to fabricate `user-<timestamp>` and let those hours reach
/// payroll attributed to nobody.
final allColleaguesProvider = StreamProvider.autoDispose<List<Colleague>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.colleagues)..orderBy([(c) => OrderingTerm.asc(c.displayName)])).watch();
});

/// One colleague's display name, from the same local mirror.
///
/// Exists because screens were rendering raw user ids at people. The ticket detail's "Tecnico" row
/// showed `assignedUserId` verbatim — a GUID — which is not a name, is not memorable, and tells a
/// technician nothing about who holds the job.
///
/// Resolving it here rather than through `/api/app/interventi/{id}` (which returns a resolved
/// `tecnico` string) is the deliberate choice: the mirror is already synced and already on the
/// device, so the name is there with no signal. An online lookup would have made the most basic
/// fact on the screen the one thing that disappears in a plant room.
///
/// Null when the id is unknown to the mirror — a colleague who left, or a sync that has not landed
/// yet. Callers fall back to the id rather than to an empty string: an unfamiliar id is at least
/// something to read out over the phone.
final colleagueNameProvider = StreamProvider.autoDispose.family<String?, String>((ref, userId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.colleagues,
  )..where((c) => c.id.equals(userId))).watchSingleOrNull().map((c) => c?.displayName);
});

final allLocationsProvider = StreamProvider.autoDispose<List<Location>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)
        ..where((l) => l.isActive.equals(true))
        ..orderBy([(l) => OrderingTerm.asc(l.name)]))
      .watch();
});

final allTicketsProvider = StreamProvider.autoDispose<List<Ticket>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
});

/// The cantieri, from the local mirror the sync fills.
///
/// Consumers (`step_dettagli.dart`'s `_TicketCantierePicker`) still degrade to a free-text field
/// when the list is empty, so report submission is never blocked.
final allCantieriProvider = StreamProvider.autoDispose<List<CantieriData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();
});

// ── Schedule assignment (ADR-0009) ─────────────────────────────────────────────

/// Everyone on one schedule, from the local `ScheduleAssignees` mirror.
///
/// Kept separate from [Schedule] itself on purpose — see `app_database.dart`'s `Schedules` doc
/// comment: `teamLeadId`/`staffIds`/`squadraId` were dropped from that table when assignment moved
/// server-side to a set of rows, and this reads that same set rather than re-adding them.
final scheduleAssigneesProvider = StreamProvider.autoDispose.family<List<ScheduleAssignee>, String>(
  (ref, scheduleId) {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(
      db.scheduleAssignees,
    )..where((a) => a.scheduleId.equals(scheduleId))).watch();
  },
);

/// Ids of every schedule that has at least one squadra-mediated assignee (`isTeam`).
///
/// This is the on-device signal for "is this a team job" — the squadra's own name is not synced
/// to the device (only `/api/schedules/{id}` resolves it, online-only), so a calendar view can
/// show *that* a schedule is squadra-assigned without fabricating a name it does not have. See
/// `calendario/views/*` — the four calendar views read this to render a team indicator.
final teamAssignedScheduleIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final query = db.selectOnly(db.scheduleAssignees)
    ..addColumns([db.scheduleAssignees.scheduleId])
    ..where(db.scheduleAssignees.isTeam.equals(true));
  return query
      .map((row) => row.read(db.scheduleAssignees.scheduleId)!)
      .watch()
      .map((ids) => ids.toSet());
});

/// `scheduleId` → every `userId` on it, from the local `ScheduleAssignees` mirror — everyone,
/// regardless of why they are on it (direct, lead, squadra member, legacy staff).
///
/// Backs the admin schedule list's technician and squadra filters
/// (`admin_schedule_list_screen.dart`): "assigned to this technician" means every way they could
/// be on the schedule, the same semantics the backend's own `IScheduleAssignmentResolver.
/// WhereAssignedTo` uses for `GET /api/schedules?userId=`; "assigned to this squadra" is not a
/// filterable field on-device at all (no squadra id is synced — see
/// `teamAssignedScheduleIdsProvider`'s doc comment) but its *members* are known once fetched
/// (`AdminApiClient.fetchSquadraDetail`), so the squadra filter intersects this map's per-schedule
/// user sets against the fetched member ids.
final scheduleAssigneeMapProvider = StreamProvider.autoDispose<Map<String, Set<String>>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.scheduleAssignees).watch().map((rows) {
    final map = <String, Set<String>>{};
    for (final row in rows) {
      map.putIfAbsent(row.scheduleId, () => {}).add(row.userId);
    }
    return map;
  });
});
