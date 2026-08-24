// dart format width=100
// test/features/admin/schedules/admin_schedule_detail_screen_test.dart
//
// AdminScheduleDetailScreen used to render only title/date/time/notes — even though the DTO
// (Schedule.userId/locationId/statusId/ticketId, already in app_database.dart) carried assignee,
// sede, status and linked-ticket data all along. Confirms the detail body actually resolves and
// renders those fields via the same lookups the rest of the app already uses
// (colleagueNameProvider, allLocationsProvider, scheduleStatusName, allTicketsProvider).

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_detail_screen.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedSchedule(AppDatabase db) async {
  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'user-1', displayName: 'Mario Rossi'));

  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'loc-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: 'cust-1',
          name: 'Sede Nord',
        ),
      );

  await db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: 'ticket-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          title: 'Guasto caldaia',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
        ),
      );

  await db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: 'sched-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          activityDate: DateTime.utc(2026, 6, 21),
          timeStartMinutes: 480,
          timeEndMinutes: 600,
          userId: 'user-1',
          statusId: 2, // "In corso"
          locationId: 'loc-1',
          title: 'Manutenzione',
          description: '',
          ticketId: const Value('ticket-1'),
        ),
      );
}

Widget _buildView({required AppDatabase db, String scheduleId = 'sched-1'}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: AdminScheduleDetailScreen(scheduleId: scheduleId)),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('renders assignee, sede, status and linked ticket', (tester) async {
    await _seedSchedule(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.text('Sede Nord'), findsOneWidget);
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Guasto caldaia'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to em-dash when assignee/sede/ticket are unresolved', (tester) async {
    // Schedule referencing ids the local mirror has never synced.
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            activityDate: DateTime.utc(2026, 6, 21),
            timeStartMinutes: 480,
            timeEndMinutes: 600,
            userId: 'ghost-user',
            statusId: 999, // unmapped -> scheduleStatusName falls through to "Pianificato"
            locationId: 'ghost-loc',
            title: 'Intervento fantasma',
            description: '',
          ),
        );

    await tester.pumpWidget(_buildView(db: db, scheduleId: 'sched-2'));
    await tester.pumpAndSettle();

    expect(find.text('Pianificato'), findsOneWidget);
    expect(find.text('—'), findsWidgets); // assignee, sede, and linked ticket all unresolved

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
