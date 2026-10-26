import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/dashboard/work_queue_section.dart';

Widget _buildSection({required AppDatabase db, DateTime Function()? clock}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ],
    child: const MaterialApp(home: Scaffold(body: WorkQueueSection())),
  );
}

/// The civil date the queue buckets by: the business zone's (Rome by default), never the device's,
/// so a test run is not a function of where the runner sits.
DateTime _today({DateTime Function()? clock}) =>
    BusinessTime.fallback(clock: clock).businessToday();

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('WorkQueueSection all-day schedules', () {
    testWidgets('an all-day Da fare schedule does not render 00:00', (tester) async {
      final dayStart = _today();
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-allday',
              tenantId: 'tenant-1',
              createdAt: dayStart,
              activityDate: dayStart,
              timeStartMinutes: 0,
              timeEndMinutes: 0,
              userId: 'u1',
              statusId: 1, // Aperto — lands in "Da fare" (actionable, not live/waiting/done)
              locationId: 'loc-1',
              allDay: const Value(true),
              title: 'Intervento tutto il giorno',
              description: '',
            ),
          );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Intervento tutto il giorno'), findsOneWidget);
      expect(find.textContaining('00:00'), findsNothing);

      // Same unmount-before-teardown convention dashboard_screen_test.dart's own tests use —
      // without it a pending Timer from a provider mounted here trips
      // AutomatedTestWidgetsFlutterBinding's `!timersPending` invariant after disposal.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an all-day schedule today does not render 00:00', (tester) async {
      final dayStart = _today();
      // Two schedules today: both are today's work, so both render as focus cards — the all-day
      // one included, whose 0/0 placeholder minutes are not a real time of day.
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-1',
              tenantId: 'tenant-1',
              createdAt: dayStart,
              activityDate: dayStart,
              timeStartMinutes: 480,
              timeEndMinutes: 600,
              userId: 'u1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Primo intervento',
              description: '',
            ),
          );
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-allday',
              tenantId: 'tenant-1',
              createdAt: dayStart,
              activityDate: dayStart,
              timeStartMinutes: 0,
              timeEndMinutes: 0,
              userId: 'u1',
              statusId: 1,
              locationId: 'loc-1',
              allDay: const Value(true),
              title: 'Intervento tutto il giorno',
              description: '',
            ),
          );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Intervento tutto il giorno'), findsOneWidget);
      expect(find.textContaining('00:00'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('WorkQueueSection today versus planned', () {
    Future<void> insertSchedule(
      AppDatabase db, {
      required String id,
      required DateTime activityDate,
      required String title,
    }) {
      return db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: id,
              tenantId: 'tenant-1',
              createdAt: activityDate,
              activityDate: activityDate,
              timeStartMinutes: 480,
              timeEndMinutes: 600,
              userId: 'u1',
              statusId: 1,
              locationId: 'loc-1',
              title: title,
              description: '',
            ),
          );
    }

    testWidgets('an empty today says so instead of heading future rows with "Oggi"', (
      tester,
    ) async {
      final dayStart = _today();
      await insertSchedule(
        db,
        id: 'sched-upcoming',
        activityDate: dayStart.add(const Duration(days: 2)),
        title: 'Intervento di giovedì',
      );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      // The day's own answer, stated rather than implied by the absence of rows.
      expect(find.text('Nessun lavoro assegnato per la giornata di oggi.'), findsOneWidget);
      // And the future work sits under its own heading, not under the screen's "Oggi".
      expect(find.textContaining('PROSSIMI 7 GIORNI'), findsOneWidget);
      expect(find.text('Intervento di giovedì'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('every open job scheduled today shows as its own "Da fare" card', (tester) async {
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
      await insertSchedule(db, id: 'sched-1', activityDate: dayStart, title: 'Primo intervento');
      await insertSchedule(db, id: 'sched-2', activityDate: dayStart, title: 'Secondo intervento');

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      // rh5w: the second job of the day used to be demoted to a compact tier labelled
      // PROGRAMMATO, so the header's "2 DA FARE" stood over a single card and the second job read
      // as planned for another day.
      expect(find.text('Primo intervento'), findsOneWidget);
      expect(find.text('Secondo intervento'), findsOneWidget);
      expect(find.text('DA FARE'), findsNWidgets(2));
      expect(find.textContaining('PROGRAMMATO'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a booked today shows its own rows and does not claim the day is empty', (
      tester,
    ) async {
      final dayStart = _today();
      await insertSchedule(
        db,
        id: 'sched-today',
        activityDate: dayStart,
        title: 'Intervento di oggi',
      );
      await insertSchedule(
        db,
        id: 'sched-upcoming',
        activityDate: dayStart.add(const Duration(days: 3)),
        title: 'Intervento di venerdì',
      );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Nessun lavoro assegnato per la giornata di oggi.'), findsNothing);
      expect(find.text('Intervento di oggi'), findsOneWidget);
      expect(find.textContaining('PROSSIMI 7 GIORNI'), findsOneWidget);
      expect(find.text('Intervento di venerdì'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('nothing today and nothing in the next seven days keeps the single empty state', (
      tester,
    ) async {
      // Synced device: the mirror is empty, so "nothing anywhere" is its own answer.
      await db.setLastSync(DateTime.utc(2026, 10, 1));
      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Nessun intervento oggi'), findsOneWidget);
      expect(find.textContaining('PROSSIMI 7 GIORNI'), findsNothing);
      expect(find.text('Nessun lavoro assegnato per la giornata di oggi.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an empty queue on a device that never synced does not wish anyone a good day', (
      tester,
    ) async {
      // Fresh install, offline since setup: the queue is empty because nothing was ever
      // downloaded, and "Buona giornata" would be a report on the phone, not on the technician's
      // day.
      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Nessun intervento oggi'), findsNothing);
      expect(find.text('Lavori non ancora scaricati'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('WorkQueueSection names the day its rows belong to', () {
    Future<void> insertSchedule(
      AppDatabase db, {
      required String id,
      required DateTime activityDate,
      required String title,
      required int timeStartMinutes,
    }) {
      return db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: id,
              tenantId: 'tenant-1',
              createdAt: activityDate,
              activityDate: activityDate,
              timeStartMinutes: timeStartMinutes,
              timeEndMinutes: timeStartMinutes + 60,
              userId: 'u1',
              statusId: 1,
              locationId: 'loc-1',
              title: title,
              description: '',
            ),
          );
    }

    testWidgets("every one of today's jobs is its own card, never a PROGRAMMATO tier", (
      tester,
    ) async {
      // Two jobs today. Both belong to today, so both get a focus card. The second one used to be
      // queued into a compact tier — titled RESTO DI OGGI, and before that PROGRAMMATO, the same
      // word the next-seven-days block uses — so a technician reading the screen took this
      // morning's second job as future work.
      final dayStart = _today();
      await insertSchedule(
        db,
        id: 'sched-1',
        activityDate: dayStart,
        title: 'Manutenzione ordinaria trimestrale',
        timeStartMinutes: 480,
      );
      await insertSchedule(
        db,
        id: 'sched-2',
        activityDate: dayStart,
        title: 'Manutenzione ordinaria semestrale',
        timeStartMinutes: 660,
      );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining('RESTO DI OGGI'), findsNothing);
      expect(find.textContaining('PROGRAMMATO'), findsNothing);
      // Both of today's jobs are focus cards under the today block, neither under the week.
      expect(find.text('Manutenzione ordinaria trimestrale'), findsOneWidget);
      expect(find.text('Manutenzione ordinaria semestrale'), findsOneWidget);
      expect(find.textContaining('PROSSIMI 7 GIORNI'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the day turns over at local midnight in the business zone, not at 00:00 UTC', (
      tester,
    ) async {
      // 22:30 UTC on 24 October is 00:30 in Rome on the 25th — the hour whose jobs the dashboard
      // used to miss, because it bucketed by the UTC date and called the 24th "today" for another
      // ninety minutes.
      DateTime clock() => DateTime.utc(2026, 10, 24, 22, 30);
      await insertSchedule(
        db,
        id: 'sched-25',
        activityDate: DateTime.utc(2026, 10, 25),
        title: 'Intervento del 25',
        timeStartMinutes: 480,
      );
      await insertSchedule(
        db,
        id: 'sched-24',
        activityDate: DateTime.utc(2026, 10, 24),
        title: 'Intervento del 24',
        timeStartMinutes: 480,
      );

      await tester.pumpWidget(_buildSection(db: db, clock: clock));
      await tester.pumpAndSettle();

      // Rome has already had its midnight: the 25th is today, the 24th is yesterday's work and
      // belongs nowhere on this screen.
      expect(find.text('Intervento del 25'), findsOneWidget);
      expect(find.text('DA FARE'), findsOneWidget);
      expect(find.text('Intervento del 24'), findsNothing);
      expect(find.text('Nessun lavoro assegnato per la giornata di oggi.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('WorkQueueSection an approved absence is not a job', () {
    Future<void> insertSchedule(
      AppDatabase db, {
      required String id,
      required DateTime activityDate,
      required String title,
      bool isAssenza = false,
    }) {
      return db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: id,
              tenantId: 'tenant-1',
              createdAt: activityDate,
              activityDate: activityDate,
              timeStartMinutes: 0,
              timeEndMinutes: 0,
              userId: 'u1',
              statusId: 1,
              locationId: 'loc-1',
              allDay: const Value(true),
              title: title,
              description: '',
              isAssenza: Value(isAssenza),
            ),
          );
    }

    testWidgets('a day off today reads as ASSENZA, never as a card to start', (tester) async {
      final dayStart = _today();
      await insertSchedule(
        db,
        id: 's-ferie',
        activityDate: dayStart,
        title: 'ferie',
        isAssenza: true,
      );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      // The server's own label is lowercase ("ferie", as the presenze export prints it); a category
      // reads as one only with its capital.
      expect(find.text('Ferie'), findsOneWidget);
      // The tier header renders as "<TITLE>  <count>", so it is matched by containing rather than
      // by equality.
      expect(find.textContaining('ASSENZA'), findsOneWidget);
      // No card inviting the technician to start work that does not exist.
      expect(find.text('DA FARE'), findsNothing);
      expect(find.text('Apri'), findsNothing);
      // And the day is not reported as empty: it is a day off, which is a fact about the day.
      expect(find.text('Nessun lavoro assegnato per la giornata di oggi.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a day off still shows alongside the day\'s work', (tester) async {
      final dayStart = _today();
      await insertSchedule(
        db,
        id: 's-ferie',
        activityDate: dayStart,
        title: 'permesso',
        isAssenza: true,
      );
      await insertSchedule(db, id: 's-job', activityDate: dayStart, title: 'Sostituzione caldaia');

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Permesso'), findsOneWidget);
      expect(find.textContaining('ASSENZA'), findsOneWidget);
      expect(find.text('Sostituzione caldaia'), findsOneWidget);
      expect(find.text('DA FARE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a day off next week is not counted under PROSSIMI 7 GIORNI', (tester) async {
      // Synced device, so "nothing anywhere" below is a statement about the technician's week and
      // not about a mirror that never arrived.
      await db.setLastSync(DateTime.utc(2026, 10, 1));
      final dayStart = _today();
      await insertSchedule(
        db,
        id: 's-ferie-domani',
        activityDate: dayStart.add(const Duration(days: 2)),
        title: 'ferie',
        isAssenza: true,
      );

      await tester.pumpWidget(_buildSection(db: db));
      await tester.pumpAndSettle();

      // It stays visible in Calendario; here it would read as upcoming work.
      expect(find.text('Ferie'), findsNothing);
      expect(find.textContaining('PROSSIMI 7 GIORNI'), findsNothing);
      expect(find.text('Nessun intervento oggi'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
