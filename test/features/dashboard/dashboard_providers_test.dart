// The dashboard queue answers one question per row: what does this job still need from me? Its
// only input used to be the schedule's own `statusId`, which the office does not touch when it
// closes the ticket — so a finished job kept its "DA FARE" badge and invited the technician to
// start it again. These tests pin the two ticket-side signals that correct it (a closed status,
// a running timer) and the one that must still win over both (a cancelled schedule).

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    final now = DateTime.now().toUtc();
    today = DateTime.utc(now.year, now.month, now.day);
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
          title: 'Intervento $id',
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
      day: today.add(const Duration(days: 1)),
    );
    await seedSchedule(
      id: 's-open-tomorrow',
      ticketId: 't-open',
      day: today.add(const Duration(days: 1)),
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

  // ── Absences ───────────────────────────────────────────────────────────────
  //
  // An approved Ferie/Permesso/Malattia is written server-side as a completely ordinary Schedule
  // row and keeps the tenant's default work status, so nothing in the row itself says "do not
  // work this". Without the flag the day of leave counted in "INTERVENTI OGGI" and, worse, became
  // the dashboard's next job to start.

  test('an absence today is not queued as work, and is not counted', () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-1', statusId: 1);
    await seedSchedule(id: 's-job', ticketId: 't-1', day: today);
    // No ticket, the default "Pianificato" status: exactly what the server sends for an absence.
    await seedSchedule(id: 's-ferie', ticketId: null, day: today, isAssenza: true);

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    expect(queue.absences.map((s) => s.id), ['s-ferie']);
    expect(queue.daFare?.id, 's-job', reason: 'the absence must not take the "next job" slot');
    expect(queue.restOfToday, isEmpty);
    expect(queue.fatto, isEmpty);
    expect(stats.todayCount, 1, reason: '"INTERVENTI OGGI" counts jobs, not leave');
  });

  test('a day that is only leave says so instead of looking empty', () async {
    await seedSchedule(id: 's-ferie', ticketId: null, day: today, isAssenza: true);

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    expect(queue.hasTodayWork, isFalse);
    expect(queue.absences, hasLength(1));
    expect(stats.todayCount, 0);
  });

  test("tomorrow's absence is not work ahead, and not counted as such", () async {
    await seedStatus(id: 1, name: 'Aperto');
    await seedTicket(id: 't-1', statusId: 1);
    await seedSchedule(
      id: 's-job-tomorrow',
      ticketId: 't-1',
      day: today.add(const Duration(days: 1)),
    );
    await seedSchedule(
      id: 's-ferie-tomorrow',
      ticketId: null,
      day: today.add(const Duration(days: 1)),
      isAssenza: true,
    );

    final queue = await readQueue();
    final stats = container.read(dashboardStatsProvider);

    expect(queue.upcoming.map((s) => s.id), ['s-job-tomorrow']);
    expect(stats.upcomingCount, 1);
  });

  test('an absence outranks a cancelled status, a timer and a closed ticket', () async {
    // A cancelled-but-absent row is still an absence: the flag describes what owns the row, and the
    // queue must never resurrect it as work through any of the other signals.
    await seedStatus(id: 1, name: 'Aperto');
    await seedStatus(id: 6, name: 'Chiuso', isClosed: true);
    await seedTicket(id: 't-closed', statusId: 6);
    await seedRunningTimer('t-closed');
    await seedSchedule(id: 's-x', ticketId: 't-closed', day: today, isAssenza: true);
    await seedSchedule(
      id: 's-y',
      ticketId: null,
      day: today,
      statusId: _annullato,
      isAssenza: true,
    );

    final queue = await readQueue();

    // Both rows carry the same start time, so their relative order is unspecified — assert the
    // membership, not a list order the query never promised.
    expect(queue.absences.map((s) => s.id), containsAll(['s-x', 's-y']));
    expect(queue.absences, hasLength(2));
    expect(queue.live, isEmpty);
    expect(queue.fatto, isEmpty);
    expect(queue.daFare, null);
    expect(queue.inAttesa, isEmpty);
  });
}
