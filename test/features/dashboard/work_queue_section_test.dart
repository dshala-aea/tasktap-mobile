import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/dashboard/work_queue_section.dart';

Widget _buildSection({required AppDatabase db}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: Scaffold(body: WorkQueueSection())),
  );
}

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
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
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
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
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
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
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
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
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
}
