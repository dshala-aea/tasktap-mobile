// dart format width=100
// test/features/admin/schedules/admin_schedule_detail_screen_test.dart
//
// The redesigned Pianificazione detail keeps the existing providers and edit route but renders
// them through the wave-0 summary shell: hero + Modifica, then Sintesi (when/who/where),
// Relazioni (cliente, ticket, contratto) and Attività (nota, stato).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_detail_screen.dart';

final _now = DateTime.utc(2026, 6, 21, 10);

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedSchedule(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'Rossi Srl',
        ),
      );

  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'user-1', displayName: 'Mario Rossi'));

  await db
      .into(db.contracts)
      .insert(
        ContractsCompanion.insert(
          id: 'contract-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Full service',
          customerId: 'cust-1',
          startDate: DateTime.utc(2026, 1, 1),
        ),
      );

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
          contractId: const Value('contract-1'),
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

Widget _buildView({
  required AppDatabase db,
  String scheduleId = 'sched-1',
  Set<String> capabilities = const {'pianificazione.schedule.write'},
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome', clock: () => _now)),
      cachedEntitlementProvider.overrideWith(
        (ref) => Future.value(
          Entitlement(
            features: const {},
            capabilities: capabilities,
            seatType: 'office',
            fetchedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
      ),
    ],
    child: MaterialApp(home: AdminScheduleDetailScreen(scheduleId: scheduleId)),
  );
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

  testWidgets('renders the summary hero and the three prototype sections', (tester) async {
    await _seedSchedule(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    // Hero: title, relative-day stamp and the primary action (no FAB).
    expect(find.text('Manutenzione'), findsOneWidget);
    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('OGGI')), findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('Modifica')), findsOneWidget);
    expect(find.byType(AppFab), findsNothing);

    // Sintesi: when / who / where.
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.text('Sede Nord'), findsOneWidget);
    expect(find.textContaining('08:00 – 10:00'), findsOneWidget);

    // Relazioni: cliente, ticket, contratto.
    expect(find.text('Relazioni'), findsOneWidget);
    expect(find.text('ROSSI SRL'), findsOneWidget);
    expect(find.text('GUASTO CALDAIA'), findsOneWidget);
    expect(find.text('FULL SERVICE'), findsOneWidget);

    // Attività: note/stato.
    expect(find.text('Attività'), findsOneWidget);
    expect(find.text('IN CORSO'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('tappable relation rows carry a chevron; the plain contract row does not', (
    tester,
  ) async {
    await _seedSchedule(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    // Cliente and Ticket open a screen; Contratto is informational today.
    expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));
    expect(find.text('FULL SERVICE'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a long Note wraps instead of truncating to one line', (tester) async {
    // Note is free text. It used to go through the horizontal KeyVal row, which right-aligns the
    // value, pins it to `maxLines: 1` and ellipsizes — a note written over four lines showed only
    // its first one.
    const note =
        'Il tecnico deve accedere dal cancello laterale, chiedere del responsabile di '
        'stabilimento e compilare il modulo di ingresso. Portare i dispositivi di protezione.'
        ' Al termine lasciare copia del rapporto in portineria.';
    await _seedSchedule(db);
    await (db.update(
      db.schedules,
    )..where((s) => s.id.equals('sched-1'))).write(SchedulesCompanion(description: Value(note)));

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    final noteText = find.text(note);
    expect(noteText, findsOneWidget);
    final noteWidget = tester.widget<Text>(noteText);
    expect(noteWidget.maxLines, null);
    expect(noteWidget.overflow, isNot(TextOverflow.ellipsis));
    // A 215-character note cannot fit the card's width on a single line, so any height past one
    // line is proof it wrapped — no dependence on the test font's metrics.
    expect(tester.getSize(noteText).height, greaterThan(30));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to em-dash when assignee/sede are unresolved', (tester) async {
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

    expect(find.text('PIANIFICATO'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2)); // assignee and sede
    // Nothing to link to, so Relazioni is hidden rather than drawn empty.
    expect(find.text('Relazioni'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to squadra member names when there is no direct assignee', (
    tester,
  ) async {
    // A squadra-only schedule: the server sends the all-zeros GUID for "userId" and carries the
    // real assignees in ScheduleAssignees — isTeam=true, isDirect=false.
    const zeroGuid = '00000000-0000-0000-0000-000000000000';

    await db
        .into(db.colleagues)
        .insert(ColleaguesCompanion.insert(id: 'user-2', displayName: 'Luigi Bianchi'));
    await db
        .into(db.colleagues)
        .insert(ColleaguesCompanion.insert(id: 'user-3', displayName: 'Anna Verdi'));

    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Sud',
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
            userId: zeroGuid,
            statusId: 1,
            locationId: 'loc-2',
            title: 'Intervento squadra',
            description: '',
          ),
        );

    await db
        .into(db.scheduleAssignees)
        .insert(
          ScheduleAssigneesCompanion.insert(
            scheduleId: 'sched-team',
            userId: 'user-2',
            isTeam: const Value(true),
          ),
        );
    await db
        .into(db.scheduleAssignees)
        .insert(
          ScheduleAssigneesCompanion.insert(
            scheduleId: 'sched-team',
            userId: 'user-3',
            isTeam: const Value(true),
          ),
        );

    await tester.pumpWidget(_buildView(db: db, scheduleId: 'sched-team'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Luigi Bianchi'), findsOneWidget);
    expect(find.textContaining('Anna Verdi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  // An approved absence is materialised server-side as an ordinary schedule, so this screen must
  // not offer Modifica on it: the backend answers that edit with `absence_schedule_read_only`.
  testWidgets('an absence-owned row hides Modifica and says why', (tester) async {
    await _seedSchedule(db);
    await (db.update(db.schedules)..where((s) => s.id.equals('sched-1'))).write(
      const SchedulesCompanion(isAssenza: Value(true), title: Value('ferie')),
    );

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Modifica'), findsNothing);
    expect(find.byType(AppFab), findsNothing);
    expect(find.textContaining('Assenza approvata'), findsOneWidget);
    expect(find.textContaining('non si può modificare da qui'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('lays out at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 700) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _seedSchedule(db);
    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a job keeps its Modifica action and carries no excuse', (tester) async {
    await _seedSchedule(db);

    await tester.pumpWidget(_buildView(db: db));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('detail-hero-card')),
        matching: find.text('Modifica'),
      ),
      findsOneWidget,
    );
    expect(find.byType(AppFab), findsNothing);
    expect(find.textContaining('Assenza approvata'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('without schedule write Modifica stays visible but disabled with a reason', (
    tester,
  ) async {
    await _seedSchedule(db);

    await tester.pumpWidget(_buildView(db: db, capabilities: const {}));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('detail-hero-card')),
        matching: find.text('Modifica'),
      ),
      findsOneWidget,
    );
    expect(find.text('Non hai i permessi per questa azione.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
