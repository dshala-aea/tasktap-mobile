// The dashboard queue answers one question per row: what does this job still need from me? Its
// only input used to be the schedule's own `statusId`, which the office does not touch when it
// closes the ticket — so a finished job kept its "DA FARE" badge and invited the technician to
// start it again. These tests pin the two ticket-side signals that correct it (a closed status,
// a running timer) and the one that must still win over both (a cancelled schedule).

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/dashboard/dashboard_providers.dart';
import 'package:tasktap_mobile/presentation/providers/schedule_providers.dart';

/// The "da fare" status every seeded schedule starts in.
const int _daFare = 1;
const int _inCorso = 2;
const int _annullato = 7;

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late DateTime today;
  late DateTime tomorrow;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    // Anchored to the *business* day, not the UTC date. The queue reads its day through
    // `BusinessTime`, and between 23:00Z and 00:00Z (CET) the UTC date is still yesterday while
    // the business day has already rolled over — every schedule seeded for this fixture's "today"
    // then fell outside the day the queue reads and the whole file went red for that one hour,
    // in whichever CI run happened to land inside it.
    //
    // The value is `businessToday()` itself: a civil date pinned at UTC midnight, which is the
    // convention `schedules.activityDate` stores and the one `todaySchedulesProvider` compares
    // against (`>= businessToday() & < +1 day`). Not the UTC instant that civil date starts at —
    // `utcRangeForBusinessDate()` answers the other question, and for Rome in CET it returns
    // 23:00Z of the previous day, an hour *before* the window the queue reads, so every seeded
    // schedule fell outside it and the whole file went red at every hour of the day, not only
    // across midnight. `tomorrow` is the next civil date for the same reason: in this convention
    // there is no DST to step over.
    final bt = BusinessTime.fallback();
    today = bt.businessToday();
    tomorrow = today.add(const Duration(days: 1));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seedStatus({
    required int id,
    required String name,
    bool isClosed = false,
    bool isInProgress = false,
  }) => db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: Value(id),
          tenantId: 'tenant-1',
          name: name,
          isClosed: Value(isClosed),
          isInProgress: Value(isInProgress),
        ),
      );

  Future<void> seedTicket({
    required String id,
    required int statusId,
    DateTime? closedAt,
  }) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Intervento $id',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: statusId,
          typeId: 1,
          closedAt: Value(closedAt),
        ),
      );

  Future<void> seedSchedule({
    required String id,
    required String? ticketId,
    required DateTime day,
    int statusId = _daFare,
    bool isAssenza = false,
  }) => db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          ticketId: Value(ticketId),
          activityDate: day,
          timeStartMinutes: 480,
          timeEndMinutes: 1020,
          userId: 'user-1',
          statusId: statusId,
          locationId: 'loc-1',
          // An approved absence carries the server's own label, lowercase, and no ticket.
          title: isAssenza ? 'ferie' : 'Intervento $id',
          description: '',
          isAssenza: Value(isAssenza),
        ),
      );

  Future<void> seedRunningTimer(String ticketId) => db
      .into(db.ticketTimers)
      .insert(
        TicketTimersCompanion.insert(
          id: 'timer-$ticketId',
          ticketId: ticketId,
          startUtc: Value(DateTime.utc(2026, 7, 10, 7)),
        ),
      );

  /// Reads [workQueueProvider] once every provider it watches has data.
  ///
  /// The listener is what makes that possible: these are `autoDispose` providers, so a bare
  /// `container.read(...)` releases them again and the queue would recompute against
  /// `AsyncLoading`. It is not closed on purpose — the container disposes it, and the stats
  /// assertions below read the same live graph. Awaiting each dependency also proves the queries
  /// run at all.
  Future<WorkQueueBuckets> readQueue() async {
    container.listen(workQueueProvider, (_, _) {});
    await container.read(todaySchedulesProvider.future);
    await container.read(upcomingSchedulesProvider.future);
    await container.read(closedTicketIdsProvider.future);
    await container.read(runningTicketTimerIdsProvider.future);
    await container.read(inProgressTicketIdsProvider.future);
    return container.read(workQueueProvider);
  }

  test('inProgressSchedulesProvider emits empty list when db empty', () async {
    final result = await container.read(inProgressSchedulesProvider.future);
    expect(result, isEmpty);
  });

  test('dashboardStatsProvider returns zeros when db empty', () {
    final stats = container.read(dashboardStatsProvider);
    expect(stats.todayCount, 0);
    expect(stats.inProgressCount, 0);
    expect(stats.completedCount, 0);
    expect(stats.upcomingCount, 0);
  });

  test('a job on a closed ticket is finished, not "da fare"', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedStatus(id: 6, name: 'Chiuso', isClosed: true);
    await seedTicket(id: 't-open', statusId: 1);
    await seedTicket(id: 't-closed', statusId: 6);
    // The real shape of the bug: the ticket was closed, the schedule never moved.
    await seedSchedule(id: 's-closed', ticketId: 't-closed', day: today);
    await seedSchedule(id: 's-open', ticketId: 't-open', day: today);

    final queue = await readQueue();

    expect(queue.daFare?.id, 's-open');
    expect(queue.restOfToday, isEmpty);
    expect(queue.fatto.map((s) => s.id), ['s-closed']);
  });

  test(
    'closedAt alone marks the ticket closed, before the status reaches the phone',
    () async {
      await seedStatus(id: 1, name: 'Aperto');
      // A ticket closed on the phone carries the new statusId and nothing else; a ticket closed by
      // the office can arrive with closedAt set under a status the mirror still calls open.
      await seedTicket(
        id: 't-closed',
        statusId: 1,
        closedAt: DateTime.utc(2026, 7, 9),
      );
      await seedSchedule(id: 's-closed', ticketId: 't-closed', day: today);

      final queue = await readQueue();

      expect(queue.daFare, null);
      expect(queue.fatto.map((s) => s.id), ['s-closed']);
    },
  );

  test('a running ticket timer puts its job in Live, not "da fare"', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-working', statusId: 1);
    await seedTicket(id: 't-idle', statusId: 1);
    await seedSchedule(id: 's-working', ticketId: 't-working', day: today);
    await seedSchedule(id: 's-idle', ticketId: 't-idle', day: today);
    await seedRunningTimer('t-working');

    final queue = await readQueue();

    expect(queue.live.map((s) => s.id), ['s-working']);
    expect(queue.daFare?.id, 's-idle');
  });

  test('a stopped timer leaves the job where its status says', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-done', statusId: 1);
    await seedSchedule(id: 's-done', ticketId: 't-done', day: today);
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'timer-1',
            ticketId: 't-done',
            startUtc: Value(DateTime.utc(2026, 7, 10, 7)),
            endUtc: Value(DateTime.utc(2026, 7, 10, 9)),
          ),
        );

    final queue = await readQueue();

    expect(queue.live, isEmpty);
    expect(queue.daFare?.id, 's-done');
  });

  test('cancelled still wins over a running timer', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-cancelled', statusId: 1);
    await seedSchedule(
      id: 's-cancelled',
      ticketId: 't-cancelled',
      day: today,
      statusId: _annullato,
    );
    await seedRunningTimer('t-cancelled');

    final queue = await readQueue();

    expect(queue.live, isEmpty);
    expect(queue.daFare, null);
    expect(queue.fatto, isEmpty);
  });

  test("a closed ticket's job tomorrow is not ahead of us", () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedStatus(id: 6, name: 'Chiuso', isClosed: true);
    await seedTicket(id: 't-closed', statusId: 6);
    await seedTicket(id: 't-open', statusId: 1);
    await seedSchedule(
      id: 's-closed-tomorrow',
      ticketId: 't-closed',
      day: tomorrow,
    );
    await seedSchedule(
      id: 's-open-tomorrow',
      ticketId: 't-open',
      day: tomorrow,
    );

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    expect(queue.upcoming.map((s) => s.id), ['s-open-tomorrow']);
    expect(stats.upcomingCount, 1);
  });

  test('a schedule already in "in corso" stays live without a timer', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-1', statusId: 1);
    await seedSchedule(
      id: 's-live',
      ticketId: 't-1',
      day: today,
      statusId: _inCorso,
    );

    final queue = await readQueue();

    expect(queue.live.map((s) => s.id), ['s-live']);
    expect(queue.daFare, null);
  });

  // The office starts a job by moving the TICKET to "In corso"; the linked schedule row stays in
  // "da fare", because nothing rewrites it. With only the schedule's own statusId to go on, the
  // dashboard kept the job in the "DA FARE" slot while the work was already under way.
  test("a ticket in \"In corso\" is live even with its schedule still 'da fare'", () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedStatus(id: _inCorso, name: 'In corso', isInProgress: true);
    await seedTicket(id: 't-started', statusId: _inCorso);
    await seedTicket(id: 't-pending', statusId: 1);
    await seedSchedule(id: 's-started', ticketId: 't-started', day: today);
    await seedSchedule(id: 's-pending', ticketId: 't-pending', day: today);

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    expect(queue.live.map((s) => s.id), ['s-started']);
    expect(queue.daFare?.id, 's-pending');
    expect(stats.inProgressCount, 1);
  });

  // The flag is the contract, not the id and not the name: a tenant that renames "In corso" or
  // seeds its own statuses gets a different id, and a dashboard keyed on `statusId == 2` would
  // silently stop recognising started work for that tenant.
  test('a renamed in-progress status is recognised through its flag, not its id', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedStatus(id: 42, name: 'Sul posto', isInProgress: true);
    await seedTicket(id: 't-1', statusId: 42);
    await seedSchedule(id: 's-1', ticketId: 't-1', day: today);

    final queue = await readQueue();

    expect(queue.live.map((s) => s.id), ['s-1']);
    expect(queue.daFare, null);
  });

  // A closed status that also carries the started flag is still finished work — closing must keep
  // outranking every "work has started" signal, or a closed ticket would reappear on the clock.
  test('a closed ticket outranks an in-progress flag on the same status', () async {
    await seedStatus(id: 6, name: 'Chiuso', isClosed: true, isInProgress: true);
    await seedTicket(id: 't-1', statusId: 6);
    await seedSchedule(id: 's-1', ticketId: 't-1', day: today);

    final queue = await readQueue();

    expect(queue.live, isEmpty);
    expect(queue.fatto.map((s) => s.id), ['s-1']);
  });

  // An approved absence is materialised server-side as an ordinary schedule so the agenda blocks
  // the day. Nothing in the row itself says "not work": it has a status, an assignee and no ticket,
  // which is exactly the shape the "da fare" bucket used to claim. The technician then read a day
  // off as a day with a job to start.
  test('an approved absence is not queued as work', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-1', statusId: 1);
    await seedSchedule(id: 's-job', ticketId: 't-1', day: today);
    await seedSchedule(id: 's-ferie', ticketId: null, day: today, isAssenza: true);

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    expect(queue.daFare?.id, 's-job');
    expect(queue.restOfToday, isEmpty);
    expect(queue.absences.map((s) => s.id), ['s-ferie']);
    // Counted through the same buckets: "N interventi oggi" must not include the day off.
    expect(stats.todayCount, 1);
  });

  test('a day that holds only an absence is not an empty day', () async {
    await seedSchedule(id: 's-ferie', ticketId: null, day: today, isAssenza: true);

    final queue = await readQueue();

    expect(queue.absences.map((s) => s.id), ['s-ferie']);
    // The screen branches on these two: `hasTodayWork` picks the "nothing assigned" sentence and
    // must not swallow the absence, `hasTodayAnything` is what keeps the day from reading as
    // empty.
    expect(queue.hasTodayWork, isFalse);
    expect(queue.hasTodayAnything, isTrue);
  });

  test('an absence in the next seven days is not work ahead', () async {
    await seedSchedule(
      id: 's-ferie-domani',
      ticketId: null,
      day: tomorrow,
      isAssenza: true,
    );

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    // Still visible in Calendario, which is where a planned day off belongs — but the dashboard's
    // "Prossimi 7 giorni" counts work, and "1 in arrivo" over a week off is a wrong day.
    expect(queue.upcoming, isEmpty);
    expect(stats.upcomingCount, 0);
  });

  // The flag outranks the status for the same reason a closed ticket does: the office may well
  // move an absence row's status, and a finished-looking one must not return to the queue.
  test('an absence stays out of every work tier whatever its status says', () async {
    await seedSchedule(
      id: 's-ferie-live',
      ticketId: null,
      day: today,
      statusId: _inCorso,
      isAssenza: true,
    );
    await seedSchedule(
      id: 's-ferie-fatto',
      ticketId: null,
      day: today,
      statusId: 5,
      isAssenza: true,
    );

    final queue = await readQueue();

    expect(queue.live, isEmpty);
    expect(queue.fatto, isEmpty);
    expect(queue.absences.map((s) => s.id), ['s-ferie-live', 's-ferie-fatto']);
  });
}
