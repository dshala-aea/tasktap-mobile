import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time_providers.dart' show businessTimeProvider;
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
  // The tenant's business calendar day, carried as the column stores it (a civil date pinned at
  // UTC midnight). `DateTime.now().toUtc()` gave the UTC date instead, so in Rome between 00:00
  // and 02:00 local this window covered yesterday and every counter here was a day off.
  final start = ref.watch(businessTimeProvider).businessToday();
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
      final start = ref.watch(businessTimeProvider).businessToday();
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
  // Same business-zone day as the two counters above: "today" cannot mean one thing in the
  // card that counts it and another in the block that holds what follows it.
  final start = ref.watch(businessTimeProvider).businessToday().add(const Duration(days: 1));
  final end = start.add(const Duration(days: 7));
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

/// Ids of the tickets that are closed on this device.
///
/// The tenant's status flag decides, with `closedAt` as the second signal: a status change made on
/// the phone writes the new `statusId` and nothing else, so a ticket the office closed still
/// carries a null `closedAt` until the next sync. A closed ticket is finished work even when its
/// linked schedule was never moved out of "da fare" — the office closes the ticket and nothing
/// rewrites the schedule afterwards.
final closedTicketIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final closedStatusIds = db.selectOnly(db.ticketStatuses)
    ..addColumns([db.ticketStatuses.id])
    ..where(db.ticketStatuses.isClosed.equals(true));
  return (db.select(db.tickets)..where(
        (t) => t.closedAt.isNotNull() | t.statusId.isInQuery(closedStatusIds),
      ))
      .watch()
      .map((rows) => {for (final row in rows) row.id});
});

/// Whether a schedule belongs to a closed ticket. Takes the set, not the ref, so the same rule is
/// usable from a pure predicate in tests.
bool scheduleTicketIsClosed(Schedule schedule, Set<String> closedTicketIds) =>
    schedule.ticketId != null && closedTicketIds.contains(schedule.ticketId);

/// Ids of the tickets whose own status says work has started.
///
/// Read through the tenant's `isInProgress` flag, never through a status id or name: the seeded
/// "In corso" is id 2 on a fresh tenant, but the flag is the contract and the name is renameable.
///
/// This is the office-side signal, and it is not the same as a running timer. The office moves a
/// ticket to "In corso" when the job begins, and that leaves the linked schedule sitting in "da
/// fare" — so without this set the dashboard called a started job outstanding work. The timer set
/// below stays the device-local truth (the technician tapped start, possibly offline and not yet
/// synced); the two are unioned at the bucketing step rather than one standing in for the other.
final inProgressTicketIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final inProgressStatusIds = db.selectOnly(db.ticketStatuses)
    ..addColumns([db.ticketStatuses.id])
    ..where(db.ticketStatuses.isInProgress.equals(true));
  return (db.select(db.tickets)..where((t) => t.statusId.isInQuery(inProgressStatusIds)))
      .watch()
      .map((rows) => {for (final row in rows) row.id});
});

/// Ids of the tickets this device is holding a running timer for.
///
/// The device-local counterpart to [inProgressTicketIdsProvider]: the technician tapped start, so
/// the work is live even while the office's schedule row still says "da fare" and even before the
/// start has reached the server. A pending start counts too, the same way
/// [TicketTimerRepository.running] counts it.
final runningTicketTimerIdsProvider = StreamProvider.autoDispose<Set<String>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.ticketTimers)
        ..where((t) => t.endUtc.isNull() & t.endSeconds.isNull()))
      .watch()
      .map((rows) => {for (final row in rows) row.ticketId});
});

/// The single bucket a schedule lands in, decided once so the queue, the counters and the tests
/// cannot disagree about a row.
///
/// Order matters. A closed ticket outranks everything (no badge may invite work on it); a
/// cancelled schedule outranks a running timer (a cancelled job is not work in any bucket); and
/// "work has started" outranks the schedule's own status, because both the technician's timer and
/// the ticket's own "In corso" flag say the job is under way while the office's schedule row still
/// says "da fare".
enum ScheduleBucket { live, waiting, done, actionable, cancelled, absence }

ScheduleBucket bucketOfSchedule(
  Schedule schedule, {
  required Set<String> closedTicketIds,
  required Set<String> runningTicketIds,
  required Set<String> inProgressTicketIds,
}) {
  // First, before every other question: an approved absence (ferie/permesso/malattia) arrives as a
  // normal schedule row — that is how the server blocks the day — and it is the one row that is
  // never work, whatever its status says. Left to the rules below it landed in `actionable` and
  // was queued as "da fare", with a card inviting the technician to start a job that does not
  // exist.
  if (schedule.isAssenza) return ScheduleBucket.absence;
  if (scheduleTicketIsClosed(schedule, closedTicketIds)) {
    return ScheduleBucket.done;
  }
  if (schedule.statusId == _kStatusCancelled) return ScheduleBucket.cancelled;
  if (schedule.statusId == _kStatusInProgress) return ScheduleBucket.live;
  if (schedule.ticketId != null && runningTicketIds.contains(schedule.ticketId)) {
    return ScheduleBucket.live;
  }
  // The schedule row is a separate record from the ticket, and the office updates only the
  // ticket's status when the job begins. So the ticket's flag has to be read here too, or a
  // started job keeps its "da fare" badge until someone also moves the schedule.
  if (schedule.ticketId != null &&
      inProgressTicketIds.contains(schedule.ticketId)) {
    return ScheduleBucket.live;
  }
  if (schedule.statusId == _kStatusCompleted ||
      schedule.statusId == _kStatusClosed) {
    return ScheduleBucket.done;
  }
  if (schedule.statusId == _kStatusWaiting) return ScheduleBucket.waiting;
  return ScheduleBucket.actionable;
}

/// Computed 2×2 stats from the providers above.
/// Uses [AsyncValue.valueOrNull] so it reads synchronously without blocking.
final dashboardStatsProvider = Provider.autoDispose<DashboardStats>((ref) {
  final today = ref.watch(todaySchedulesProvider).valueOrNull ?? [];
  final upcoming = ref.watch(upcomingSchedulesProvider).valueOrNull ?? [];
  final closedTickets =
      ref.watch(closedTicketIdsProvider).valueOrNull ?? const <String>{};
  final runningTickets =
      ref.watch(runningTicketTimerIdsProvider).valueOrNull ?? const <String>{};
  final inProgressTickets =
      ref.watch(inProgressTicketIdsProvider).valueOrNull ?? const <String>{};

  ScheduleBucket bucket(Schedule s) => bucketOfSchedule(
    s,
    closedTicketIds: closedTickets,
    runningTicketIds: runningTickets,
    inProgressTicketIds: inProgressTickets,
  );

  // Counted through the same buckets the queue uses, so the hero's "DA FARE" remainder cannot
  // disagree with what the queue below it shows. Absences are not "interventi": a day off counted
  // beside a day of work is the same bug as one queued as a job, one screen up.
  final work = today.where((s) => bucket(s) != ScheduleBucket.absence);
  return DashboardStats(
    todayCount: work.length,
    inProgressCount: work.where((s) => bucket(s) == ScheduleBucket.live).length,
    completedCount: work.where((s) => bucket(s) == ScheduleBucket.done).length,
    upcomingCount: upcoming
        .where(
          (s) =>
              bucket(s) != ScheduleBucket.cancelled &&
              bucket(s) != ScheduleBucket.absence &&
              !scheduleTicketIsClosed(s, closedTickets),
        )
        .length,
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
    required this.restOfToday,
    required this.upcoming,
    required this.inAttesa,
    required this.fatto,
    required this.absences,
  });

  /// statusId == 2 (In corso) today. Usually the same job(s) a running clock names in the hero's
  /// tracker strip — that strip controls the clock, this names the job.
  final List<Schedule> live;

  /// The single next actionable job today — first by time among today's schedules that are
  /// neither live, waiting, nor done. Null on a day with nothing left to start.
  final Schedule? daFare;

  /// Today's actionable queue behind [daFare] — still today, but not the next thing to start.
  ///
  /// Split from [upcoming] deliberately. They used to share one `programmato` tier, and on a day
  /// with no schedules at all the dashboard then showed the "Oggi" heading over rows dated
  /// tomorrow and later, with nothing saying today itself was empty — the today-vs-planned
  /// ambiguity this split removes.
  final List<Schedule> restOfToday;

  /// Tomorrow through today+7, cancelled excluded: work that is genuinely another day.
  final List<Schedule> upcoming;

  /// statusId == 4 (In attesa) today — blocked on something outside the technician's control.
  final List<Schedule> inAttesa;

  /// Today's finished work: statusId == 5 or 6 (Completato/Chiuso), plus anything on a ticket the
  /// tenant considers closed. The second group is the point — the office closes the ticket and
  /// leaves the schedule in "da fare", so status alone would keep calling it outstanding work.
  final List<Schedule> fatto;

  /// Today's approved absences (ferie/permesso/malattia), in time order.
  ///
  /// Not work, and not in any tier above: the day is blocked for the technician, so there is
  /// nothing to start, nothing to wait on and nothing to finish. The dashboard still says what the
  /// day holds — "Ferie" where a job card would otherwise sit — because a technician opening the
  /// app on a day off should read that, not an empty queue that looks like a sync failure.
  final List<Schedule> absences;

  /// Whether today itself has anything in it, in any state. False means the day is genuinely
  /// empty, whatever [upcoming] holds — the dashboard states that rather than letting future
  /// rows stand in for today's work.
  bool get hasTodayWork =>
      live.isNotEmpty || daFare != null || inAttesa.isNotEmpty || fatto.isNotEmpty;

  /// Whether today holds anything at all, work or absence. The day off is a fact about the day,
  /// not an empty day, so the screen states it instead of the "nothing assigned" sentence.
  bool get hasTodayAnything => hasTodayWork || absences.isNotEmpty;

  /// Every open job still ahead today, in time order — [daFare] first, then [restOfToday].
  ///
  /// The dashboard renders all of these as full "Da fare" cards, which is what the header's own
  /// "N DA FARE" count means. Only the first one used to get a card; the rest were demoted to a
  /// compact tier labelled PROGRAMMATO, so on a day with two jobs the screen showed one.
  List<Schedule> get actionableToday => [?daFare, ...restOfToday];
}

final workQueueProvider = Provider.autoDispose<WorkQueueBuckets>((ref) {
  final today = ref.watch(todaySchedulesProvider).valueOrNull ?? [];
  final upcoming = ref.watch(upcomingSchedulesProvider).valueOrNull ?? [];
  final closedTickets =
      ref.watch(closedTicketIdsProvider).valueOrNull ?? const <String>{};
  final runningTickets =
      ref.watch(runningTicketTimerIdsProvider).valueOrNull ?? const <String>{};
  final inProgressTickets =
      ref.watch(inProgressTicketIdsProvider).valueOrNull ?? const <String>{};

  ScheduleBucket bucket(Schedule s) => bucketOfSchedule(
    s,
    closedTicketIds: closedTickets,
    runningTicketIds: runningTickets,
    inProgressTicketIds: inProgressTickets,
  );

  final live = <Schedule>[];
  final inAttesa = <Schedule>[];
  final fatto = <Schedule>[];
  final absences = <Schedule>[];
  final actionableToday = <Schedule>[];
  for (final schedule in today) {
    switch (bucket(schedule)) {
      case ScheduleBucket.live:
        live.add(schedule);
      case ScheduleBucket.waiting:
        inAttesa.add(schedule);
      case ScheduleBucket.done:
        fatto.add(schedule);
      case ScheduleBucket.actionable:
        actionableToday.add(schedule);
      case ScheduleBucket.absence:
        absences.add(schedule);
      case ScheduleBucket.cancelled:
        break;
    }
  }

  final daFare = actionableToday.isEmpty ? null : actionableToday.first;
  final restOfToday = actionableToday.isEmpty
      ? const <Schedule>[]
      : actionableToday.skip(1).toList();

  return WorkQueueBuckets(
    live: live,
    daFare: daFare,
    restOfToday: restOfToday,
    // Tomorrow's rows run through the same buckets: a closed ticket's job tomorrow is not work
    // ahead, for the same reason a cancelled one is not, and the hero's count agrees. An absence
    // is dropped for the same reason — it is not work ahead — and it stays visible in Calendario,
    // which is where a planned day off belongs.
    upcoming: upcoming
        .where(
          (s) =>
              bucket(s) != ScheduleBucket.cancelled &&
              bucket(s) != ScheduleBucket.absence &&
              !scheduleTicketIsClosed(s, closedTickets),
        )
        .toList(),
    inAttesa: inAttesa,
    fatto: fatto,
    absences: absences,
  );
});
