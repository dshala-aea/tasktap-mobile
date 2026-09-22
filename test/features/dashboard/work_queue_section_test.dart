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

    testWidgets('an all-day Programmato schedule does not render 00:00', (tester) async {
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
      // Two schedules today: the first becomes "Da fare", pushing the second (all-day) into the
      // compact "Programmato" tier, which renders through ListRow's `meta` slot instead of the
      // focus card's badge row.
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
}
