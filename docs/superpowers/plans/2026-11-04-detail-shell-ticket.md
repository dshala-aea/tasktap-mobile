# Detail Shell + Ticket Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared `DetailScaffold` / `DetailHero` / `DetailSection` shell and migrate the ticket detail screen to it without losing any existing ticket behaviour.

**Architecture:** Add a small, presentation-only widget set under `lib/core/widgets/detail/`. The shell owns the generic header, scroll frame, collapsing status/action bar, loading/unavailable frames, and max width. Screens supply a `DetailHeroData` and an ordered list of `DetailSectionData`; the ticket screen keeps its existing compartment bottom sheets and provider logic, only regrouping their entry points into the four sections.

**Tech Stack:** Flutter, Riverpod, existing TaskTap core widgets (`AppCard`, `AppButton`, `StatusStamp`, `ScreenHeader`, `AppCompartmentTile`, `UnavailableState`). No new packages.

**Spec:** `docs/superpowers/specs/2026-11-04-detail-shell-design.md`

## Global Constraints

- Il Documento tokens only: Paper `#F1EEE7`, Sheet `#FBF9F4`, Ink `#22252E`, Slate `#5E6878`, Rule `#DED9CE`, Stamp Red `#C03221`.
- Flat surfaces only; 1px Rule borders, 2px radius, no shadows/blur/gradients.
- Header shows the generic screen name (`Ticket`, `Cliente`); the hero owns the entity title.
- Hero shows at most three facts; those facts do not repeat in Sintesi.
- Collapsed bar is 56px, shows status + primary action only.
- Disabled-with-reason for state; hidden for permission.
- No new network reads; keep mirrors and existing providers.
- Italian copy; 48px minimum touch targets; respect `MediaQuery.disableAnimationsOf`.
- No FAB when the hero has a primary action.
- Run `dart format` on touched files; `flutter analyze` must be clean.

## Review Focus

1. **Long ticket titles and fact values** — two-line clamp/ellipsis at 320–430px width, no action pushed off-screen.
2. **Offline timer** — `Avvia intervento` must be disabled with a reason, never silently absent; the rest of the page still renders from local data.
3. **Unassigned ticket** — `Prendi in carico` stays reachable; the hero must not promise a timer start the server will refuse.
4. **Permission-hidden actions** — edit/assign/delete follow the existing capability gates; hiding them must not shift the header layout.
5. **Collapse back-scroll** — the bar disappears when the hero returns, does not trap focus, and does not cover the section title when hidden.

---

### Task 1: Detail hero

**Files:**
- Create: `lib/core/widgets/detail/detail_hero.dart`
- Test: `test/core/widgets/detail/detail_hero_test.dart`

**Interfaces:**
- Consumes: `AppCard`, `AppButton`, `StatusStamp`, `AppSpacing`, `AppTextStyles`, `AppPalette`.
- Produces:
  - `enum DetailHeroVariant { operational, summary }`
  - `enum DetailStatusTone { neutral, info, good, warn, bad }`
  - `class DetailStatus { const DetailStatus({required this.label, this.tone = DetailStatusTone.neutral}); final String label; final DetailStatusTone tone; }`
  - `class DetailFact { const DetailFact({required this.label, required this.value, this.onTap}); final String label; final String value; final VoidCallback? onTap; }`
  - `class DetailAction { const DetailAction({required this.label, this.icon, this.onPressed, this.enabled = true, this.disabledReason}); final String label; final Widget? icon; final VoidCallback? onPressed; final bool enabled; final String? disabledReason; }`
  - `class DetailHeroData { const DetailHeroData({required this.title, required this.variant, required this.status, this.subtitle, this.facts = const [], this.liveValue, this.primaryAction, this.secondaryActions = const []}) : assert(facts.length <= 3); ... }`
  - `class DetailHero extends StatelessWidget { const DetailHero({super.key, required this.data}); final DetailHeroData data; }`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('renders entity title, subtitle, stamp and three facts', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: DetailHero(data: DetailHeroData(
      variant: DetailHeroVariant.operational,
      title: 'Perdita acqua sotto il lavello',
      subtitle: 'INT-2026-0412',
      status: const DetailStatus(label: 'In corso', tone: DetailStatusTone.warn),
      facts: const [
        DetailFact(label: 'Cliente', value: 'Rossi Srl'),
        DetailFact(label: 'Sede', value: 'Milano'),
        DetailFact(label: 'Tecnico', value: 'D. Shala'),
      ],
    )),
  ));
  expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
  expect(find.text('INT-2026-0412'), findsOneWidget);
  expect(find.text('IN CORSO'), findsOneWidget);
  expect(find.text('Rossi Srl'), findsOneWidget);
});

testWidgets('more than three facts are rejected', (tester) async {
  expect(
    () => DetailHeroData(
      variant: DetailHeroVariant.summary,
      title: 'Cliente',
      status: const DetailStatus(label: 'Attivo'),
      facts: const [
        DetailFact(label: 'A', value: '1'),
        DetailFact(label: 'B', value: '2'),
        DetailFact(label: 'C', value: '3'),
        DetailFact(label: 'D', value: '4'),
      ],
    ),
    throwsAssertionError,
  );
});

testWidgets('long titles clamp to two lines without overflowing', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: SizedBox(
      width: 320,
      child: DetailHero(data: DetailHeroData(
        variant: DetailHeroVariant.operational,
        title: 'Perdita acqua sotto il lavello della cucina del piano primo con allagamento',
        status: const DetailStatus(label: 'In corso'),
      )),
    ),
  ));
  expect(tester.takeException(), isNull);
  expect(find.textContaining('Perdita acqua sotto'), findsOneWidget);
});

testWidgets('disabled primary action shows its reason and never fires', (tester) async {
  var fired = false;
  await tester.pumpWidget(MaterialApp(
    home: DetailHero(data: DetailHeroData(
      variant: DetailHeroVariant.operational,
      title: 'Ticket',
      status: const DetailStatus(label: 'Aperto'),
      primaryAction: DetailAction(
        label: 'Avvia intervento',
        enabled: false,
        disabledReason: 'Timer non disponibile offline',
        onPressed: () => fired = true,
      ),
    )),
  ));
  expect(find.text('Timer non disponibile offline'), findsOneWidget);
  await tester.tap(find.text('Avvia intervento'));
  expect(fired, isFalse);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/widgets/detail/detail_hero_test.dart`
Expected: FAIL — `detail_hero.dart` / `DetailHero` not found.

- [ ] **Step 3: Implement `lib/core/widgets/detail/detail_hero.dart`**

Use `AppCard` for the surface. Layout: status stamp + optional `data.liveValue` in a top row; title (`Archivo Narrow`, 28, w700, maxLines 2, ellipsis); optional subtitle (`IBM Plex Mono`, 11, muted); facts in a `Wrap`/two-column row using small label + value; primary `AppButton` full width (`onPressed: action.enabled ? action.onPressed : null`); secondary actions in one `Row` of `Expanded` `AppButton.secondary` / `AppButton.ghost`. Render `disabledReason` as one 12px slate line under the primary button. If `variant == summary`, never render `liveValue`.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/widgets/detail/detail_hero_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/detail/detail_hero.dart test/core/widgets/detail/detail_hero_test.dart
git commit -m "feat(detail): add the shared detail hero"
```

---

### Task 2: Detail section

**Files:**
- Create: `lib/core/widgets/detail/detail_section.dart`
- Test: `test/core/widgets/detail/detail_section_test.dart`

**Interfaces:**
- Consumes: `AppSpacing`, `AppTextStyles`, `AppPalette`.
- Produces:
  - `class DetailSectionData { const DetailSectionData({required this.title, required this.child, this.trailing, this.isEmpty = false}); final String title; final Widget child; final Widget? trailing; final bool isEmpty; }`
  - `class DetailSection extends StatelessWidget { const DetailSection({super.key, required this.data}); final DetailSectionData data; }`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('renders the title, trailing and child', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: DetailSection(data: DetailSectionData(
      title: 'Sintesi',
      trailing: Text('4 campi'),
      child: Text('Contenuto'),
    )),
  ));
  expect(find.text('Sintesi'), findsOneWidget);
  expect(find.text('4 campi'), findsOneWidget);
  expect(find.text('Contenuto'), findsOneWidget);
});

testWidgets('empty sections render nothing', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: DetailSection(data: DetailSectionData(
      title: 'Documenti',
      isEmpty: true,
      child: Text('non deve apparire'),
    )),
  ));
  expect(find.text('Documenti'), findsNothing);
  expect(find.text('non deve apparire'), findsNothing);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/widgets/detail/detail_section_test.dart`
Expected: FAIL — `DetailSection` not found.

- [ ] **Step 3: Implement `lib/core/widgets/detail/detail_section.dart`**

Render `SizedBox.shrink()` when `isEmpty`. Otherwise a `Column`: a title row (`Archivo Narrow`, 18, w700) with optional trailing (mono/small, right-aligned), 8px gap, child. Do not use `SectionTitle` — it embeds `pagePadding`, which the scaffold already applies.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/widgets/detail/detail_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/detail/detail_section.dart test/core/widgets/detail/detail_section_test.dart
git commit -m "feat(detail): add the shared detail section"
```

---

### Task 3: Detail scaffold frame

**Files:**
- Create: `lib/core/widgets/detail/detail_scaffold.dart`
- Test: `test/core/widgets/detail/detail_scaffold_test.dart`

**Interfaces:**
- Consumes: Task 1 `DetailHeroData` / `DetailHero`; Task 2 `DetailSectionData` / `DetailSection`; `ScreenHeader`, `AppSpacing`.
- Produces:
  - `class DetailScaffold extends StatefulWidget { const DetailScaffold({super.key, required this.screenTitle, required this.hero, this.headerActions = const [], this.expandedExtra, required this.sections, this.onRefresh, this.maxWidth = 720, this.fab}); ... }`
  - `static Widget loading({required String screenTitle, List<Widget> headerActions = const []})` (implemented in Task 5; leave a stub that throws until then if necessary, but prefer implementing the frame first and adding the named constructors in Task 5).
  - `static Widget unavailable({...})` (Task 5).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('renders the generic header, hero and sections in order', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: DetailScaffold(
    screenTitle: 'Ticket',
    hero: DetailHeroData(
      variant: DetailHeroVariant.operational,
      title: 'Perdita acqua sotto il lavello',
      status: DetailStatus(label: 'Aperto'),
    ),
    sections: [
      DetailSectionData(title: 'Attività', child: Text('attività')),
      DetailSectionData(title: 'Sintesi', child: Text('sintesi')),
    ],
  )));
  expect(find.text('Ticket'), findsOneWidget);
  expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
  expect(tester.getTopLeft(find.text('Attività')).dy,
      lessThan(tester.getTopLeft(find.text('Sintesi')).dy));
});

testWidgets('skips empty sections and respects max width', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: DetailScaffold(
    screenTitle: 'Cliente',
    maxWidth: 600,
    hero: DetailHeroData(
      variant: DetailHeroVariant.summary,
      title: 'Rossi Srl',
      status: DetailStatus(label: 'Attivo'),
    ),
    sections: [
      DetailSectionData(title: 'Sintesi', child: Text('sintesi')),
      DetailSectionData(title: 'Documenti', isEmpty: true, child: Text('vuoto')),
    ],
  )));
  expect(find.text('Documenti'), findsNothing);
  final content = tester.getSize(find.byKey(const Key('detail-content')));
  expect(content.width, lessThanOrEqualTo(600));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/widgets/detail/detail_scaffold_test.dart`
Expected: FAIL — `DetailScaffold` not found.

- [ ] **Step 3: Implement the frame**

`Scaffold` → `SafeArea` → `Column`:
1. `ScreenHeader(title: screenTitle, showBack: true, actions: headerActions)`.
2. `Expanded` → `RefreshIndicator` (when `onRefresh != null`) → `CustomScrollView` with `SliverToBoxAdapter` for `DetailHero` (centered, `ConstrainedBox(maxWidth: maxWidth)`, page padding, wrapped in a `Key('detail-content')`), `expandedExtra`, then each `DetailSection` as its own `SliverToBoxAdapter`. Add bottom padding `AppSpacing.xxl`. Use a `ScrollController` owned by the state (needed by Task 4).
3. Optional `fab` via `Scaffold.floatingActionButton` with `context.fabSafeBottom` padding.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/widgets/detail/detail_scaffold_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/detail/detail_scaffold.dart test/core/widgets/detail/detail_scaffold_test.dart
git commit -m "feat(detail): add the shared detail scaffold frame"
```

---

### Task 4: Collapsing status/action bar

**Files:**
- Modify: `lib/core/widgets/detail/detail_scaffold.dart`
- Test: `test/core/widgets/detail/detail_scaffold_test.dart`

**Interfaces:**
- Consumes: Task 3 `DetailScaffold`.
- Produces: `Key('detail-collapsed-bar')` on the bar; `DetailScaffold` gains no new public parameters — it derives status/action from `hero`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('collapsed bar appears after the hero scrolls away and hides on return', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: DetailScaffold(
    screenTitle: 'Ticket',
    hero: DetailHeroData(
      variant: DetailHeroVariant.operational,
      title: 'Ticket lungo',
      status: DetailStatus(label: 'In corso'),
      primaryAction: DetailAction(label: 'Chiudi intervento', onPressed: () {}),
    ),
    sections: [
      DetailSectionData(title: 'Attività', child: SizedBox(height: 1200, child: Text('attività'))),
    ],
  )));
  expect(find.byKey(const Key('detail-collapsed-bar')), findsNothing);
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('detail-collapsed-bar')), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const Key('detail-collapsed-bar')),
      matching: find.text('Chiudi intervento'),
    ),
    findsOneWidget,
  );
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 700));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('detail-collapsed-bar')), findsNothing);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/widgets/detail/detail_scaffold_test.dart --plain-name "collapsed bar"`
Expected: FAIL — no collapsed bar.

- [ ] **Step 3: Implement the bar**

Wrap the scroll area in a `Stack`. Attach a `GlobalKey` to the hero. In a `NotificationListener<ScrollNotification>`, compute whether the hero's bottom is above the scroll viewport top (use the render box; do not hard-code a scroll offset). When true, show a 56px `Positioned(top: 0, left: 0, right: 0)` bar with `AnimatedSlide` + `AnimatedOpacity` (150ms, ease-out; skip animation when `MediaQuery.disableAnimationsOf`). The bar is a `Sheet` surface with a bottom Rule, a `StatusStamp` small, and a compact `AppButton` (`size: AppButtonSize.sm`, `fullWidth: false`) for `hero.primaryAction`; no secondary actions. Wrap hidden state in `IgnorePointer`. Add `Key('detail-collapsed-bar')` to the visible bar only.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/widgets/detail/detail_scaffold_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/detail/detail_scaffold.dart test/core/widgets/detail/detail_scaffold_test.dart
git commit -m "feat(detail): collapse the hero into a sticky action bar"
```

---

### Task 5: Loading and unavailable frames

**Files:**
- Modify: `lib/core/widgets/detail/detail_scaffold.dart`
- Test: `test/core/widgets/detail/detail_scaffold_test.dart`

**Interfaces:**
- Produces:
  - `static Widget DetailScaffold.loading({required String screenTitle, List<Widget> headerActions = const []})`
  - `static Widget DetailScaffold.unavailable({required String screenTitle, required IconData icon, required String title, required String reason, VoidCallback? onRetry, List<Widget> headerActions = const []})`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('loading shows a header and a hero skeleton, never a full-screen spinner', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: DetailScaffold.loading(screenTitle: 'Ticket')));
  expect(find.text('Ticket'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byKey(const Key('detail-loading-skeleton')), findsOneWidget);
});

testWidgets('unavailable shows the reason and retry', (tester) async {
  var retried = false;
  await tester.pumpWidget(MaterialApp(home: DetailScaffold.unavailable(
    screenTitle: 'Ticket',
    icon: LucideIcons.ticket,
    title: 'Ticket non trovato',
    reason: 'Il ticket non è disponibile in cache.',
    onRetry: () => retried = true,
  )));
  expect(find.text('Ticket non trovato'), findsOneWidget);
  await tester.tap(find.text('Riprova'));
  expect(retried, isTrue);
});
```

Add `import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';` to the test.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/widgets/detail/detail_scaffold_test.dart --plain-name "loading"`
Expected: FAIL — named constructor not found.

- [ ] **Step 3: Implement the frames**

Both use the same `Scaffold` + `ScreenHeader` frame. Loading renders an `AppCard` placeholder (`Key('detail-loading-skeleton')`) with three Rule-coloured bars at hero height; no spinner. Unavailable renders `UnavailableState` with the provided icon/title/reason and retry action.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/widgets/detail/detail_scaffold_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/detail/detail_scaffold.dart test/core/widgets/detail/detail_scaffold_test.dart
git commit -m "feat(detail): add loading and unavailable frames"
```

---

### Task 6: Ticket timer hero value and action

**Files:**
- Create: `lib/features/ticket/ticket_timer_hero.dart`
- Modify: `lib/features/ticket/ticket_providers.dart` (add `ticketTimerBusyProvider`)
- Modify: `lib/features/ticket/ticket_detail_screen.dart` (move `ticketTimerElapsed` out, see Step 3)
- Modify: `test/features/ticket/ticket_timer_elapsed_test.dart` (import the new file)
- Test: `test/features/ticket/ticket_timer_hero_test.dart`

**Interfaces:**
- Consumes: `ticketWorklogsProvider`, `runningTicketWorklogProvider`, `nowProvider`, `businessTimeProvider`, `ticketWorkflowApiClientProvider`, `formatElapsed`, `LiveDot`.
- Produces:
  - `final ticketTimerBusyProvider = StateProvider.autoDispose.family<bool, String>((ref, ticketId) => false);`
  - `class TicketTimerLiveValue extends ConsumerWidget { const TicketTimerLiveValue({super.key, required this.ticketId}); final String ticketId; }`
  - `Duration ticketTimerElapsed(TicketWorkLogDto running, DateTime now, BusinessTime businessTime)` (moved from `ticket_detail_screen.dart`)
  - `DetailAction ticketTimerAction(BuildContext context, WidgetRef ref, String ticketId)`

- [ ] **Step 1: Write the failing tests**

```dart
class _TimerHarness extends ConsumerWidget {
  const _TimerHarness();
  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailHero(
    data: DetailHeroData(
      variant: DetailHeroVariant.operational,
      title: 'Ticket',
      status: const DetailStatus(label: 'Aperto'),
      liveValue: const TicketTimerLiveValue(ticketId: 't1'),
      primaryAction: ticketTimerAction(context, ref, 't1'),
    ),
  );
}

testWidgets('offline timer shows the reason and disables the action', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [isOnlineProvider.overrideWithValue(false)],
    child: const MaterialApp(home: _TimerHarness()),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Timer non disponibile offline'), findsAtLeastNWidgets(1));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/ticket/ticket_timer_hero_test.dart`
Expected: FAIL — `TicketTimerLiveValue` not found.

- [ ] **Step 3: Implement**

Move `ticketTimerElapsed` from `ticket_detail_screen.dart` into `ticket_timer_hero.dart`; update `test/features/ticket/ticket_timer_elapsed_test.dart` to import the new file. Remove the old definition from the screen (Task 7 removes its last caller).

`TicketTimerLiveValue` watches `ticketWorklogsProvider(ticketId)`; on `TicketDetailOfflineException` returns `Text('Timer non disponibile offline')`; otherwise watches `runningTicketWorklogProvider` and `nowProvider`, returning `Row(LiveDot, Text(formatElapsed(ticketTimerElapsed(...))))` when running, or `Text('Nessun timer attivo')` when not. `ticketTimerAction` returns a `DetailAction` whose label is `Chiudi intervento` when running else `Avvia intervento`; disabled with `Timer non disponibile offline` when the worklogs provider is offline; disabled while `ticketTimerBusyProvider(ticketId)` is true; otherwise `onPressed` toggles via `ticketWorkflowApiClientProvider.startTimer/stopTimer`, sets the busy provider, invalidates `ticketWorklogsProvider`, and shows `showAppToast` on `TicketWorkflowFailure`.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/ticket/ticket_timer_hero_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ticket/ticket_timer_hero.dart lib/features/ticket/ticket_providers.dart test/features/ticket/ticket_timer_hero_test.dart
git commit -m "feat(ticket): expose the ticket timer as a detail hero action"
```

---

### Task 7: Ticket shell + hero migration

**Files:**
- Modify: `lib/features/ticket/ticket_detail_screen.dart`
- Modify: `test/features/ticket/ticket_detail_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: `TicketDetailScreen` uses `DetailScaffold`; `_TicketDetailBody` returns a `DetailScaffold` with `screenTitle: 'Ticket'`, header actions, hero, `expandedExtra` status row, and one temporary `Attività` section containing the existing body content (the map, summary card and compartment grid) so the screen remains working before Task 8.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/ticket/ticket_detail_screen_test.dart`:

```dart
testWidgets('uses the generic Ticket header and the entity title in the hero', (tester) async {
  await seedBase(db);
  await pump(tester);
  expect(find.text('Ticket'), findsOneWidget);
  expect(find.text('Perdita idrica bagno'), findsOneWidget);
});

testWidgets('offline hero offers Avvia intervento disabled with a reason', (tester) async {
  await seedBase(db);
  await pump(tester); // defaults offline
  expect(find.text('Avvia intervento'), findsOneWidget);
  expect(find.text('Timer non disponibile offline'), findsOneWidget);
});

testWidgets('Crea rapportino and AI Copilot move into the hero', (tester) async {
  await seedBase(db);
  await pump(tester);
  expect(find.text('Crea rapportino'), findsOneWidget);
  expect(find.text('AI Copilot'), findsOneWidget);
});

testWidgets('an unassigned ticket keeps Prendi in carico reachable', (tester) async {
  await db.into(db.tickets).insert(TicketsCompanion.insert(
    id: 'ticket-2', tenantId: 'tenant-1', createdAt: DateTime.utc(2026, 6, 1, 9),
    title: 'Ticket libero', customerId: 'cust-1', locationId: 'loc-1', statusId: 1, typeId: 1,
  ));
  await pump(tester, ticketId: 'ticket-2');
  expect(find.text('Prendi in carico'), findsOneWidget);
});

testWidgets('delete is hidden without the tenant-admin capability', (tester) async {
  await seedBase(db);
  await pump(tester);
  expect(find.bySemanticsLabel('Elimina'), findsNothing);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/ticket/ticket_detail_screen_test.dart --plain-name "generic Ticket header"`
Expected: FAIL — current header shows the ticket title, not `Ticket`, and there is no hero.

- [ ] **Step 3: Implement the shell + hero**

In `TicketDetailScreen.build`, replace the error/null/loading branches with `DetailScaffold.loading` / `DetailScaffold.unavailable`. In `_TicketDetailBody`:
- Return `DetailScaffold(screenTitle: 'Ticket', headerActions: [edit, assign, delete], hero: ..., expandedExtra: _TicketStatusRow(...), sections: [DetailSectionData(title: 'Attività', child: ...existing body...)])`.
- Move the edit/assign/delete `HeaderIconBtn`s from `_TicketDetailHeader` into `headerActions`; delete `_TicketDetailHeader`.
- Build `DetailHeroData` with `ticket.title`, `reference`, `DetailStatus(label: statusName)`, facts `Cliente`/`Sede`/`Tecnico`, `liveValue: TicketTimerLiveValue(ticketId: ticket.id)`, primary `ticketTimerAction(...)`, secondary `AI Copilot` + `Crea rapportino` when assigned.
- Keep the status row as `expandedExtra` so `Prendi in carico` remains reachable.
- Remove `_TicketTimerBar` and the fixed bottom action bar (`AI Copilot` / `Crea rapportino`), because both moved.
- Keep the existing summary card, map, compartment grid and all bottom sheets inside the temporary `Attività` section.

- [ ] **Step 4: Run the ticket tests**

Run: `flutter test test/features/ticket/ticket_detail_screen_test.dart`
Expected: PASS. Update `shows empty-state when ticket not found` to expect `UnavailableState` (the new frame), and fix any test that still expects the old fixed bottom bar or the old header title; preserve assertions on `ACME Srl`, `Sede Milano`, `Crea rapportino`, the compartment labels and the cantiere chip.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ticket/ticket_detail_screen.dart test/features/ticket/ticket_detail_screen_test.dart
git commit -m "refactor(ticket): move the ticket detail onto the shared shell"
```

---

### Task 8: Ticket four-section mapping

**Files:**
- Modify: `lib/features/ticket/ticket_detail_screen.dart`
- Modify: `test/features/ticket/ticket_detail_screen_test.dart`

**Interfaces:**
- Consumes: Task 7 ticket body.
- Produces: four `DetailSectionData` entries in this order: `Attività`, `Sintesi`, `Relazioni`, `Documenti & mappa`; a private `_TicketCompartmentGrid` helper that takes `List<String> labels` and a `Widget Function(String label) contentBuilder`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('renders the four ticket sections in order', (tester) async {
  await seedBase(db);
  await pump(tester);
  final attivita = tester.getTopLeft(find.text('Attività')).dy;
  final sintesi = tester.getTopLeft(find.text('Sintesi')).dy;
  final relazioni = tester.getTopLeft(find.text('Relazioni')).dy;
  final documenti = tester.getTopLeft(find.text('Documenti & mappa')).dy;
  expect(attivita, lessThan(sintesi));
  expect(sintesi, lessThan(relazioni));
  expect(relazioni, lessThan(documenti));
});

testWidgets('groups the nine compartments into the four sections', (tester) async {
  await seedBase(db);
  await pump(tester);
  expect(find.text('Ore'), findsOneWidget);
  expect(find.text('Storico'), findsOneWidget);
  expect(find.text('Dettagli'), findsOneWidget);
  expect(find.text('Pianificazioni'), findsOneWidget);
  expect(find.text('Fabbisogno'), findsOneWidget);
  expect(find.text('Asset'), findsOneWidget);
  expect(find.text('Report'), findsOneWidget);
  expect(find.text('Controllo'), findsOneWidget);
  expect(find.text('Allegati'), findsOneWidget);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/ticket/ticket_detail_screen_test.dart --plain-name "four ticket sections"`
Expected: FAIL — only one temporary section exists.

- [ ] **Step 3: Implement the mapping**

Replace the temporary `Attività` section with:
1. `Attività`: grid labels `Ore`, `Storico`.
2. `Sintesi`: the Contract/Commessa `KeyVal` rows plus a `Dettagli` tile. Do not repeat Cliente/Sede/Tecnico (they are hero facts).
3. `Relazioni`: the existing cantiere chip + grid labels `Pianificazioni`, `Fabbisogno`, `Asset`.
4. `Documenti & mappa`: `GeoMapCard` when the address is non-empty + grid labels `Report`, `Controllo`, `Allegati`.

Extract the repeated `GridView` into `_TicketCompartmentGrid`; pass `_sectionContent(label, ticket.id)` and the `Dettagli` special case exactly as today. Preserve `openCompartmentSheet` and every sheet's behaviour.

- [ ] **Step 4: Run the ticket tests**

Run: `flutter test test/features/ticket/ticket_detail_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ticket/ticket_detail_screen.dart test/features/ticket/ticket_detail_screen_test.dart
git commit -m "refactor(ticket): group the compartments into the four detail sections"
```

---

### Task 9: Verification

**Files:**
- No new files.

- [ ] **Step 1: Format and analyze**

Run:
```bash
dart format lib/core/widgets/detail lib/features/ticket/ticket_detail_screen.dart lib/features/ticket/ticket_timer_hero.dart test/core/widgets/detail test/features/ticket/ticket_detail_screen_test.dart test/features/ticket/ticket_timer_hero_test.dart
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 2: Run the focused suites**

Run:
```bash
flutter test test/core/widgets/detail
flutter test test/features/ticket
flutter test test/features/cantiere test/features/timbra
```
Expected: all pass.

- [ ] **Step 3: Verify the acceptance checks**

- Long title/fact does not overflow at 320px width.
- Offline ticket: hero action disabled with reason; the page still shows local facts and sections.
- Scroll down: collapsed bar appears; scroll up: it disappears; it never shows secondary actions.
- Unassigned ticket: `Prendi in carico` still works.
- Edit/assign/delete still obey the existing capability gates.
- `Crea rapportino` and `AI Copilot` still navigate to the same routes.
- `Dettagli`, `Report`, `Controllo`, `Allegati`, `Ore`, `Pianificazioni`, `Fabbisogno`, `Storico` sheets still open and render.

- [ ] **Step 4: Commit the verification fixes (if any)**

```bash
git add -A
git commit -m "chore(ticket): finish the detail shell migration"
```

---

## Self-review notes

- Spec coverage: Tasks 1–5 cover the shell, hero, section, sticky bar and states. Task 6 covers the ticket timer contract. Tasks 7–8 cover the ticket mapping and preserve existing behaviour. Task 9 verifies the spec's acceptance checks.
- Deliberate deferrals: Ticket is the only screen migrated here; rapportino/cantiere/admin stay for later core feats. The wizard is untouched. No new network reads.
- Placeholder risk: `_TicketCompartmentGrid` is introduced in Task 8, so Task 7's temporary section must keep the existing single grid working; do not delete the sheet builders.
- Type consistency: `DetailHeroData`, `DetailSectionData`, `DetailAction`, `TicketTimerLiveValue` and `ticketTimerAction` are defined once and consumed under the same names in later tasks.
