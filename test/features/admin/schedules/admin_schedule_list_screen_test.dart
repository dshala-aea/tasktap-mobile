// dart format width=100
// test/features/admin/schedules/admin_schedule_list_screen_test.dart
//
// Gap 9 of the feature audit: the squadra detail screen's "Pianificazioni squadra" header action
// navigates here with `initialSquadraId` (routed through `extra` on the `pianificazioni` route),
// which should pre-apply the existing squadra filter — landing straight on that squadra's own
// schedule instead of an unfiltered list the admin then has to filter by hand.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_list_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({required this.squadraMembers}) : super(Dio());

  final Map<String, List<String>> squadraMembers;

  @override
  Future<List<Map<String, dynamic>>> fetchSquadre() async => [
    for (final id in squadraMembers.keys) {'id': id, 'nome': 'Squadra $id'},
  ];

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async => {
    'squadra': {'id': id, 'nome': 'Squadra $id'},
    'membri': [
      for (final userId in squadraMembers[id] ?? const <String>[]) {'userId': userId, 'ruolo': 0},
    ],
  };
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedSchedules(AppDatabase db) async {
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
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: 'sched-team',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          activityDate: DateTime.utc(2026, 6, 21),
          timeStartMinutes: 480,
          timeEndMinutes: 600,
          userId: '00000000-0000-0000-0000-000000000000',
          statusId: 1,
          locationId: 'loc-1',
          title: 'Intervento squadra Nord',
          description: '',
        ),
      );
  await db
      .into(db.scheduleAssignees)
      .insert(
        ScheduleAssigneesCompanion.insert(
          scheduleId: 'sched-team',
          userId: 'user-1',
          isTeam: const Value(true),
        ),
      );

  await db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: 'sched-other',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          activityDate: DateTime.utc(2026, 6, 22),
          timeStartMinutes: 480,
          timeEndMinutes: 600,
          userId: '00000000-0000-0000-0000-000000000000',
          statusId: 1,
          locationId: 'loc-1',
          title: 'Intervento altra squadra',
          description: '',
        ),
      );
  await db
      .into(db.scheduleAssignees)
      .insert(
        ScheduleAssigneesCompanion.insert(
          scheduleId: 'sched-other',
          userId: 'user-2',
          isTeam: const Value(true),
        ),
      );
}

Widget _buildView({required AppDatabase db, String? initialSquadraId}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      adminApiClientProvider.overrideWithValue(
        _FakeAdminApiClient(
          squadraMembers: {
            'sq-1': ['user-1'],
          },
        ),
      ),
    ],
    child: MaterialApp(home: AdminScheduleListScreen(initialSquadraId: initialSquadraId)),
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

  testWidgets('with no initial squadra, lands unfiltered on the calendar tab', (tester) async {
    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Rimuovi filtri (1)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('initialSquadraId pre-applies the squadra filter and lands on elenco', (
    tester,
  ) async {
    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db, initialSquadraId: 'sq-1'));
    await tester.pumpAndSettle();

    // One filter (squadra) pre-applied, surfaced by the "clear filters" chip.
    expect(find.text('Rimuovi filtri (1)'), findsOneWidget);

    // Landed on the elenco tab (not the calendar grid), showing only this squadra's schedule.
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Intervento altra squadra'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
