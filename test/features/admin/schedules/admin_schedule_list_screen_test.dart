// dart format width=100
// test/features/admin/schedules/admin_schedule_list_screen_test.dart
//
// The redesigned Pianificazioni list keeps the calendar/elenco toggle, the filter sheet and the
// squadra route pre-filter, and adds the prototype's grouped elenco plus its Oggi/Settimana/
// Futuro/Tutte date presets. These tests pin that behaviour — including the planned-hours defect
// the old rows had (a midnight activityDate printed the device's UTC offset as its clock).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
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

/// Wednesday 17 June 2026, 12:00 Rome. A mid-week day makes Oggi / Questa settimana / Futuro
/// distinct for the seeded rows below.
final _now = DateTime.utc(2026, 6, 17, 10);

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

  Future<void> schedule({
    required String id,
    required DateTime date,
    required String title,
    int start = 480,
    int end = 600,
    String userId = '00000000-0000-0000-0000-000000000000',
    bool allDay = false,
  }) => db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          activityDate: date,
          timeStartMinutes: start,
          timeEndMinutes: end,
          userId: userId,
          statusId: 1,
          locationId: 'loc-1',
          allDay: Value(allDay),
          title: title,
          description: '',
        ),
      );

  await schedule(
    id: 'sched-team',
    date: DateTime.utc(2026, 6, 17),
    title: 'Intervento squadra Nord',
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

  await schedule(
    id: 'sched-other',
    date: DateTime.utc(2026, 6, 18),
    title: 'Intervento altra squadra',
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
      businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome', clock: () => _now)),
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

Future<void> _openElenco(WidgetTester tester) async {
  await tester.tap(find.text('Elenco'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
    ensureTimeZonesInitialized();
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('with no initial squadra, lands unfiltered on the calendar tab', (tester) async {
    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Calendario'), findsOneWidget);
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

    // One filter (squadra) pre-applied, surfaced by the "clear filters" row.
    expect(find.text('Rimuovi filtri (1)'), findsOneWidget);

    // Landed on the elenco tab (not the calendar grid), showing only this squadra's schedule.
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Intervento altra squadra'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('elenco rows show the planned hours, not midnight\'s offset', (tester) async {
    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    // Seeded 480→600. The old defect formatted the midnight activityDate through `toLocal()`,
    // printing the device's offset from UTC ("02:00" in CEST) whatever hours were planned.
    expect(find.text('08:00 – 10:00 · Sede Nord'), findsOneWidget);
    expect(find.textContaining('02:00'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('an all-day elenco row says "Tutto il giorno", never 00:00', (tester) async {
    await _seedSchedules(db);
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-allday',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            activityDate: DateTime.utc(2026, 6, 17),
            timeStartMinutes: 0,
            timeEndMinutes: 0,
            userId: '00000000-0000-0000-0000-000000000000',
            statusId: 1,
            locationId: 'loc-1',
            allDay: const Value(true),
            title: 'Intervento tutto il giorno',
            description: '',
          ),
        );
    await db
        .into(db.scheduleAssignees)
        .insert(
          ScheduleAssigneesCompanion.insert(
            scheduleId: 'sched-allday',
            userId: 'user-1',
            isTeam: const Value(true),
          ),
        );

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    expect(find.text('Intervento tutto il giorno'), findsOneWidget);
    expect(find.textContaining('Tutto il giorno'), findsOneWidget);
    expect(find.textContaining('00:00'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the group headings and summary follow the loaded rows', (tester) async {
    await _seedSchedules(db);

    // One future and one past row, outside the seeded today/tomorrow pair.
    Future<void> add(String id, DateTime date, String title) => db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            activityDate: date,
            timeStartMinutes: 540,
            timeEndMinutes: 600,
            userId: 'user-2',
            statusId: 1,
            locationId: 'loc-1',
            title: title,
            description: '',
          ),
        );
    await add('sched-future', DateTime.utc(2026, 6, 24), 'Futuro lontano');
    await add('sched-past', DateTime.utc(2026, 6, 10), 'Passato recente');

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Questa settimana'), findsOneWidget);
    expect(find.text('Futuro'), findsOneWidget);
    // The mockup has no Passato group; it exists only so `Tutte` keeps showing past work.
    expect(find.text('Passato'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('4 IMPEGNI'), findsOneWidget);
    expect(find.text('1 OGGI'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Oggi / Settimana / Futuro / Tutte map to the date facet', (tester) async {
    await _seedSchedules(db);
    Future<void> add(String id, DateTime date, String title) => db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            activityDate: date,
            timeStartMinutes: 540,
            timeEndMinutes: 600,
            userId: 'user-2',
            statusId: 1,
            locationId: 'loc-1',
            title: title,
            description: '',
          ),
        );
    await add('sched-future', DateTime.utc(2026, 6, 24), 'Futuro lontano');
    await add('sched-past', DateTime.utc(2026, 6, 10), 'Passato recente');

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    // Tutte is the default so the calendar keeps showing the whole month.
    expect(find.text('Passato recente'), findsOneWidget);

    await tester.tap(find.text('OGGI'));
    await tester.pumpAndSettle();
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Intervento altra squadra'), findsNothing);
    expect(find.text('Futuro lontano'), findsNothing);
    expect(find.text('Passato recente'), findsNothing);
    expect(find.text('Questa settimana'), findsNothing);

    await tester.tap(find.text('SETTIMANA'));
    await tester.pumpAndSettle();
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Intervento altra squadra'), findsOneWidget);
    expect(find.text('Futuro lontano'), findsNothing);
    expect(find.text('Passato recente'), findsNothing);

    await tester.tap(find.text('FUTURO'));
    await tester.pumpAndSettle();
    expect(find.text('Futuro lontano'), findsOneWidget);
    expect(find.text('Intervento squadra Nord'), findsNothing);
    expect(find.text('Intervento altra squadra'), findsNothing);
    expect(find.text('Passato recente'), findsNothing);

    await tester.tap(find.text('TUTTE'));
    await tester.pumpAndSettle();
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Futuro lontano'), findsOneWidget);
    expect(find.text('Passato recente'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('search matches title, sede, technician and date', (tester) async {
    await _seedSchedules(db);
    await db
        .into(db.colleagues)
        .insert(ColleaguesCompanion.insert(id: 'user-1', displayName: 'Daniel Shala'));

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    Future<void> query(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    await query('Daniel');
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Intervento altra squadra'), findsNothing);

    await query('Sede Nord');
    expect(find.text('Intervento squadra Nord'), findsOneWidget);

    await query('17 giu');
    expect(find.text('Intervento squadra Nord'), findsOneWidget);
    expect(find.text('Intervento altra squadra'), findsNothing);

    await query('nomatch');
    expect(find.text('Nessun risultato'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the Filtri sheet keeps every facet', (tester) async {
    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();

    expect(find.text('DA'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('STATO'), findsOneWidget);
    expect(find.text('TECNICO'), findsOneWidget);
    expect(find.text('SQUADRA'), findsOneWidget);
    expect(find.text('TICKET'), findsOneWidget);
    expect(find.text('Azzera'), findsOneWidget);
    expect(find.text('Applica'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('lays out at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 700) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the clear-filters action is a 44px target', (tester) async {
    await _seedSchedules(db);
    await tester.pumpWidget(_buildView(db: db, initialSquadraId: 'sq-1'));
    await tester.pumpAndSettle();

    final target = find.byKey(const Key('clear-schedule-filters'));
    expect(target, findsOneWidget);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the current week stays under Questa settimana, even Monday/Tuesday', (tester) async {
    await _seedSchedules(db);
    // Monday of this week (today is Wednesday 17 June 2026) used to fall into `Passato`.
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-monday',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            activityDate: DateTime.utc(2026, 6, 15),
            timeStartMinutes: 540,
            timeEndMinutes: 600,
            userId: 'user-2',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Lunedì corrente',
            description: '',
          ),
        );

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();
    await _openElenco(tester);

    expect(find.text('Lunedì corrente'), findsOneWidget);
    expect(find.text('Questa settimana'), findsOneWidget);
    // No previous-week rows were seeded, so a Passato group here would mean Monday was misfiled.
    expect(find.text('Passato'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('does not mount its own offline banner (HomeShell owns it)', (tester) async {
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(find.byType(OfflineSyncBanner), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the header offers Nuovo and no floating create button', (tester) async {
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(find.text('NUOVO'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  // The elenco's empty state distinguishes three cases; the mirror-empty one is not a fact about
  // the tenant until a sync has landed.
  testWidgets('never-synced empty mirror says pianificazioni were not downloaded', (tester) async {
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    await _openElenco(tester);

    expect(find.text('Pianificazioni non ancora scaricate'), findsOneWidget);
    expect(find.text('Nessuna pianificazione'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a synced, genuinely empty list offers the create action instead', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    await _openElenco(tester);

    expect(find.text('Nessuna pianificazione'), findsOneWidget);
    expect(find.text('Pianificazioni non ancora scaricate'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
