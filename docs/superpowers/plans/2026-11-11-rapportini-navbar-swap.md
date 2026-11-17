# Rapportini in navbar, Interventi in Altro — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make **Reports** (the report list) the bottom-nav tab at index 1 and move **Ticket** access to **Altro › Interventi**, keeping every existing path and deep link valid.

**Architecture:** Swap the shell branch at index 1 from `/ticket` to `/altro/rapportini` (moving the existing report route subtree with it), promote `/ticket` to a root-level full-screen route, and have the Altro hub `push` it so back navigation returns to the hub. The floating nav's tab 1 label/icon changes to Reports; the duplicate Rapportini tile leaves the Altro hub.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, drift. Tests use `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-11-rapportini-navbar-swap-design.md`

## Global Constraints

- Exactly 5 bottom-nav tabs, unchanged order: Dashboard, Reports, Cantieri, Calendario, Altro.
- All existing paths stay valid: `/ticket`, `/ticket/:id`, `/ticket/:id/assets`, `/ticket/new`, `/altro/rapportini`, `/altro/rapportini/editor/:reportId`, `/altro/rapportini/view/:reportId`, `/altro/rapportini/copilot`.
- Italian UI copy: tab label is exactly `Reports`; ticket list header remains `Ticket`; ticket search hint remains `Cerca ticket…`; report search hint remains `Cerca rapportino…`.
- No backend changes.
- Do not commit: the working tree already contains unrelated in-progress changes, and the user has not requested a commit. Stage/report only the files this plan touches.

## Review Focus

Each line is pinned by a test in Task 1.

- A notification deep link straight to `/ticket` (no shell history) must render the ticket list, not crash or show an empty shell.
- A direct visit to `/altro/rapportini` (where report notifications land) must render the report list now that the subtree lives in branch 1.
- A tenant without the `interventi` module must still redirect `/ticket` to `ForbiddenScreen`.
- Back from the ticket list opened via Altro › Interventi must return to the Altro hub.
- Tapping the Reports tab with no reports must show the list's empty state, not a blank screen.

---

### Task 1: Swap the tab, relocate both route subtrees, and update the Altro hub

**Files:**
- Modify: `lib/core/widgets/bottom_nav.dart:8-16` (icon constants) and `:57-63` (`defaultItems`)
- Modify: `lib/core/router/app_router.dart:486-543` (ticket root route + branch 1) and `:584-625` (remove report subtree from Altro branch)
- Modify: `lib/features/altro/altro_hub_screen.dart:104-118` (Interventi push, remove Rapportini tile)
- Modify: `lib/features/ticket/ticket_list_screen.dart:163-166` (back affordance)
- Test: `test/core/widgets/bottom_nav_test.dart`
- Test: `test/presentation/app_shell_test.dart`
- Test: `test/core/router/app_router_route_requirement_redirect_test.dart`

**Interfaces:**
- Consumes: existing `AppRoutes.ticket` (`/ticket`), `AppRoutes.altroRapportini` (`/altro/rapportini`), `RapportiniListScreen`, `TicketListScreen`.
- Produces: `AppBottomNavIcons.reports` (`IconData`, `LucideIcons.fileText`); `AppBottomNav.defaultItems[1]` is `AppBottomNavItem(icon: AppBottomNavIcons.reports, label: 'Reports')`.

- [ ] **Step 1: Update the bottom-nav widget test to the new expectation**

In `test/core/widgets/bottom_nav_test.dart`:
- Change the "active tab shows its label" assertion at line 16 to `expect(find.text('Reports'), findsNothing);`
- Change the index-1 test at lines 52-57 to expect `find.text('Reports')` and no `Dashboard`.
- Change the icon assertion at line 63 to `expect(find.byIcon(AppBottomNavIcons.reports), findsOneWidget);`

- [ ] **Step 2: Run the bottom-nav test to verify it fails**

Run: `flutter test test/core/widgets/bottom_nav_test.dart`
Expected: FAIL — `AppBottomNavIcons.reports` is undefined / `Reports` not found.

- [ ] **Step 3: Update `bottom_nav.dart`**

Replace the `ticket` icon constant with:
```dart
static const IconData reports = LucideIcons.fileText;
```
Change `defaultItems[1]` to:
```dart
AppBottomNavItem(icon: AppBottomNavIcons.reports, label: 'Reports'),
```
Leave the other four entries and their order untouched.

- [ ] **Step 4: Run the bottom-nav test to verify it passes**

Run: `flutter test test/core/widgets/bottom_nav_test.dart`
Expected: PASS.

- [ ] **Step 5: Replace and extend the shell navigation tests**

In `test/presentation/app_shell_test.dart`, replace the `tapping Ticket tab switches branch` test (lines 132-147) with:

```dart
testWidgets('tapping Reports tab opens the report list', (tester) async {
  await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final reportsTab = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Reports',
  );
  expect(reportsTab, findsWidgets);
  await tester.tap(reportsTab.first);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  expect(find.text('Cerca rapportino…'), findsOneWidget);
  expect(find.text('Nessun rapportino'), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

Add below it:

```dart
testWidgets('Altro › Interventi opens the ticket list and back returns to Altro', (tester) async {
  await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final altroTab = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Altro',
  );
  await tester.tap(altroTab.first);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  await tester.tap(find.text('Interventi'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.text('Cerca ticket…'), findsOneWidget);

  final back = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Indietro',
  );
  await tester.tap(back.first);
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.text('Gestione'), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

- [ ] **Step 6: Add direct-route regression tests**

In `test/core/router/app_router_route_requirement_redirect_test.dart`, add the imports:
```dart
import 'package:tasktap_mobile/features/rapportino/rapportini_list_screen.dart';
import 'package:tasktap_mobile/features/ticket/ticket_list_screen.dart';
```

Then add these tests at the end of `main()`:

```dart
testWidgets('direct /ticket renders the ticket list without the shell', (tester) async {
  final cached = Entitlement(
    features: const {'interventi', 'rapportini'},
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
  GoRouter.of(context).go('/ticket');
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(find.byType(TicketListScreen), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});

testWidgets('direct /altro/rapportini renders the report list', (tester) async {
  final cached = Entitlement(
    features: const {'interventi', 'rapportini'},
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
  GoRouter.of(context).go('/altro/rapportini');
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(find.byType(RapportiniListScreen), findsOneWidget);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});

testWidgets('unentitled interventi redirects /ticket to /forbidden', (tester) async {
  final cached = Entitlement(
    features: const {'rapportini'},
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
  GoRouter.of(context).go('/ticket');
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(find.byType(ForbiddenScreen), findsOneWidget);
  expect(find.byType(TicketListScreen), findsNothing);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
});
```

- [ ] **Step 7: Run the new tests to verify they fail**

Run:
```bash
flutter test test/presentation/app_shell_test.dart test/core/router/app_router_route_requirement_redirect_test.dart
```
Expected: FAIL — tab 1 still shows tickets; `/ticket` is not a root route.

- [ ] **Step 8: Move the report route subtree into branch 1 and promote `/ticket` to a root route**

In `lib/core/router/app_router.dart`:

1. In the root route list, immediately after the existing `/ticket/new` `GoRoute` (around line 490), add:
```dart
GoRoute(
  path: AppRoutes.ticket,
  builder: (context, state) => const TicketListScreen(),
  routes: [
    GoRoute(
      path: ':id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => TicketDetailScreen(
        ticketId: state.pathParameters['id']!,
      ),
      routes: [
        GoRoute(
          path: 'assets',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              AssetChecklistScreen(ticketId: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
),
```

2. Replace the branch at index 1 (currently the `// 1 — Ticket` block, lines 514-543) with:
```dart
// 1 — Rapportini
StatefulShellBranch(
  navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'rapportini'),
  routes: [
    GoRoute(
      path: AppRoutes.altroRapportini,
      builder: (context, state) => const RapportiniListScreen(),
      routes: [
        GoRoute(
          path: 'editor/:reportId',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => RapportinoFormScreen(
            reportId: state.pathParameters['reportId']!,
          ),
          routes: [
            GoRoute(
              path: 'assets',
              parentNavigatorKey: rootNavigatorKey,
              builder: (context, state) => AssetChecklistScreen(
                reportId: state.pathParameters['reportId']!,
                focusAssetId: state.uri.queryParameters['focus'],
                initialFilter: ChecklistFilter.values.firstWhere(
                  (f) => f.name == state.uri.queryParameters['filter'],
                  orElse: () => ChecklistFilter.all,
                ),
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'copilot',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => AiCopilotScreen(
            ticketId: state.uri.queryParameters['ticketId'],
            cantiereId: state.uri.queryParameters['cantiereId'],
          ),
        ),
        GoRoute(
          path: 'view/:reportId',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => RapportinoViewScreen(
            reportId: state.pathParameters['reportId']!,
          ),
        ),
      ],
    ),
  ],
),
```

3. Delete the now-duplicated `rapportini` subtree from the Altro branch (`app_router.dart:584-625`). Keep the Altro branch's `profilo`, `impostazioni`, `notifiche`, `i-miei-dati`, `ferie`, `clienti`, etc.

4. Update the comment above branch 4 from `// 4 — Altro (hub + Rapportini + ...)` to `// 4 — Altro (hub + Profilo + Impostazioni + Notifiche)`.

- [ ] **Step 9: Update the Altro hub tiles**

In `lib/features/altro/altro_hub_screen.dart`:
- Change the Interventi tile's callback to `onTap: () => context.push(AppRoutes.ticket),`
- Delete the Rapportini tile record (`LucideIcons.fileText`, label `Rapportini`, module `rapportini`, `context.go(AppRoutes.altroRapportini)`).

- [ ] **Step 10: Add a back affordance to the ticket list**

In `lib/features/ticket/ticket_list_screen.dart`, change the `ScreenHeader` call (lines 163-166) to:
```dart
child: ScreenHeader(
  title: 'Ticket',
  subtitle: '${allTickets.length} totali · $inCorsoCount in corso',
  showBack: Navigator.of(context).canPop(),
),
```
This shows a back chevron when the list is pushed (Altro › Interventi) and stays hidden for a root `go` (notification digest).

- [ ] **Step 11: Run the targeted tests**

Run:
```bash
flutter test test/core/widgets/bottom_nav_test.dart test/presentation/app_shell_test.dart test/core/router/app_router_route_requirement_redirect_test.dart test/core/notifications/deep_link_intent_test.dart test/core/notifications/deep_link_drainer_test.dart test/core/router/asset_checklist_routes_test.dart
```
Expected: PASS.

- [ ] **Step 12: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!` (or only pre-existing issues unrelated to the files above; inspect each).

- [ ] **Step 13: Report, do not commit**

Report the touched files and the test/analyze output. Do **not** run `git commit`; the repository has unrelated pre-existing modifications and no commit was requested.
