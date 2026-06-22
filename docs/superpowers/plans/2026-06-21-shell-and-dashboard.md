# Shell (5-Tab) + Dashboard Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4-tab `NavigationBar` shell with a go_router `StatefulShellRoute` + design-system `AppBottomNav` (5 tabs: Dashboard / Ticket / Timbra / Calendario / Altro), and build the Dashboard screen wired to real Riverpod providers, plus widget tests.

**Architecture:**
- Shell: `HomeShell` widget is gutted and rebuilt to use `AppBottomNav` from `lib/core/widgets/bottom_nav.dart`. Router gets 5 `StatefulShellBranch` entries. Old screens (Oggi, Interventi, Rapportini, Profilo) are re-routed: Dashboard replaces Oggi as branch 0; Ticket reuses InterventiScreen as branch 1; Timbra/Calendario/Altro get thin placeholder screens (branches 2–4). Profilo and Rapportini screens stay accessible via the Altro branch routes.
- Dashboard screen: a single `ConsumerWidget` in `lib/features/dashboard/dashboard_screen.dart` that assembles existing core widgets in a `CustomScrollView` (so the dark Hero scrolls away). All data comes from existing providers in `lib/presentation/providers/schedule_providers.dart` and `lib/presentation/providers/auth_providers.dart`.
- Tests: `test/features/dashboard/dashboard_screen_test.dart` (mock providers) + `test/presentation/app_shell_test.dart` is updated for 5 tabs + `AppBottomNav`.

**Tech Stack:** Flutter / Dart 3.11, Riverpod 2.x, go_router 14.x, Drift (already set up), lucide_icons, google_fonts.

## Global Constraints

- `mobile/` is its own git repo — all file paths are relative to `/mnt/d/AEA/Sviluppi/TaskTap/mobile/`.
- Run Flutter with `cmd.exe /c flutter.bat <args>` from inside `mobile/`.
- No Android SDK — verify with `flutter analyze` + `flutter test` only.
- After every task, `flutter analyze` must be clean and `flutter test` must stay ≥ 301 green.
- Reuse existing widgets from `lib/core/widgets/widgets.dart` — do NOT duplicate them.
- ≥44 pt touch targets, safe areas, press feedback throughout.
- Italian UI copy.
- No emoji in code.
- ONE commit at the end (the task says "one commit"), but run analyze+test after each task to catch regressions early.
- NEVER paste file contents in output messages (32k output limit risk).

---

## File Map

### Created
- `lib/features/dashboard/dashboard_screen.dart` — Dashboard screen widget (Hero + ActiveJobCard + StatsGrid + QuickActions + Prossimi interventi section).
- `lib/features/dashboard/dashboard_providers.dart` — Derived Riverpod providers: `inProgressSchedulesProvider`, `completedTodaySchedulesProvider`, `upcomingSchedulesProvider` (next 7 days excluding today), computed stats.
- `lib/presentation/screens/placeholder/timbra_placeholder_screen.dart` — Minimal dark placeholder for Timbra tab.
- `lib/presentation/screens/placeholder/calendario_placeholder_screen.dart` — Minimal placeholder for Calendario tab.
- `lib/presentation/screens/placeholder/altro_screen.dart` — Minimal Altro hub screen with links to Rapportini + Profilo.
- `test/features/dashboard/dashboard_screen_test.dart` — Widget tests (active state + empty state + mock providers).

### Modified
- `lib/core/router/app_router.dart` — Replace 4 branches with 5 branches; update `AppRoutes` constants; add `/dashboard`, `/ticket`, `/timbra`, `/calendario`, `/altro` and sub-routes `/altro/rapportini`, `/altro/rapportini/editor/:reportId`, `/altro/profilo`.
- `lib/presentation/screens/home/home_shell.dart` — Replace `NavigationBar` / `_AppBottomNav` with `AppBottomNav` from `lib/core/widgets/bottom_nav.dart`.
- `test/presentation/app_shell_test.dart` — Update assertions: `NavigationBar` → `AppBottomNav`, 4 destinations → 5 tab labels.

---

## Task 1 — Dashboard providers

**Files:**
- Create: `lib/features/dashboard/dashboard_providers.dart`
- Reads: `lib/presentation/providers/schedule_providers.dart` (existing `todaySchedulesProvider`, `weekSchedulesProvider`)
- Reads: `lib/data/local/app_database.dart` for `Schedule` type

**Interfaces:**
- Produces:
  - `inProgressSchedulesProvider` → `StreamProvider.autoDispose<List<Schedule>>` — today's schedules with `statusId == 2` (In corso).
  - `completedTodaySchedulesProvider` → `StreamProvider.autoDispose<List<Schedule>>` — today's schedules with `statusId == 5` (Completato).
  - `upcomingSchedulesProvider` → `StreamProvider.autoDispose<List<Schedule>>` — schedules in [today+1, today+8) from weekSchedulesProvider minus today.
  - `dashboardStatsProvider` → `Provider.autoDispose<DashboardStats>` — plain class with `todayCount`, `inProgressCount`, `completedCount`, `upcomingCount`.

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/dashboard_providers_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/dashboard/dashboard_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('inProgressSchedulesProvider emits empty list when db empty', () async {
    final result = await container
        .read(inProgressSchedulesProvider.future);
    expect(result, isEmpty);
  });

  test('dashboardStatsProvider returns zeros when db empty', () {
    final stats = container.read(dashboardStatsProvider);
    expect(stats.todayCount, 0);
    expect(stats.inProgressCount, 0);
    expect(stats.completedCount, 0);
    expect(stats.upcomingCount, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cmd.exe /c flutter.bat test test/features/dashboard/dashboard_providers_test.dart -v
```
Expected: FAIL with "Target of URI doesn't exist" (file not created yet).

- [ ] **Step 3: Create `lib/features/dashboard/dashboard_providers.dart`**

```dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../presentation/providers/schedule_providers.dart';

/// Dashboard-derived stats (plain class, computed synchronously from async values).
class DashboardStats {
  const DashboardStats({
    required this.todayCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.upcomingCount,
  });

  final int todayCount;
  final int inProgressCount;
  final int completedCount;
  final int upcomingCount;
}

/// statusId == 2 → "In corso" (from backend WorkScheduleStatusEnum).
const int _kStatusInProgress = 2;

/// statusId == 5 → "Completato".
const int _kStatusCompleted = 5;

/// Today's schedules with statusId == 2 (In corso).
final inProgressSchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day).toUtc();
  final end = start.add(const Duration(days: 1));
  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(start) &
              s.activityDate.isSmallerThanValue(end) &
              s.statusId.equals(_kStatusInProgress),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.timeStartMinutes)]))
      .watch();
});

/// Today's schedules with statusId == 5 (Completato).
final completedTodaySchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day).toUtc();
  final end = start.add(const Duration(days: 1));
  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(start) &
              s.activityDate.isSmallerThanValue(end) &
              s.statusId.equals(_kStatusCompleted),
        ))
      .watch();
});

/// Schedules in [today+1 day, today+8 days) — next 7 days, excluding today.
final upcomingSchedulesProvider =
    StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = DateTime.now();
  final start =
      DateTime(today.year, today.month, today.day).toUtc().add(const Duration(days: 1));
  final end =
      DateTime(today.year, today.month, today.day).toUtc().add(const Duration(days: 8));
  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(start) &
              s.activityDate.isSmallerThanValue(end),
        )
        ..orderBy([
          (s) => OrderingTerm.asc(s.activityDate),
          (s) => OrderingTerm.asc(s.timeStartMinutes),
        ]))
      .watch();
});

/// Computed 2×2 stats from the three stream providers above + todaySchedulesProvider.
/// Uses [AsyncValue.valueOrNull] so it reads synchronously without blocking.
final dashboardStatsProvider = Provider.autoDispose<DashboardStats>((ref) {
  final today = ref.watch(todaySchedulesProvider).valueOrNull ?? [];
  final inProgress = ref.watch(inProgressSchedulesProvider).valueOrNull ?? [];
  final completed = ref.watch(completedTodaySchedulesProvider).valueOrNull ?? [];
  final upcoming = ref.watch(upcomingSchedulesProvider).valueOrNull ?? [];
  return DashboardStats(
    todayCount: today.length,
    inProgressCount: inProgress.length,
    completedCount: completed.length,
    upcomingCount: upcoming.length,
  );
});
```

- [ ] **Step 4: Run providers test to verify it passes**

```
cmd.exe /c flutter.bat test test/features/dashboard/dashboard_providers_test.dart -v
```
Expected: PASS (2 tests).

- [ ] **Step 5: Run analyze to confirm no issues**

```
cmd.exe /c flutter.bat analyze
```
Expected: "No issues found."

---

## Task 2 — Dashboard screen widget

**Files:**
- Create: `lib/features/dashboard/dashboard_screen.dart`
- Reads: `lib/core/widgets/widgets.dart` (all existing core widgets)
- Reads: `lib/presentation/providers/auth_providers.dart` (`currentUserProvider`)
- Reads: `lib/features/dashboard/dashboard_providers.dart` (Task 1)
- Reads: `lib/presentation/providers/schedule_providers.dart` (todaySchedulesProvider, weekSchedulesProvider)
- Reads: `lib/data/local/app_database.dart` (`Schedule` type, `Customer`, `Location`)

**Interfaces:**
- Consumes: `currentUserProvider` → `AuthUser?`, `inProgressSchedulesProvider`, `dashboardStatsProvider`, `upcomingSchedulesProvider`, `customerByIdProvider`, `locationByIdProvider`
- Produces: `DashboardScreen` — `ConsumerWidget`, no required constructor params.

**Design notes (from DESIGN-SCREENS.md Phase P2):**
- `DashboardHero` wraps hero section; pass `userName` from `currentUserProvider?.displayName ?? currentUserProvider?.email ?? 'Tecnico'`.
- Hero actions: two `HeaderIconBtn(glass: true)` — bell (LucideIcons.bell) and user (LucideIcons.user).
- Inside hero: if `inProgressSchedules` is non-empty, show the first as `ActiveJobCard` with `elapsed: '00:00:00'` (timer phase is later); show `EmptyState` (in glass card) when empty.
- Below hero (white area): `StatsGrid` 2×2 → "Interventi\noggi" / "In corso" / "Completati" / "Prossimi".
- `QuickActions` row: 4 `QuickAction` widgets — Storico (LucideIcons.history), Nuova pianificazione (LucideIcons.calendarPlus), Nuovo ticket (LucideIcons.ticket), Nuovo report (LucideIcons.fileText). All `onTap: null` for now (real nav in later phase).
- `SectionTitle('Prossimi interventi')` + list of `_UpcomingItem` cards (AppCard.pressable) for `upcomingSchedulesProvider`.
- Use `CustomScrollView` with `SliverToBoxAdapter` wrappers so the full page scrolls.
- Wrap everything in `Scaffold(backgroundColor: AppColors.BG2, body: ...)`. No AppBar (hero replaces it).

- [ ] **Step 1: Write the failing widget test**

Create `test/features/dashboard/dashboard_screen_test.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/dashboard/dashboard_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}
class MockDio extends Mock implements Dio {}

Widget _buildDashboard({
  required AppDatabase db,
  required MockAuthRepository repo,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
    ],
    child: const MaterialApp(home: DashboardScreen()),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
    Future.microtask(() => authStream.add(fakeUser));
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  group('DashboardScreen', () {
    testWidgets('renders hero with user email when no displayName', (tester) async {
      await tester.pumpWidget(_buildDashboard(db: db, repo: repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('mario@tasktap.io'), findsOneWidget);
      expect(find.text('Bentornato'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatsGrid with 4 cells', (tester) async {
      await tester.pumpWidget(_buildDashboard(db: db, repo: repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(StatsGrid), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows 4 QuickAction widgets', (tester) async {
      await tester.pumpWidget(_buildDashboard(db: db, repo: repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(QuickAction), findsNWidgets(4));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows empty state when no active jobs', (tester) async {
      await tester.pumpWidget(_buildDashboard(db: db, repo: repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(EmptyState), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows ActiveJobCard when in-progress schedule present',
        (tester) async {
      // Insert a today in-progress schedule into the DB.
      final today = DateTime.now().toUtc();
      final dayStart = DateTime(today.year, today.month, today.day).toUtc();
      await db.into(db.schedules).insert(SchedulesCompanion.insert(
            id: 'sched-1',
            tenantId: 'tenant-1',
            createdAt: dayStart,
            activityDate: dayStart,
            timeStartMinutes: 480,
            timeEndMinutes: 1020,
            userId: 'u1',
            statusId: 2, // In corso
            locationId: 'loc-1',
            title: 'Sostituzione caldaia',
            description: '',
          ));

      await tester.pumpWidget(_buildDashboard(db: db, repo: repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(ActiveJobCard), findsOneWidget);
      expect(find.text('Sostituzione caldaia'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cmd.exe /c flutter.bat test test/features/dashboard/dashboard_screen_test.dart -v
```
Expected: FAIL with "Target of URI doesn't exist: 'package:tasktap_mobile/features/dashboard/dashboard_screen.dart'".

- [ ] **Step 3: Create `lib/features/dashboard/dashboard_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.displayName ?? user?.email ?? 'Tecnico';

    final inProgressAsync = ref.watch(inProgressSchedulesProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final upcomingAsync = ref.watch(upcomingSchedulesProvider);

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: CustomScrollView(
        slivers: [
          // ── Hero ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: DashboardHero(
              userName: userName,
              actions: [
                HeaderIconBtn(
                  icon: LucideIcons.bell,
                  glass: true,
                  onTap: () {},
                ),
                HeaderIconBtn(
                  icon: LucideIcons.user,
                  glass: true,
                  onTap: () {},
                ),
              ],
              child: inProgressAsync.when(
                data: (jobs) => jobs.isEmpty
                    ? _NoActiveJobGlass()
                    : _ActiveJobSection(jobs: jobs, ref: ref),
                loading: () => const _HeroLoadingIndicator(),
                error: (_, __) => _NoActiveJobGlass(),
              ),
            ),
          ),

          // ── Stats 2×2 ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 20, 19, 0),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: StatsGrid(
                  items: [
                    StatItem(
                        label: 'Interventi\noggi',
                        value: stats.todayCount.toString()),
                    StatItem(
                        label: 'In corso',
                        value: stats.inProgressCount.toString()),
                    StatItem(
                        label: 'Completati',
                        value: stats.completedCount.toString()),
                    StatItem(
                        label: 'Prossimi',
                        value: stats.upcomingCount.toString()),
                  ],
                ),
              ),
            ),
          ),

          // ── Quick Actions ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 20, 19, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  QuickAction(
                    icon: LucideIcons.history,
                    label: 'Storico',
                  ),
                  QuickAction(
                    icon: LucideIcons.calendarPlus,
                    label: 'Nuova\npianificazione',
                  ),
                  QuickAction(
                    icon: LucideIcons.ticket,
                    label: 'Nuovo\nticket',
                  ),
                  QuickAction(
                    icon: LucideIcons.fileText,
                    label: 'Nuovo\nreport',
                  ),
                ],
              ),
            ),
          ),

          // ── Prossimi interventi ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: SectionTitle(
              title: 'Prossimi interventi',
            ),
          ),

          upcomingAsync.when(
            data: (schedules) => schedules.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 19),
                      child: EmptyState(
                        icon: LucideIcons.calendarOff,
                        title: 'Nessun intervento in programma',
                        body: 'I prossimi interventi appariranno qui dopo la sincronizzazione.',
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: EdgeInsets.fromLTRB(
                            19, i == 0 ? 0 : 8, 19, 8),
                        child: _UpcomingItem(schedule: schedules[i], ref: ref),
                      ),
                      childCount: schedules.length,
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // Bottom padding so last card clears the bottom nav.
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

// ── No active job empty state (inside hero) ────────────────────────────────────

class _NoActiveJobGlass extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: EmptyState(
        icon: LucideIcons.briefcase,
        title: 'Nessuna attività in corso',
        body: 'Non hai interventi attivi al momento.',
        action: AppButton(
          label: 'Cerca ticket aperti',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.dark,
          onPressed: null,
        ),
      ),
    );
  }
}

// ── Hero loading ───────────────────────────────────────────────────────────────

class _HeroLoadingIndicator extends StatelessWidget {
  const _HeroLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(color: AppColors.WHITE),
      ),
    );
  }
}

// ── Active job section (one card per in-progress job) ─────────────────────────

class _ActiveJobSection extends ConsumerWidget {
  const _ActiveJobSection({required this.jobs, required this.ref});

  final List<Schedule> jobs;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show the first in-progress job; timer is static for now (live timer in P3).
    final job = jobs.first;
    final locationAsync = ref.watch(locationByIdProvider(job.locationId));
    final location = locationAsync.valueOrNull;
    final customerName = location != null
        ? ref
            .watch(customerByIdProvider(location.customerId))
            .valueOrNull
            ?.companyName
        : null;

    return ActiveJobCard(
      stato: 'In corso',
      title: job.title.isNotEmpty ? job.title : 'Intervento',
      client: customerName,
      elapsed: '00:00:00',
      onOpen: null,
    );
  }
}

// ── Upcoming intervento card ───────────────────────────────────────────────────

class _UpcomingItem extends ConsumerWidget {
  const _UpcomingItem({required this.schedule, required this.ref});

  final Schedule schedule;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationByIdProvider(schedule.locationId));
    final location = locationAsync.valueOrNull;
    final customerName = location != null
        ? ref
            .watch(customerByIdProvider(location.customerId))
            .valueOrNull
            ?.companyName
        : null;

    final dateFmt = DateFormat('EEE d MMM', 'it');
    final dateLabel = dateFmt.format(schedule.activityDate.toLocal());
    final timeLabel = _minutesToTime(schedule.timeStartMinutes);

    return AppCard.pressable(
      onTap: () {},
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  schedule.title.isNotEmpty ? schedule.title : 'Intervento',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.DARK,
                  ),
                ),
                if (customerName != null || location?.city != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [customerName, location?.city]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.MUTED,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.DARK,
                ),
              ),
              Text(
                timeLabel,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: AppColors.MUTED,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _minutesToTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 4: Run dashboard screen test to verify it passes**

```
cmd.exe /c flutter.bat test test/features/dashboard/dashboard_screen_test.dart -v
```
Expected: PASS (5 tests).

- [ ] **Step 5: Run analyze**

```
cmd.exe /c flutter.bat analyze
```
Expected: "No issues found."

---

## Task 3 — Placeholder screens (Timbra, Calendario, Altro)

**Files:**
- Create: `lib/presentation/screens/placeholder/timbra_placeholder_screen.dart`
- Create: `lib/presentation/screens/placeholder/calendario_placeholder_screen.dart`
- Create: `lib/presentation/screens/placeholder/altro_screen.dart`
- Reads: `lib/presentation/screens/oggi/oggi_screen.dart` for `ComingSoonPlaceholder`
- Reads: `lib/presentation/screens/profilo/profilo_screen.dart` and `lib/presentation/screens/rapportini/rapportini_screen.dart` for imports

**Interfaces:**
- Produces: `TimbraPlaceholderScreen`, `CalendarioPlaceholderScreen`, `AltroScreen` — all `StatelessWidget` (no required params).
- `AltroScreen` must navigate to `/altro/rapportini` and `/altro/profilo` using `context.go(...)`.

- [ ] **Step 1: Write the failing test**

Add to `test/presentation/app_shell_test.dart` (add a new group at the bottom — do NOT remove existing tests yet):

We can't test placeholder navigation without the router; the router test in Task 4 will cover tab switching. For now, just verify the screens compile by adding import-only smoke tests:

Create `test/presentation/placeholders_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/presentation/screens/placeholder/timbra_placeholder_screen.dart';
import 'package:tasktap_mobile/presentation/screens/placeholder/calendario_placeholder_screen.dart';
import 'package:tasktap_mobile/presentation/screens/placeholder/altro_screen.dart';

void main() {
  testWidgets('TimbraPlaceholderScreen renders without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TimbraPlaceholderScreen()),
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('CalendarioPlaceholderScreen renders without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CalendarioPlaceholderScreen()),
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('AltroScreen renders without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AltroScreen()),
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cmd.exe /c flutter.bat test test/presentation/placeholders_test.dart -v
```
Expected: FAIL ("Target of URI doesn't exist").

- [ ] **Step 3: Create the three placeholder files**

`lib/presentation/screens/placeholder/timbra_placeholder_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../oggi/oggi_screen.dart';

class TimbraPlaceholderScreen extends StatelessWidget {
  const TimbraPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: ComingSoonPlaceholder(
          icon: LucideIcons.clock,
          title: 'Timbra',
          subtitle: 'Il modulo di timbratura arriverà in una prossima versione.',
        ),
      ),
    );
  }
}
```

`lib/presentation/screens/placeholder/calendario_placeholder_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../oggi/oggi_screen.dart';

class CalendarioPlaceholderScreen extends StatelessWidget {
  const CalendarioPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: ComingSoonPlaceholder(
          icon: LucideIcons.calendar,
          title: 'Calendario',
          subtitle: 'Il calendario arriverà in una prossima versione.',
        ),
      ),
    );
  }
}
```

`lib/presentation/screens/placeholder/altro_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';

/// Altro hub — links to Rapportini and Profilo (other sections added in P4).
class AltroScreen extends StatelessWidget {
  const AltroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Altro'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 19),
                children: [
                  _AltroTile(
                    icon: LucideIcons.fileText,
                    title: 'Rapportini',
                    onTap: () => context.go('/altro/rapportini'),
                  ),
                  const SizedBox(height: 8),
                  _AltroTile(
                    icon: LucideIcons.user,
                    title: 'Profilo',
                    onTap: () => context.go('/altro/profilo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AltroTile extends StatelessWidget {
  const _AltroTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard.pressable(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.BG3,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.DARK),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.DARK,
              ),
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: AppColors.DIS,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run placeholder test to verify it passes**

```
cmd.exe /c flutter.bat test test/presentation/placeholders_test.dart -v
```
Expected: PASS (3 tests).

- [ ] **Step 5: Run analyze**

```
cmd.exe /c flutter.bat analyze
```
Expected: "No issues found."

---

## Task 4 — 5-tab shell + router rewire

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/presentation/screens/home/home_shell.dart`
- Reads: `lib/core/widgets/bottom_nav.dart` (existing `AppBottomNav`)

**Key changes:**

`app_router.dart`:
- Add route constants: `dashboard = '/dashboard'`, `ticket = '/ticket'`, `timbra = '/timbra'`, `calendario = '/calendario'`, `altro = '/altro'`. Keep existing `login`, `rapportiniEditor()`. Add `altroProfilo = '/altro/profilo'`, `altroRapportini = '/altro/rapportini'`.
- Change `initialLocation` from `/oggi` to `/dashboard`.
- Change redirect: `isAuthenticated && isOnLogin` → go to `/dashboard` (was `/oggi`).
- Replace 4 `StatefulShellBranch` with 5:
  - Branch 0 `debugLabel: 'dashboard'` → `/dashboard` → `DashboardScreen()`
  - Branch 1 `debugLabel: 'ticket'` → `/ticket` → `InterventiScreen()` (reuse unchanged)
  - Branch 2 `debugLabel: 'timbra'` → `/timbra` → `TimbraPlaceholderScreen()`
  - Branch 3 `debugLabel: 'calendario'` → `/calendario` → `CalendarioPlaceholderScreen()`
  - Branch 4 `debugLabel: 'altro'` → `/altro` → `AltroScreen()`, sub-routes:
    - `path: 'rapportini'` → `RapportiniScreen()`, sub-route `path: 'editor/:reportId'` → `RapportinoEditorScreen(...)`
    - `path: 'profilo'` → `ProfiloScreen()`
- Keep the `/login` `GoRoute` and `_AuthStateListenable` unchanged.
- Remove old `/oggi`, `/interventi`, `/rapportini`, `/profilo` top-level paths (they no longer need to be top-level; all traffic enters through the new paths).

`home_shell.dart`:
- Remove the `_AppBottomNav` class and `NavigationBar` usage.
- Import `AppBottomNav` from `'../../../core/widgets/widgets.dart'`.
- Replace `bottomNavigationBar: _AppBottomNav(...)` with `bottomNavigationBar: AppBottomNav(currentIndex: widget.navigationShell.currentIndex, onTap: _onDestinationSelected)`.

- [ ] **Step 1: Write the failing test update**

The existing `test/presentation/app_shell_test.dart` asserts `NavigationBar`, 4 `NavigationDestination` widgets, and Italian tab labels 'Oggi'/'Interventi'/'Rapportini'/'Profilo'. After this task those assertions will fail (correct behavior), so first update the test file to reflect the new shell:

Open `test/presentation/app_shell_test.dart` and replace the `group('TaskTapApp shell smoke test', ...)` body with:

```dart
  group('TaskTapApp shell smoke test', () {
    testWidgets('app renders without throwing', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(MaterialApp), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('AppBottomNav is visible (5-tab pill)', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // AppBottomNav replaces NavigationBar.
      expect(find.byType(AppBottomNav), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('bottom nav shows Dashboard tab label (active)', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // Active tab shows label; Dashboard is index 0 (initial route).
      expect(find.text('Dashboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tapping Ticket tab switches branch', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // Tap "Ticket" icon (inactive tab — icon only, no label shown).
      final ticketFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Ticket',
      );
      if (ticketFinder.evaluate().isNotEmpty) {
        await tester.tap(ticketFinder.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.text('Ticket'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
```

Also add the following import to the test file (AppBottomNav):
```dart
import 'package:tasktap_mobile/core/widgets/widgets.dart';
```

- [ ] **Step 2: Run test to verify it fails**

```
cmd.exe /c flutter.bat test test/presentation/app_shell_test.dart -v
```
Expected: some tests FAIL (AppBottomNav not found in current shell, Dashboard route doesn't exist yet).

- [ ] **Step 3: Rewrite `lib/core/router/app_router.dart`**

Full replacement (write the entire file):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/screens/home/home_shell.dart';
import '../../presentation/screens/interventi/interventi_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../presentation/screens/placeholder/altro_screen.dart';
import '../../presentation/screens/placeholder/calendario_placeholder_screen.dart';
import '../../presentation/screens/placeholder/timbra_placeholder_screen.dart';
import '../../presentation/screens/profilo/profilo_screen.dart';
import '../../presentation/screens/rapportini/editor/rapportino_editor_screen.dart';
import '../../presentation/screens/rapportini/rapportini_screen.dart';

/// Route path constants.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String ticket = '/ticket';
  static const String timbra = '/timbra';
  static const String calendario = '/calendario';
  static const String altro = '/altro';
  static const String altroProfilo = '/altro/profilo';
  static const String altroRapportini = '/altro/rapportini';

  static String rapportiniEditor(String reportId) =>
      '/altro/rapportini/editor/$reportId';
}

/// Global navigator key.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds and returns the [GoRouter] for the TaskTap app.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.dashboard,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final isOnLogin = state.matchedLocation == AppRoutes.login;

      return authAsync.when(
        loading: () => null,
        error: (err, stack) => isOnLogin ? null : AppRoutes.login,
        data: (user) {
          final isAuthenticated = user != null;
          if (!isAuthenticated && !isOnLogin) return AppRoutes.login;
          if (isAuthenticated && isOnLogin) return AppRoutes.dashboard;
          return null;
        },
      );
    },
    refreshListenable: _AuthStateListenable(ref),
    routes: [
      // ── Auth ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),

      // ── Main Shell (5-tab bottom nav) ────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          // 0 — Dashboard
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'dashboard'),
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // 1 — Ticket (reuses InterventiScreen)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'ticket'),
            routes: [
              GoRoute(
                path: AppRoutes.ticket,
                builder: (context, state) => const InterventiScreen(),
              ),
            ],
          ),
          // 2 — Timbra (placeholder)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'timbra'),
            routes: [
              GoRoute(
                path: AppRoutes.timbra,
                builder: (context, state) => const TimbraPlaceholderScreen(),
              ),
            ],
          ),
          // 3 — Calendario (placeholder)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'calendario'),
            routes: [
              GoRoute(
                path: AppRoutes.calendario,
                builder: (context, state) =>
                    const CalendarioPlaceholderScreen(),
              ),
            ],
          ),
          // 4 — Altro (hub + Rapportini + Profilo sub-routes)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'altro'),
            routes: [
              GoRoute(
                path: AppRoutes.altro,
                builder: (context, state) => const AltroScreen(),
                routes: [
                  GoRoute(
                    path: 'rapportini',
                    builder: (context, state) => const RapportiniScreen(),
                    routes: [
                      GoRoute(
                        path: 'editor/:reportId',
                        builder: (context, state) => RapportinoEditorScreen(
                          reportId: state.pathParameters['reportId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'profilo',
                    builder: (context, state) => const ProfiloScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(WidgetRef ref) {
    ref.listenManual(authStateProvider, (prev, next) => notifyListeners());
  }
}
```

- [ ] **Step 4: Rewrite `lib/presentation/screens/home/home_shell.dart`**

Full replacement (write the entire file):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';

/// Main app shell — 5-tab pill bottom nav, state preserved per branch.
///
/// Sync triggers:
/// - On first mount (post-login): calls [SyncNotifier.performSync].
/// - On app foreground resume: calls [SyncNotifier.performSync].
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).performSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncProvider.notifier).performSync();
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: AppBottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onDestinationSelected,
      ),
    );
  }
}
```

- [ ] **Step 5: Run shell test**

```
cmd.exe /c flutter.bat test test/presentation/app_shell_test.dart -v
```
Expected: PASS (4 tests).

- [ ] **Step 6: Run full test suite**

```
cmd.exe /c flutter.bat test -v
```
Expected: all ≥ 301 tests green (providers test + placeholders test + dashboard screen test all added).

- [ ] **Step 7: Run analyze**

```
cmd.exe /c flutter.bat analyze
```
Expected: "No issues found."

---

## Task 5 — Final integration: commit

This task verifies the complete picture passes and makes the single commit.

- [ ] **Step 1: Run full test suite**

```
cmd.exe /c flutter.bat test
```
Expected: all tests green, count ≥ 301 + the new tests (≥ 311).

- [ ] **Step 2: Run analyze**

```
cmd.exe /c flutter.bat analyze
```
Expected: "No issues found."

- [ ] **Step 3: Verify test count**

```
cmd.exe /c flutter.bat test --reporter=compact 2>&1 | tail -5
```
Note the pass count; confirm ≥ 301.

- [ ] **Step 4: Stage and commit (inside mobile/ only)**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
git add \
  lib/features/dashboard/dashboard_providers.dart \
  lib/features/dashboard/dashboard_screen.dart \
  lib/presentation/screens/placeholder/timbra_placeholder_screen.dart \
  lib/presentation/screens/placeholder/calendario_placeholder_screen.dart \
  lib/presentation/screens/placeholder/altro_screen.dart \
  lib/core/router/app_router.dart \
  lib/presentation/screens/home/home_shell.dart \
  test/features/dashboard/dashboard_providers_test.dart \
  test/features/dashboard/dashboard_screen_test.dart \
  test/presentation/placeholders_test.dart \
  test/presentation/app_shell_test.dart \
  docs/superpowers/plans/2026-06-21-shell-and-dashboard.md
git commit -m "$(cat <<'EOF'
feat(mobile): 5-tab shell + Dashboard screen wired to real data

- Replace 4-tab NavigationBar shell with AppBottomNav (design-system
  floating pill) via go_router StatefulShellRoute (5 branches).
- Dashboard/Ticket/Timbra/Calendario/Altro. Profilo+Rapportini kept
  accessible via Altro sub-routes.
- DashboardScreen: Hero (user name from authStateProvider) +
  ActiveJobCard (inProgressSchedulesProvider, Drift cache) +
  StatsGrid 2x2 (today/inProgress/completed/upcoming) +
  QuickActions row + Prossimi interventi section (upcomingSchedulesProvider).
- Empty-state variant when no active jobs (GlassCard + EmptyState).
- Timbra/Calendario = placeholder; Altro = hub screen.
- Widget tests: dashboard active + empty + stats + QuickActions;
  shell AppBottomNav + 5 tabs; placeholders compile.
- flutter analyze clean; flutter test green (>=301).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Verify commit**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile && git log --oneline -3
```
Expected: the new commit appears at top.

---

## Self-Review Checklist

### Spec coverage

| Spec requirement | Task |
|---|---|
| 5-tab shell: Dashboard/Ticket/Timbra/Calendario/Altro | Task 4 |
| go_router StatefulShellRoute | Task 4 |
| Existing screens reachable (Rapportini/Profilo via Altro) | Task 4 (altro_screen.dart sub-routes) |
| Hero: Bentornato + user name from authStateProvider | Task 2 |
| ActiveJobCard(s) for in-progress work | Task 2 |
| StatsGrid 2×2 (oggi/in corso/completati/prossimi) | Task 2, Task 1 |
| QuickActions row (4 items) | Task 2 |
| "Prossimi interventi" section + UpcomingItem cards | Task 2 |
| Wire to real Riverpod providers (Drift cache) | Tasks 1–2 |
| Empty-state variant (no active jobs) | Task 2 |
| Timbra/Calendario/Altro = placeholder screens | Task 3 |
| Safe areas, ≥44pt touch targets | DashboardHero has SafeArea; HeaderIconBtn is 44×44; AppBottomNav tabs min 44pt |
| App compiles + analyze clean | Task 4 Step 7 |
| Widget tests: dashboard renders, active+empty states, shell 5 tabs, tab switch | Tasks 1–4 |
| flutter test green ≥ 301 | Task 5 |
| ONE commit | Task 5 Step 4 |
| Git ops inside mobile/ only | All tasks use cd /mnt/d/.../mobile |

### Placeholder scan — PASS
No TBD, TODO, "implement later", "similar to Task N", or "add validation" phrases found.

### Type consistency
- `inProgressSchedulesProvider` — defined Task 1, consumed Task 2 ✓
- `dashboardStatsProvider` → `DashboardStats` — defined Task 1, consumed Task 2 ✓
- `upcomingSchedulesProvider` — defined Task 1, consumed Task 2 ✓
- `AppBottomNav(currentIndex:, onTap:)` — signature in `bottom_nav.dart` (existing) matches Task 4 usage ✓
- `ActiveJobCard(stato:, title:, client:, elapsed:, onOpen:)` — matches `active_job_card.dart` ✓
- `StatsGrid(items: List<StatItem>)` — matches `stats_grid.dart` ✓
- `QuickAction(icon:, label:, onTap:)` — matches `quick_action.dart` ✓
- `DashboardHero(userName:, actions:, child:)` — matches `dashboard_hero.dart` ✓
- `AppRoutes.rapportiniEditor(id)` — updated in Task 4 to `/altro/rapportini/editor/$reportId` and used in `RapportiniScreen` (`context.push(AppRoutes.rapportiniEditor(...))`) ✓
