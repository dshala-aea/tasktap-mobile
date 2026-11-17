# Dashboard Prossimi 7 giorni + Storico — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the already-computed next-7-days schedule count in the dashboard hero and add a `Storico` entry that opens a full-screen list of locally synced past schedules.

**Architecture:** Add a `pastSchedulesProvider`, a `StoricoScreen` reusing `ListaView`, and a root-level `/storico` route (Task 1). Then add the third hero readout and the `Storico` section action on the dashboard (Task 2).

**Tech Stack:** Flutter, Dart, Riverpod, Drift, go_router, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-11-dashboard-storico-design.md`

## Global Constraints

- Italian copy: counter label is exactly `PROSSIMI 7 GIORNI`, action label is exactly `Storico`, screen title is exactly `Storico`, empty title is `Nessuno storico`.
- `/storico` is a root-level, full-screen route and is **not** added to `_routeRequirements` (matches `/calendario`).
- History = all locally synced schedules with `activityDate < today` (UTC-midnight convention), newest first.
- Do not change the work-queue tiers, `PROGRAMMATO`, or Calendario's own views.
- Do not commit or push unless the user asks.

## Review Focus

Each line is pinned by a test in the owning task.

- A narrow phone at 1.3× text scale must not overflow the hero's three readouts.
- Storico must exclude today's and future schedules, not just sort them after past ones.
- A Storico row with a `ticketId` must open that ticket; a row without one must not be tappable.
- An all-day or multi-day row in the dashboard queue must name its day when it is not today, must say `Tutto il giorno`, and must never render `00:00`.
- Storico must remain reachable when the tenant has no `interventi` entitlement (same data as Dashboard/Calendario).
- `Storico` must be reachable from the dashboard without scrolling past the work queue.

---

### Task 1: Storico data, screen and route

**Files:**
- Modify: `lib/features/dashboard/dashboard_providers.dart` (add `pastSchedulesProvider`)
- Modify: `lib/features/calendario/views/lista_view.dart:19-63` (optional params)
- Create: `lib/features/dashboard/storico_screen.dart`
- Modify: `lib/core/router/app_router.dart:76-232` (`AppRoutes.storico`), `:486-495` (route), imports
- Test: `test/features/dashboard/dashboard_providers_test.dart`
- Test: `test/features/dashboard/storico_screen_test.dart` (new)
- Test: `test/core/router/app_router_route_requirement_redirect_test.dart`

**Interfaces:**
- Consumes: `Schedule` (Drift), `appDatabaseProvider`, `ListaView`, `AppRoutes.ticketDetailPath`, `rootNavigatorKey`.
- Produces: `pastSchedulesProvider` (`StreamProvider<AsyncValue<List<Schedule>>>`); `StoricoScreen`; `AppRoutes.storico` (`'/storico'`); `ListaView({bool reverseDays = false, String emptyTitle = 'Nessun intervento', String emptyBody = 'Non ci sono interventi pianificati nel periodo selezionato.', double? bottomPadding})`.

- [ ] **Step 1: Add the failing provider test**

Append to `test/features/dashboard/dashboard_providers_test.dart`:

```dart
test('pastSchedulesProvider returns past schedules newest first, excluding today', () async {
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);

  Future<void> insert(String id, DateTime date) => db.into(db.schedules).insert(
    SchedulesCompanion.insert(
      id: id,
      tenantId: 't1',
      createdAt: DateTime.utc(2026, 1, 1),
      activityDate: date,
      timeStartMinutes: 480,
      timeEndMinutes: 540,
      userId: 'u1',
      statusId: 5,
      locationId: 'l1',
      title: id,
      description: '',
    ),
  );

  await insert('yesterday', today.subtract(const Duration(days: 1)));
  await insert('lastWeek', today.subtract(const Duration(days: 7)));
  await insert('today', today);
  await insert('tomorrow', today.add(const Duration(days: 1)));

  final result = await container.read(pastSchedulesProvider.future);
  expect(result.map((s) => s.id), ['yesterday', 'lastWeek']);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_providers_test.dart --plain-name "pastSchedulesProvider returns past schedules newest first, excluding today"`
Expected: FAIL — `pastSchedulesProvider` is undefined.

- [ ] **Step 3: Add `pastSchedulesProvider`**

In `lib/features/dashboard/dashboard_providers.dart`, add below `upcomingSchedulesProvider`:

```dart
/// Every locally synced schedule before today, newest first.
/// Same UTC-midnight convention as [todaySchedulesProvider].
final pastSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final now = DateTime.now().toUtc();
  final startOfToday = DateTime.utc(now.year, now.month, now.day);
  return (db.select(db.schedules)
        ..where((s) => s.activityDate.isSmallerThanValue(startOfToday))
        ..orderBy([
          (s) => OrderingTerm.desc(s.activityDate),
          (s) => OrderingTerm.desc(s.timeStartMinutes),
        ]))
      .watch();
});
```

- [ ] **Step 4: Run the provider test to verify it passes**

Run: `flutter test test/features/dashboard/dashboard_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Extend `ListaView` without changing its callers**

In `lib/features/calendario/views/lista_view.dart`, change the constructor and fields to:

```dart
const ListaView({
  super.key,
  required this.schedules,
  this.onTapTicket,
  this.reverseDays = false,
  this.emptyTitle = 'Nessun intervento',
  this.emptyBody = 'Non ci sono interventi pianificati nel periodo selezionato.',
  this.bottomPadding,
});

final bool reverseDays;
final String emptyTitle;
final String emptyBody;
final double? bottomPadding;
```

In `build`, replace the empty state with:

```dart
return EmptyState(
  icon: LucideIcons.calendarX,
  title: emptyTitle,
  body: emptyBody,
);
```

Replace the grouped loop setup with:

```dart
final grouped = groupSchedulesByDay(schedules);
final entries = reverseDays ? grouped.entries.toList().reversed : grouped.entries;
```

and iterate `for (final entry in entries)`. Replace the list padding with:

```dart
padding: EdgeInsets.only(bottom: bottomPadding ?? context.navClearance),
```

- [ ] **Step 6: Write the failing Storico screen test**

Create `test/features/dashboard/storico_screen_test.dart` with a Drift in-memory DB, a `ProviderScope`, and a `GoRouter` that mounts `StoricoScreen` at `/` and a marker at `/ticket/:id`:

```dart
testWidgets('renders past schedules newest first and opens a linked ticket', (tester) async {
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);

  Future<void> insert(String id, String title, DateTime date, {String? ticketId}) =>
      db.into(db.schedules).insert(
        SchedulesCompanion.insert(
          id: id,
          tenantId: 't1',
          createdAt: DateTime.utc(2026, 1, 1),
          ticketId: Value(ticketId),
          activityDate: date,
          timeStartMinutes: 480,
          timeEndMinutes: 540,
          userId: 'u1',
          statusId: 5,
          locationId: 'l1',
          title: title,
          description: '',
        ),
      );

  await insert('old', 'Vecchio', today.subtract(const Duration(days: 2)));
  await insert('recent', 'Recente', today.subtract(const Duration(days: 1)), ticketId: 't-recent');
  await insert('today', 'Oggi', today);

  await tester.pumpWidget(_buildStorico(db, router));
  await tester.pumpAndSettle();

  expect(find.text('Recente'), findsOneWidget);
  expect(find.text('Vecchio'), findsOneWidget);
  expect(find.text('Oggi'), findsNothing);
  expect(
    tester.getTopLeft(find.text('Recente')).dy,
    lessThan(tester.getTopLeft(find.text('Vecchio')).dy),
  );

  await tester.tap(find.text('Recente'));
  await tester.pumpAndSettle();
  expect(find.text('TICKET-DETAIL-MARKER'), findsOneWidget);
});
```

Router in the test:

```dart
GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StoricoScreen()),
    GoRoute(
      path: '/ticket/:id',
      builder: (_, _) => const Scaffold(body: Center(child: Text('TICKET-DETAIL-MARKER'))),
    ),
  ],
)
```

Also add an empty-state test asserting `find.text('Nessuno storico')`.

- [ ] **Step 7: Run the Storico screen tests to verify they fail**

Run: `flutter test test/features/dashboard/storico_screen_test.dart`
Expected: FAIL — `StoricoScreen` is undefined.

- [ ] **Step 8: Create `StoricoScreen`**

Create `lib/features/dashboard/storico_screen.dart`:

```dart
class StoricoScreen extends ConsumerWidget {
  const StoricoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(pastSchedulesProvider);
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Storico', showBack: true),
            Expanded(
              child: past.when(
                data: (schedules) => ListaView(
                  schedules: schedules,
                  onTapTicket: (id) => context.push(AppRoutes.ticketDetailPath(id)),
                  reverseDays: true,
                  emptyTitle: 'Nessuno storico',
                  emptyBody: 'Gli interventi passati appariranno qui.',
                  bottomPadding: context.fabSafeBottom,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const EmptyState(
                  icon: LucideIcons.calendarX,
                  title: 'Storico non disponibile',
                  body: 'Impossibile leggere gli interventi passati.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Imports: `material`, `flutter_riverpod`, `go_router`, `app_lucide_icons`, `app_router`, `app_colors`, `app_palette` (for `context.colors`), `app_rack` (`fabSafeBottom`), `widgets`, `lista_view`, `dashboard_providers`.

- [ ] **Step 9: Run the Storico screen tests to verify they pass**

Run: `flutter test test/features/dashboard/storico_screen_test.dart`
Expected: PASS.

- [ ] **Step 10: Add the route (write the failing route test first)**

Add to `test/core/router/app_router_route_requirement_redirect_test.dart`, importing `StoricoScreen`:

```dart
testWidgets('/storico renders StoricoScreen without module gating', (tester) async {
  final cached = Entitlement(
    features: const {},
    capabilities: const {},
    seatType: 'field',
    fetchedAt: DateTime.utc(2026, 11, 11),
  );

  await tester.pumpWidget(
    _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
  );
  authStream.add(fakeUser);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/storico');
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(find.byType(StoricoScreen), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

Run: `flutter test test/core/router/app_router_route_requirement_redirect_test.dart --plain-name "/storico renders StoricoScreen without module gating"`
Expected: FAIL — no `/storico` route.

- [ ] **Step 11: Wire the route**

In `lib/core/router/app_router.dart`:
- Add `static const String storico = '/storico';` beside `/calendario` in `AppRoutes`.
- Add the route in the root `routes` list, beside the ticket/form root routes:

```dart
GoRoute(
  path: AppRoutes.storico,
  builder: (context, state) => const StoricoScreen(),
),
```

- Import `../../features/dashboard/storico_screen.dart`.
- Do **not** add a `_routeRequirements` entry for `/storico`.

- [ ] **Step 12: Run the route test and the Task 1 suite**

Run:
```bash
flutter test test/features/dashboard/dashboard_providers_test.dart test/features/dashboard/storico_screen_test.dart test/core/router/app_router_route_requirement_redirect_test.dart test/features/calendario
```
Expected: PASS.

---

### Task 2: Dashboard counter and Storico action

**Files:**
- Modify: `lib/features/dashboard/id_plate_hero_comp.dart:18-30` (constructor/fields), `:102-116` (readout row)
- Modify: `lib/features/dashboard/dashboard_screen.dart:78-96` (hero props), `:137-147` (section header)
- Test: `test/features/dashboard/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `AppRoutes.storico`, `StoricoScreen` route, `DashboardStats.upcomingCount`.
- Produces: `IdPlateHeroComp({required int upcomingCount, ...})`.

- [ ] **Step 1: Add the failing dashboard tests**

In `test/features/dashboard/dashboard_screen_test.dart`, add:

```dart
testWidgets('shows the next-7-days counter with a self-explanatory label', (tester) async {
  await pumpDashboard(tester);
  expect(find.text('PROSSIMI 7 GIORNI'), findsOneWidget);
  expect(find.text('0'), findsWidgets);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});

testWidgets('tapping Storico pushes AppRoutes.storico', (tester) async {
  final router = _makeQuickActionRouter(storicoMarker: true);
  await tester.pumpWidget(_buildDashboardWithRouter(db: db, repo: repo, router: router));
  await tester.pump();
  authStream.add(fakeUser);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  await tester.tap(find.text('Storico'));
  await tester.pumpAndSettle();
  expect(find.text('STORICO-SCREEN-MARKER'), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});

testWidgets('hero readouts do not overflow at 1.3x text scale on a narrow phone', (
  tester,
) async {
  tester.view.physicalSize = const Size(720, 1440);
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await pumpDashboard(tester);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

Extend `_makeQuickActionRouter` with an optional `bool storicoMarker = false` and, when true, a route:

```dart
GoRoute(
  path: AppRoutes.storico,
  builder: (_, _) => const Scaffold(body: Center(child: Text('STORICO-SCREEN-MARKER'))),
),
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
flutter test test/features/dashboard/dashboard_screen_test.dart --plain-name "PROSSIMI 7 GIORNI"
flutter test test/features/dashboard/dashboard_screen_test.dart --plain-name "tapping Storico pushes"
```
Expected: FAIL — label absent / no `Storico` button.

- [ ] **Step 3: Add `upcomingCount` and wrap the readouts**

In `lib/features/dashboard/id_plate_hero_comp.dart`:
- Add `required this.upcomingCount` to the constructor and `final int upcomingCount;` beside `completedCount`.
- Replace the readout `Row` with a `Wrap`:

```dart
Wrap(
  spacing: 28,
  runSpacing: 8,
  children: [
    _Readout(value: '$todayCount', label: 'INTERVENTI OGGI', accent: false),
    _Readout(value: '$remaining', label: 'DA FARE', accent: remaining > 0),
    _Readout(value: '$upcomingCount', label: 'PROSSIMI 7 GIORNI', accent: false),
  ],
)
```

- [ ] **Step 4: Wire the dashboard**

In `lib/features/dashboard/dashboard_screen.dart`:
- Pass `upcomingCount: stats.upcomingCount` to `IdPlateHeroComp`.
- Add to the `Oggi` `SectionTitle`:

```dart
action: TextButton(
  onPressed: () => context.push(AppRoutes.storico),
  child: const Text('Storico'),
),
```

- [ ] **Step 5: Run the dashboard tests to verify they pass**

Run: `flutter test test/features/dashboard/dashboard_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full Task 2 suite and analysis**

Run:
```bash
flutter test test/features/dashboard test/features/calendario test/core/router
flutter analyze
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`.

---

### Task 3: Day labels for all-day and multi-day rows in the dashboard queue

**Files:**
- Modify: `lib/features/dashboard/work_queue_section.dart:110-150` (`_resolveRow`/label helper), `:215-235` (focus-card time text), `:330-345` (compact-row meta)
- Test: `test/features/dashboard/work_queue_section_test.dart`

**Interfaces:**
- Consumes: `Schedule.activityDate`, `Schedule.timeStartMinutes`, `Schedule.allDay`, `_weekdayFmt`.
- Produces: `String _scheduleDayLabel(DateTime activityDate, int timeStartMinutes, {required bool allDay})`; `_RowContent.timeLabel` becomes non-nullable `String`.

- [ ] **Step 1: Extend the failing all-day tests**

In `test/features/dashboard/work_queue_section_test.dart`:
- In both existing all-day tests, add `expect(find.textContaining('Tutto il giorno'), findsOneWidget);`
- Add:

```dart
testWidgets('a future all-day schedule names its day', (tester) async {
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final future = today.add(const Duration(days: 2));

  await db.into(db.schedules).insert(
    SchedulesCompanion.insert(
      id: 'sched-future-allday',
      tenantId: 'tenant-1',
      createdAt: today,
      activityDate: future,
      timeStartMinutes: 0,
      timeEndMinutes: 0,
      userId: 'u1',
      statusId: 1,
      locationId: 'loc-1',
      allDay: const Value(true),
      title: 'Blocco futuro',
      description: '',
    ),
  );

  await tester.pumpWidget(_buildSection(db: db));
  await tester.pumpAndSettle();

  final day = DateFormat('EEE d', 'it').format(future);
  final label = '${day[0].toUpperCase()}${day.substring(1)}';
  expect(find.textContaining('$label · Tutto il giorno'), findsOneWidget);
  expect(find.textContaining('00:00'), findsNothing);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

- Add the multi-day run test:

```dart
testWidgets('consecutive multi-day all-day rows show distinct days', (tester) async {
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final first = today.add(const Duration(days: 1));
  final second = today.add(const Duration(days: 2));

  for (final (id, day) in [('day-1', first), ('day-2', second)]) {
    await db.into(db.schedules).insert(
      SchedulesCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: today,
        activityDate: day,
        timeStartMinutes: 0,
        timeEndMinutes: 0,
        userId: 'u1',
        statusId: 1,
        locationId: 'loc-1',
        allDay: const Value(true),
        title: 'Cantiere multi-giorno',
        description: '',
      ),
    );
  }

  await tester.pumpWidget(_buildSection(db: db));
  await tester.pumpAndSettle();

  String label(DateTime d) {
    final s = DateFormat('EEE d', 'it').format(d);
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  expect(find.textContaining('${label(first)} · Tutto il giorno'), findsOneWidget);
  expect(find.textContaining('${label(second)} · Tutto il giorno'), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

Add `import 'package:intl/intl.dart';` if absent.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/dashboard/work_queue_section_test.dart`
Expected: FAIL — `Tutto il giorno` / future day labels are absent.

- [ ] **Step 3: Implement one day-label function**

In `lib/features/dashboard/work_queue_section.dart`:

- Replace `_dateQualifiedTimeLabel` with:

```dart
String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _scheduleDayLabel(
  DateTime activityDate,
  int timeStartMinutes, {
  required bool allDay,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(activityDate.year, activityDate.month, activityDate.day);
  final time = '${_twoDigits(timeStartMinutes ~/ 60)}:${_twoDigits(timeStartMinutes % 60)}';

  if (day == today) return allDay ? 'Tutto il giorno' : time;

  final raw = _weekdayFmt.format(day);
  final label = '${raw[0].toUpperCase()}${raw.substring(1)}';
  return allDay ? '$label · Tutto il giorno' : '$label, $time';
}
```

- In `_resolveRow`, replace the `timeLabel` expression with:

```dart
final timeLabel = _scheduleDayLabel(
  schedule.activityDate,
  schedule.timeStartMinutes,
  allDay: schedule.allDay,
);
```

- Change `_RowContent.timeLabel` to `final String timeLabel;` and update its doc comment (it no longer exists to hide all-day rows).
- In `_FocusCard`, render the time unconditionally:
```dart
Text(
  '  ·  ${row.timeLabel}',
  style: TextStyle(
    fontFamily: 'Archivo',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: c.inkMuted,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
),
```
- In `_CompactRow`, replace the `meta` ternary with:
```dart
meta: Text(
  row.timeLabel,
  style: TextStyle(
    fontFamily: 'Archivo',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: context.colors.inkMuted,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
),
```

- [ ] **Step 4: Run the queue tests to verify they pass**

Run: `flutter test test/features/dashboard/work_queue_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the dashboard suite and analysis**

Run:
```bash
flutter test test/features/dashboard test/features/calendario test/core/router
flutter analyze
```
Expected: all PASS; `No issues found!`.

- [ ] **Step 6: Report, do not commit**

Report the changed files and test/analyze output. Do not commit or push.
