# Cantiere Timbra Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `CantiereTimbraScreen`'s check-in and active-session bodies around a flatter
hierarchy, a lead-only collapsed action menu instead of three stacked buttons, and a new
locally-derived "today's hours on this cantiere" total.

**Architecture:** No changes to the screen's state machine, providers' existing behavior, offline
event queue, sync push, reconciliation, or the batch-start API contract. All changes are confined
to `lib/features/timbra/cantiere_timbra_screen.dart`'s `_CheckInBody` and `_ActiveSessionBody`
widgets (both rewritten), one new derived provider (`cantiereTodayHoursProvider`), one new small
ticking widget for the live elapsed-time display, and the corresponding test file.

**Tech Stack:** Flutter, Riverpod (`Provider.autoDispose.family`), Drift (local SQLite),
`Ticker`/`SingleTickerProviderStateMixin` for live time display (same pattern already used by
`rapportino/step_ore.dart`'s `_RunningTimerBadge`).

**Spec:** `docs/superpowers/specs/2026-09-05-cantiere-timbra-redesign-design.md`

## Global Constraints

- No backend, queue, sync, reconciliation, or batch-start API changes — this is confined to the UI
  layer of `cantiere_timbra_screen.dart` plus one new provider in the same file.
- No crew-presence ("who else is on site") display, no rapportini-surfacing on this screen, no
  "Squadra · N persone" indicator — all explicitly deferred per the spec's Non-goals.
- `_handleStartCantiere`, `_handleSelectSquadra`, `_handleTuttaLaSquadra`, `_handleEndCantiere`,
  `_openDetailsSheet`, `_openClosingDetailsSheet` (all in `_CantiereTimbraScreenState`) are reused
  **unchanged** — no task in this plan modifies their bodies or signatures.
- `_CantiereCheckInDetailsForm`, `_CantiereClosingDetailsForm`, `_ErrorBanner`, `_ErrorBody`,
  `teammate_picker_sheet.dart` are reused **unchanged** — repositioned within the new layouts, not
  redesigned.
- "Today" is local-midnight-bounded, matching `CantiereSessionRepository._todayBounds()` exactly:
  `final start = DateTime(now.year, now.month, now.day).toUtc();` — any new code computing "start
  of today" must use this exact expression, not reinvent it.
- Hours are scoped to the single cantiere being displayed — never a cross-cantiere daily total.
- Elapsed/hours display format is `"{h}h {mm}m"` (zero-padded minutes, no seconds) — reuse
  `_ActiveSessionBody._formatElapsed`'s existing pattern, don't invent a second format.

---

### Task 1: `cantiereTodayHoursProvider` — closed-interval hours for one cantiere, today

**Files:**
- Modify: `lib/features/timbra/cantiere_timbra_screen.dart` (add near the other providers, after
  `cantiereHasPendingSyncProvider` at line ~120)
- Test: `test/features/timbra/cantiere_timbra_screen_test.dart` (new group)

**Interfaces:**
- Consumes: `todayCantiereEventsProvider` (existing, `StreamProvider.autoDispose<List<CantierePunche>>`),
  `CantierePunche` (existing Drift data class with fields `id`, `eventTime` (`DateTime`),
  `eventType` (`String`, one of `'ingresso'`/`'uscita'`), `cantiereId` (`String?`), `isPendingSync` (`bool`)).
- Produces: `final cantiereTodayHoursProvider = Provider.autoDispose.family<Duration, String>(...)`
  — later tasks watch this as `ref.watch(cantiereTodayHoursProvider(cantiereId))`.

- [ ] **Step 1: Write the failing tests**

Add this new group to `test/features/timbra/cantiere_timbra_screen_test.dart`, right after the
`'lead branching'` group closes (after line 1020, before the file's closing `}`):

`cantiereTodayHoursProvider` is a plain `Provider` (not a `FutureProvider`), derived from the
`StreamProvider` `todayCantiereEventsProvider` — reading it requires letting that stream emit its
first value before the read, via `container.listen(...)` followed by a zero-duration delay (the
pattern used throughout this group below).

```dart
  group('cantiereTodayHoursProvider', () {
    ProviderContainer buildContainer(AppDatabase db) => ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );

    Future<void> punch(
      AppDatabase db, {
      required String id,
      required DateTime eventTime,
      required String eventType,
      String? cantiereId,
    }) => db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: id,
            eventTime: eventTime,
            eventType: eventType,
            cantiereId: Value(cantiereId),
          ),
        );

    test('sums a single closed ingresso→uscita interval for the given cantiere', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8).toUtc();

      await punch(db, id: 'e1', eventTime: start, eventType: 'ingresso', cantiereId: 'cant-1');
      await punch(
        db,
        id: 'e2',
        eventTime: start.add(const Duration(hours: 3)),
        eventType: 'uscita',
      );

      // Let the StreamProvider this derives from emit its first value.
      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, const Duration(hours: 3));
    });

    test('ignores events for a different cantiere', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8).toUtc();

      await punch(db, id: 'e1', eventTime: start, eventType: 'ingresso', cantiereId: 'cant-OTHER');
      await punch(
        db,
        id: 'e2',
        eventTime: start.add(const Duration(hours: 3)),
        eventType: 'uscita',
      );

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, Duration.zero);
    });

    test('excludes a still-open interval (no matching uscita yet)', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final closedStart = DateTime(today.year, today.month, today.day, 7).toUtc();

      await punch(
        db,
        id: 'e1',
        eventTime: closedStart,
        eventType: 'ingresso',
        cantiereId: 'cant-1',
      );
      await punch(
        db,
        id: 'e2',
        eventTime: closedStart.add(const Duration(hours: 2)),
        eventType: 'uscita',
      );
      // A second, still-open interval later the same day.
      await punch(
        db,
        id: 'e3',
        eventTime: closedStart.add(const Duration(hours: 4)),
        eventType: 'ingresso',
        cantiereId: 'cant-1',
      );

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      // Only the first, closed 2h interval counts — the open 'ingresso' with no 'uscita' after it
      // must not contribute anything (that portion is the live-ticking concern, not this provider).
      expect(result, const Duration(hours: 2));
    });

    test('sums multiple closed intervals for the same cantiere', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);
      final today = DateTime.now();
      final s1 = DateTime(today.year, today.month, today.day, 7).toUtc();
      final s2 = DateTime(today.year, today.month, today.day, 12).toUtc();

      await punch(db, id: 'e1', eventTime: s1, eventType: 'ingresso', cantiereId: 'cant-1');
      await punch(db, id: 'e2', eventTime: s1.add(const Duration(hours: 2)), eventType: 'uscita');
      await punch(db, id: 'e3', eventTime: s2, eventType: 'ingresso', cantiereId: 'cant-1');
      await punch(
        db,
        id: 'e4',
        eventTime: s2.add(const Duration(minutes: 90)),
        eventType: 'uscita',
      );

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, const Duration(hours: 3, minutes: 30));
    });

    test('returns Duration.zero when there are no events at all', () async {
      final container = buildContainer(db);
      addTearDown(container.dispose);

      container.listen(todayCantiereEventsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final result = container.read(cantiereTodayHoursProvider('cant-1'));

      expect(result, Duration.zero);
    });
  });
```

The group above contains exactly five `test(...)` blocks — write all five into the test file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "cantiereTodayHoursProvider"`
Expected: FAIL — `cantiereTodayHoursProvider` is not defined (compile error).

- [ ] **Step 3: Implement the provider**

In `lib/features/timbra/cantiere_timbra_screen.dart`, add immediately after the existing
`cantiereHasPendingSyncProvider` definition (which ends around line 120):

```dart
/// Sums today's *closed* (ingresso→uscita) intervals on [cantiereId] into a total duration.
///
/// Deliberately excludes a still-open interval at the end of the list — that portion needs a
/// live per-second tick to stay accurate, which a value recomputed only when the event list
/// changes can't give you. The UI combines this closed-interval total with a separately-ticking
/// "current session" elapsed widget (see `_CantiereElapsedTicker`) to show the running total.
///
/// Scoped to one cantiere (not a cross-cantiere daily total) — matches the screen's own context:
/// "how much have I worked *here* today."
final cantiereTodayHoursProvider = Provider.autoDispose.family<Duration, String>((
  ref,
  cantiereId,
) {
  final events = ref.watch(todayCantiereEventsProvider).valueOrNull ?? [];
  CantierePunche? opener;
  var total = Duration.zero;
  for (final e in events) {
    switch (e.eventType) {
      case 'ingresso':
        opener = e;
      case 'uscita':
        if (opener != null && opener.cantiereId == cantiereId) {
          total += e.eventTime.difference(opener.eventTime);
        }
        opener = null;
    }
  }
  return total;
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "cantiereTodayHoursProvider"`
Expected: PASS (5/5).

- [ ] **Step 5: Run the full existing test file to confirm no regressions**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: PASS (all pre-existing tests unaffected — this task only adds a new provider and new
tests, touching nothing else).

- [ ] **Step 6: Commit**

```bash
git add lib/features/timbra/cantiere_timbra_screen.dart test/features/timbra/cantiere_timbra_screen_test.dart
git commit -m "feat(cantiere): add cantiereTodayHoursProvider for closed-interval daily hours"
```

---

### Task 2: Shared elapsed-formatting helper and a live-ticking elapsed widget

**Files:**
- Modify: `lib/features/timbra/cantiere_timbra_screen.dart`
- Test: `test/features/timbra/cantiere_timbra_screen_test.dart` (new group)

**Interfaces:**
- Consumes: nothing new (pure `DateTime`/`Duration` math + `Ticker`).
- Produces:
  - `String formatHoursMinutes(Duration d)` — top-level function, replaces
    `_ActiveSessionBody._formatElapsed`'s private static method so both the check-in header and
    the active-session body can share it. Later tasks call `formatHoursMinutes(...)`.
  - `Duration clampedElapsedSinceMidnight(DateTime startTime, DateTime now)` — top-level function.
    Returns `now.difference(startTime)` when `startTime` is already on-or-after local midnight
    (UTC-normalized the same way `CantiereSessionRepository._todayBounds()` does), otherwise
    returns `now.difference(todayStartUtc)` — clamping an overnight session's elapsed reading to
    only the since-midnight portion. Later tasks use this inside the ticking widget.
  - `class _CantiereElapsedTicker extends StatefulWidget` — constructor
    `const _CantiereElapsedTicker({required DateTime startTime, required TextStyle style})`.
    Ticks once a second, rendering `Text(formatHoursMinutes(clampedElapsedSinceMidnight(startTime, DateTime.now())), style: style)`.
    Later tasks (`_ActiveSessionBody`) use this both for the "current session" elapsed display
    (unclamped conceptually, but clamping is always safe/a no-op for a session that started today)
    and, added to `cantiereTodayHoursProvider`'s value, for the live "OGGI" total.

- [ ] **Step 1: Write the failing tests**

Add this new group to `test/features/timbra/cantiere_timbra_screen_test.dart`, after the
`cantiereTodayHoursProvider` group added in Task 1:

```dart
  group('formatHoursMinutes', () {
    test('formats whole hours with zero minutes', () {
      expect(formatHoursMinutes(const Duration(hours: 2)), '2h 00m');
    });

    test('formats hours and minutes, zero-padded', () {
      expect(formatHoursMinutes(const Duration(hours: 6, minutes: 5)), '6h 05m');
    });

    test('formats zero duration', () {
      expect(formatHoursMinutes(Duration.zero), '0h 00m');
    });
  });

  group('clampedElapsedSinceMidnight', () {
    test('returns the full elapsed time when startTime is already today', () {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8).toUtc();
      final now = start.add(const Duration(hours: 1, minutes: 18));

      expect(clampedElapsedSinceMidnight(start, now), const Duration(hours: 1, minutes: 18));
    });

    test('clamps to since-midnight when startTime was yesterday', () {
      final today = DateTime.now();
      final todayMidnightUtc = DateTime(today.year, today.month, today.day).toUtc();
      final start = todayMidnightUtc.subtract(const Duration(hours: 5)); // started yesterday
      final now = todayMidnightUtc.add(const Duration(hours: 2));

      // Only the 2h since midnight counts, not the 5h before it.
      expect(clampedElapsedSinceMidnight(start, now), const Duration(hours: 2));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "formatHoursMinutes"`
Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "clampedElapsedSinceMidnight"`
Expected: both FAIL — neither function exists yet (compile error).

- [ ] **Step 3: Implement the helpers and the ticking widget**

In `lib/features/timbra/cantiere_timbra_screen.dart`, add these top-level (module-level, outside
any class) right after the `cantiereTodayHoursProvider` definition from Task 1:

```dart
/// "Xh Ym" — zero-padded minutes, no seconds. Shared by the check-in body's "OGGI" header and the
/// active-session body's hero card (previously duplicated as `_ActiveSessionBody._formatElapsed`).
String formatHoursMinutes(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${h}h ${m}m';
}

/// Elapsed time since [startTime], clamped so it never counts time before local midnight — a
/// session that started yesterday and is still open must only contribute its since-midnight
/// portion to a "today" reading. Uses the exact same midnight expression as
/// `CantiereSessionRepository._todayBounds()`.
Duration clampedElapsedSinceMidnight(DateTime startTime, DateTime now) {
  final today = DateTime.now();
  final todayStartUtc = DateTime(today.year, today.month, today.day).toUtc();
  final effectiveStart = startTime.isAfter(todayStartUtc) ? startTime : todayStartUtc;
  return now.difference(effectiveStart);
}

/// Live-ticking elapsed-time text, clamped to today (see [clampedElapsedSinceMidnight]). Same
/// Ticker-based pattern as `rapportino/step_ore.dart`'s `_RunningTimerBadge`.
class _CantiereElapsedTicker extends StatefulWidget {
  const _CantiereElapsedTicker({required this.startTime, required this.style});

  final DateTime startTime;
  final TextStyle style;

  @override
  State<_CantiereElapsedTicker> createState() => _CantiereElapsedTickerState();
}

class _CantiereElapsedTickerState extends State<_CantiereElapsedTicker>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = clampedElapsedSinceMidnight(widget.startTime, DateTime.now());
    return Text(formatHoursMinutes(elapsed), style: widget.style);
  }
}
```

Do not remove `_ActiveSessionBody._formatElapsed` yet — Task 4 rewrites `_ActiveSessionBody`
entirely and removes it then. Leaving it in place for this task keeps the file compiling with
`_ActiveSessionBody` unchanged.

Note: `Ticker` requires importing `package:flutter/scheduler.dart` — check the top of
`cantiere_timbra_screen.dart`'s import list; if it's not already imported (it likely isn't, since
this file has no existing ticker), add `import 'package:flutter/scheduler.dart';` alongside the
other Flutter imports.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "formatHoursMinutes"`
Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "clampedElapsedSinceMidnight"`
Expected: both PASS.

- [ ] **Step 5: Run the full existing test file to confirm no regressions**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/timbra/cantiere_timbra_screen.dart test/features/timbra/cantiere_timbra_screen_test.dart
git commit -m "feat(cantiere): add shared hours formatter and midnight-clamped elapsed ticker"
```

---

### Task 3: Redesign `_CheckInBody` — OGGI header, single button, lead-only menu

**Files:**
- Modify: `lib/features/timbra/cantiere_timbra_screen.dart` (`_CheckInBody` class, currently lines
  765-1147, and its instantiation site inside `_CantiereTimbraScreenState.build()`, currently
  around line 341)
- Test: `test/features/timbra/cantiere_timbra_screen_test.dart`

**Interfaces:**
- Consumes: `cantiereTodayHoursProvider` and `formatHoursMinutes` (Task 1/2). `AppButton`,
  `AppButton.secondary` (existing, `lib/core/widgets/app_button.dart` — `AppButton({required
  String label, VoidCallback? onPressed, Widget? icon, bool isLoading, ...})`).
  `isLeadForCantiereProvider` (existing, unchanged). `onStart`, `onSelectSquadra`,
  `onTuttaLaSquadra`, `onOpenDetails`, `onCantiereSelected` callbacks (existing, unchanged
  signatures — still `VoidCallback`/`ValueChanged<CantieriData?>` respectively).
- Produces: `_CheckInBody` becomes a `ConsumerWidget` (was `StatelessWidget`) with one new
  constructor parameter, `cantiereId` (`String?` — the resolved cantiere's id, or null before one
  is picked in picker mode). The call site in `_CantiereTimbraScreenState.build()` passes
  `cantiereId: effectiveCantiereId` (the variable already computed at line 310, reused as-is —
  no new state needed).

- [ ] **Step 1: Write the failing tests**

Add this group to `test/features/timbra/cantiere_timbra_screen_test.dart`, after the
`clampedElapsedSinceMidnight` group from Task 2:

```dart
  group('check-in body — OGGI header and lead menu', () {
    testWidgets('shows OGGI 0h 00m when no hours logged yet today', (tester) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient();

      await tester.pumpWidget(_buildScreen(db: db, apiClient: api, currentUser: _testUser));
      await tester.pumpAndSettle();

      expect(find.text('OGGI'), findsOneWidget);
      expect(find.text('0h 00m'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('OGGI total reflects a closed interval logged earlier today', (tester) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 7).toUtc();
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e1',
              eventTime: start,
              eventType: 'ingresso',
              cantiereId: const Value('cant-1'),
            ),
          );
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e2',
              eventTime: start.add(const Duration(hours: 2, minutes: 30)),
              eventType: 'uscita',
            ),
          );

      final api = _FakeApiClient();
      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('2h 30m'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('shows a single Inizia timbratura button and no menu for a non-lead', (
      tester,
    ) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient(
        assegnazioni: const [CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: false)],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
      expect(find.textContaining('Per:'), findsNothing);

      await _teardown(tester);
    });

    testWidgets('shows the Inizia timbratura button plus a Per: Me menu for a lead', (
      tester,
    ) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient(
        assegnazioni: const [
          CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
          CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
      expect(find.textContaining('Per: Me'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('tapping Inizia timbratura starts solo, for a lead or non-lead alike', (
      tester,
    ) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient(
        assegnazioni: const [CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true)],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inizia timbratura'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.startedRequests, hasLength(1));
      expect(api.batchStartRequests, isEmpty);

      await _teardown(tester);
    });

    testWidgets('picking Squadra from the Per menu opens the teammate picker', (tester) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient(
        assegnazioni: const [
          CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
          CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Per: Me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squadra'));
      await tester.pumpAndSettle();

      // The teammate picker sheet is now open (same sheet _handleSelectSquadra always opened).
      expect(find.text('teammate-1'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('picking Me e squadra from the Per menu batch-starts everyone', (tester) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient(
        assegnazioni: const [
          CantiereCrewAssignmentDto(id: 'a1', userId: 'me', isLead: true),
          CantiereCrewAssignmentDto(id: 'a2', userId: 'teammate-1', isLead: false),
        ],
      );

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Per: Me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Me e squadra'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.batchStartRequests, hasLength(1));
      expect(
        api.batchStartRequests.first.userIds,
        unorderedEquals(['me', 'teammate-1']),
      );

      await _teardown(tester);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "check-in body"`
Expected: FAIL — `'OGGI'`/`'Inizia timbratura'`/`'Per: Me'` text not found (the old layout has
neither), and `_CheckInBody`'s constructor doesn't yet accept `cantiereId`.

- [ ] **Step 3: Rewrite `_CheckInBody`**

Replace the entire `_CheckInBody` class (currently lines 765-1147) with:

```dart
class _CheckInBody extends ConsumerWidget {
  const _CheckInBody({
    required this.customerId,
    required this.ticketId,
    required this.cantieriAsync,
    required this.selectedCantiere,
    required this.cantiereId,
    required this.showPicker,
    this.fixedCantiereAsync,
    required this.isLoading,
    required this.errorMessage,
    required this.hasDetails,
    required this.isLead,
    required this.onCantiereSelected,
    required this.onStart,
    required this.onSelectSquadra,
    required this.onTuttaLaSquadra,
    required this.onOpenDetails,
  });

  final String? customerId;
  final String? ticketId;
  final AsyncValue<List<CantieriData>> cantieriAsync;
  final CantieriData? selectedCantiere;

  /// The resolved cantiere's id, or null before one is picked (picker mode, nothing tapped yet).
  /// Feeds the "OGGI" header's `cantiereTodayHoursProvider` watch — null shows a static "0h 00m"
  /// with no provider call, since there is nothing to scope hours to yet.
  final String? cantiereId;

  /// When false, the cantiere picker (section header + selectable list) is skipped in favour of a
  /// compact fixed-cantiere card — the direct-entry path (`CantiereTimbraScreen.cantiereId` set).
  final bool showPicker;

  /// The fixed cantiere's own load state (direct-entry mode only — null when `showPicker` is
  /// true). Carried separately from `selectedCantiere` because a plain `CantieriData?` can't tell
  /// "still loading" apart from "resolved to nothing found" — the fixed-cantiere card below needs
  /// that distinction so a not-found cantiere doesn't read as a permanent spinner.
  final AsyncValue<CantieriData?>? fixedCantiereAsync;
  final bool isLoading;
  final String? errorMessage;
  final bool hasDetails;

  /// Whether the current user is the lead on the resolved cantiere — gates the "Per: Me ▾" menu
  /// below the main button. False while no cantiere is resolved yet, on fetch error, or offline
  /// (see isLeadForCantiereProvider) — the explicit fallback to the plain single-button flow.
  final bool isLead;
  final ValueChanged<CantieriData?> onCantiereSelected;
  final VoidCallback onStart;
  final VoidCallback onSelectSquadra;
  final VoidCallback onTuttaLaSquadra;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantieriValue = cantieriAsync.valueOrNull;
    final noCantieriAvailable = showPicker && cantieriValue != null && cantieriValue.isEmpty;
    final noFixedCantiere = !showPicker && selectedCantiere == null;

    final todayHours = cantiereId != null
        ? ref.watch(cantiereTodayHoursProvider(cantiereId!))
        : Duration.zero;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "OGGI" header — plain text hierarchy, not another elevated card, per the redesign's
          // own stated reasoning: stacking a card onto an already-card-heavy screen would just be
          // clutter restyled, not clutter removed.
          Text(
            'OGGI',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatHoursMinutes(todayHours),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: context.colors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: context.colors.borderLight, height: 1),
          const SizedBox(height: 16),

          // Context banner (linked ticket)
          if (ticketId != null) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.link, size: 16, color: context.colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collegato al ticket',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (showPicker) ...[
            Text(
              'Cantiere',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: 8),

            cantieriAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                child: Text(
                  'Impossibile caricare i cantieri.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: context.colors.red),
                ),
              ),
              data: (cantieri) {
                final preferred = customerId != null
                    ? cantieri.where((c) => c.customerId == customerId).toList()
                    : <CantieriData>[];
                final others = cantieri.where((c) => !preferred.contains(c)).toList();
                final ordered = [...preferred, ...others];

                if (ordered.isEmpty) {
                  return const UnavailableState(
                    icon: LucideIcons.hardHat,
                    titolo: 'Nessun cantiere disponibile',
                    motivo:
                        'Non risultano cantieri attivi sincronizzati su questo dispositivo. Se ne '
                        'è stato creato uno di recente, apri una qualsiasi scheda e trascina in '
                        'basso per aggiornare, oppure riprova tra poco.',
                  );
                }

                return AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: ordered.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value;
                      final isSelected = selectedCantiere?.id == c.id;
                      final isLast = i == ordered.length - 1;

                      return InkWell(
                        onTap: () => onCantiereSelected(c),
                        borderRadius: i == 0
                            ? const BorderRadius.vertical(top: Radius.circular(20))
                            : (isLast
                                  ? const BorderRadius.vertical(bottom: Radius.circular(20))
                                  : BorderRadius.zero),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.base,
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.Y.withAlpha(31) : Colors.transparent,
                            border: isLast
                                ? null
                                : Border(bottom: BorderSide(color: context.colors.borderLight)),
                          ),
                          child: Row(
                            children: [
                              const RowIconTile(icon: LucideIcons.hardHat),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: context.colors.ink,
                                      ),
                                    ),
                                    if (c.city != null && c.city!.isNotEmpty)
                                      Text(
                                        c.city!,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          color: context.colors.inkMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(LucideIcons.checkCircle2, size: 18, color: AppColors.Y),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ] else
            AppCard(
              child:
                  fixedCantiereAsync?.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.base),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                      child: Text(
                        'Impossibile caricare il cantiere.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: context.colors.red,
                        ),
                      ),
                    ),
                    data: (c) => c == null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                            child: Text(
                              'Cantiere non trovato su questo dispositivo.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: context.colors.red,
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              Icon(LucideIcons.hardHat, size: 18, color: context.colors.ink),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ) ??
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.base),
                      child: CircularProgressIndicator(),
                    ),
                  ),
            ),

          const SizedBox(height: 16),

          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          AppButton(
            label: 'Inizia timbratura',
            icon: const Icon(LucideIcons.mapPin),
            isLoading: isLoading,
            onPressed: (isLoading || noCantieriAvailable || noFixedCantiere) ? null : onStart,
          ),

          if (isLead) ...[
            const SizedBox(height: 8),
            Center(
              child: PopupMenuButton<VoidCallback>(
                enabled: !(isLoading || noCantieriAvailable || noFixedCantiere),
                onSelected: (handler) => handler(),
                itemBuilder: (context) => [
                  PopupMenuItem(value: onSelectSquadra, child: const Text('Squadra')),
                  PopupMenuItem(value: onTuttaLaSquadra, child: const Text('Me e squadra')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Per: Me',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.inkMuted,
                        ),
                      ),
                      Icon(LucideIcons.chevronDown, size: 16, color: context.colors.inkMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: AppTappable(
                onTap: onOpenDetails,
                borderRadius: AppRack.insetShape,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.base,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasDetails ? LucideIcons.checkCircle2 : LucideIcons.plus,
                      size: 14,
                      color: hasDetails ? context.colors.green : context.colors.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasDetails ? 'Altri dettagli aggiunti' : 'Altri dettagli',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasDetails ? context.colors.green : context.colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Note on the "Per: Me" menu label: it's always literally "Per: Me" (never changes to "Per:
Squadra" or similar) because selecting a menu item fires its action immediately — there is no
persisted "current scope" to reflect in the label, matching the spec's explicit design ("not a
persisted selection the main button later acts on"). This is deliberate, not a bug — the menu is a
one-shot action picker, not a stateful mode switch.

Now update the instantiation site inside `_CantiereTimbraScreenState.build()` (currently around
line 341-357) to pass the new `cantiereId` parameter — change:

```dart
                  : _CheckInBody(
                      customerId: widget.customerId,
                      ticketId: widget.ticketId,
                      cantieriAsync: cantieriAsync,
                      selectedCantiere: _effectiveCantiere,
                      showPicker: widget.cantiereId == null,
```

to:

```dart
                  : _CheckInBody(
                      customerId: widget.customerId,
                      ticketId: widget.ticketId,
                      cantieriAsync: cantieriAsync,
                      selectedCantiere: _effectiveCantiere,
                      cantiereId: effectiveCantiereId,
                      showPicker: widget.cantiereId == null,
```

(`effectiveCantiereId` is the existing local variable at line 310 — no new state, just threading
an already-computed value one level deeper.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "check-in body"`
Expected: PASS (7/7).

- [ ] **Step 5: Run the full existing test file**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: the new groups pass; the pre-existing `'no active session'` group's tests that assert
the OLD button text (`'Timbra ingresso cantiere'`) will now FAIL, since the button is renamed to
`'Inizia timbratura'` — expected at this point in the plan. Update those specific assertions now:
in the `'no active session'` group, every `find.text('Timbra ingresso cantiere')` becomes
`find.text('Inizia timbratura')` (there are three such tests: `'renders Timbra ingresso cantiere
button'` around line 247, `'check-in calls startCantiere with correct ids'` around line 315, and
`'shows validation error when no cantiere selected and clock-in tapped'` around line 355 — rename
the assertion text and, for the first, the test's own description string too, e.g. `'renders
Inizia timbratura button'`). Also update the `'direct-entry mode'` group's occurrences of the same
button text the same way (search the whole file for `'Timbra ingresso cantiere'` and replace every
occurrence — do not touch `'Timbra uscita cantiere'`, the clock-out button, which Task 4 handles).
The `'lead branching'` group's own failures are handled entirely in Task 5 — do not touch that
group in this task.

Re-run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: every group except `'lead branching'` passes. `'lead branching'` failures are expected
and handled by Task 5.

- [ ] **Step 6: Commit**

```bash
git add lib/features/timbra/cantiere_timbra_screen.dart test/features/timbra/cantiere_timbra_screen_test.dart
git commit -m "feat(cantiere): redesign check-in body with OGGI header and collapsed lead menu"
```

---

### Task 4: Redesign `_ActiveSessionBody` — OGGI header, live ticker, restyled hero

**Files:**
- Modify: `lib/features/timbra/cantiere_timbra_screen.dart` (`_ActiveSessionBody` class, currently
  lines 1319-1509)
- Test: `test/features/timbra/cantiere_timbra_screen_test.dart`

**Interfaces:**
- Consumes: `cantiereTodayHoursProvider`, `formatHoursMinutes`, `clampedElapsedSinceMidnight`,
  `_CantiereElapsedTicker` (Tasks 1/2). `CantiereActiveSession.cantiereId` (existing field, used to
  scope the OGGI provider watch — no change to `CantiereActiveSession` itself).
- Produces: `_ActiveSessionBody`'s own `_formatElapsed` static method is removed (superseded by the
  shared `formatHoursMinutes`); everything else about its constructor is unchanged (still
  `local`, `serverLog`, `hasPendingSync`, `hasClosingDetails`, `isLoading`, `errorMessage`, `onEnd`,
  `onOpenClosingDetails` — no signature change, no instantiation-site change needed).

- [ ] **Step 1: Write the failing tests**

Add this group to `test/features/timbra/cantiere_timbra_screen_test.dart`, after the "check-in
body" group from Task 3:

```dart
  group('active session body — OGGI header and live elapsed', () {
    testWidgets('shows OGGI total plus the live current-session elapsed', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('OGGI'), findsOneWidget);
      expect(find.byType(_CantiereElapsedTicker), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('shows TIMBRATURA ATTIVA and the cantiere name', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('TIMBRATURA ATTIVA'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('still shows the pending-sync indicator when a punch has not synced', (
      tester,
    ) async {
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e1',
              eventTime: DateTime.utc(2026, 6, 23, 8),
              eventType: 'ingresso',
              cantiereId: const Value('cant-1'),
            ),
          );
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Non sincronizzata'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('still shows Timbra uscita cantiere and ends the session on tap', (tester) async {
      final api = _FakeApiClient(activeLog: _activeLog());
      await tester.pumpWidget(_buildScreen(db: db, apiClient: api));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Timbra uscita cantiere'));
      await tester.tap(find.text('Timbra uscita cantiere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.endCalled, isTrue);
      await _teardown(tester);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "active session body"`
Expected: FAIL — `'OGGI'`, `_CantiereElapsedTicker`, `'TIMBRATURA ATTIVA'` not present in the old
layout (old layout has `'IN CANTIERE'`, not `'TIMBRATURA ATTIVA'`).

- [ ] **Step 3: Rewrite `_ActiveSessionBody`**

Replace the entire `_ActiveSessionBody` class (currently lines 1319-1509) with:

```dart
class _ActiveSessionBody extends ConsumerWidget {
  const _ActiveSessionBody({
    required this.local,
    required this.serverLog,
    required this.hasPendingSync,
    required this.hasClosingDetails,
    required this.isLoading,
    required this.errorMessage,
    required this.onEnd,
    required this.onOpenClosingDetails,
  });

  final CantiereActiveSession local;
  final CantiereWorkLogDto? serverLog;
  final bool hasPendingSync;
  final bool hasClosingDetails;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onEnd;
  final VoidCallback onOpenClosingDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketId = serverLog?.ticketId ?? local.ticketId;
    final ticketLabel = ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(ticketId)).valueOrNull?.title;

    final closedTodayHours = ref.watch(cantiereTodayHoursProvider(local.cantiereId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "OGGI" header — same visual continuity as the check-in body, with the live-ticking
          // current-session elapsed folded into the total once it starts. Watching
          // cantiereTodayHoursProvider (closed intervals only) here, then adding the ticker's own
          // live elapsed separately, keeps the "closed sum" and "live tick" concerns apart the
          // same way they're computed apart.
          Text(
            'OGGI',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          _CantiereTodayTotal(closedHours: closedTodayHours, sessionStart: local.startTime),
          const SizedBox(height: 16),
          Divider(color: context.colors.borderLight, height: 1),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Text(
                  'TIMBRATURA ATTIVA',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: context.vetro.statusGood,
                  ),
                ),
              ),
              if (hasPendingSync)
                Tooltip(
                  message: 'Non sincronizzata',
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: context.colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ticketLabel != null
                ? '${_cantiereNameFor(ref, local.cantiereId)} · $ticketLabel'
                : _cantiereNameFor(ref, local.cantiereId),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: _CantiereElapsedTicker(
              startTime: local.startTime,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: context.colors.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: AppTappable(
                onTap: onOpenClosingDetails,
                borderRadius: AppRack.insetShape,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.base,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasClosingDetails ? LucideIcons.checkCircle2 : LucideIcons.plus,
                      size: 14,
                      color: hasClosingDetails ? context.colors.green : context.colors.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasClosingDetails ? 'Note di chiusura aggiunte' : 'Note di chiusura',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasClosingDetails ? context.colors.green : context.colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          AppButton.danger(
            label: 'Timbra uscita cantiere',
            icon: const Icon(LucideIcons.logOut),
            isLoading: isLoading,
            onPressed: isLoading ? null : onEnd,
          ),
        ],
      ),
    );
  }
}
```

The card above needs two more pieces that didn't exist in the old layout (which only showed
Data/Ingresso/Ticket as separate `KeyVal` rows, never the cantiere's name): a helper to resolve
the cantiere's name from the local mirror, and the widget that combines the closed-interval sum
with the live ticker for the "OGGI" total. Add this top-level function right after
`formatHoursMinutes`:

```dart
/// Resolves a cantiere's name from the local mirror for display on the active-session card —
/// falls back to the raw id if the mirror doesn't have it yet (matches the same
/// not-found-falls-back-to-itself contract used elsewhere in this screen, e.g. colleague names).
String _cantiereNameFor(WidgetRef ref, String cantiereId) {
  return ref.watch(cantiereByIdProvider(cantiereId)).valueOrNull?.name ?? cantiereId;
}
```

And add a small private widget for the OGGI total that combines the closed-interval sum with the
live ticker's own elapsed reading, right after `_CantiereElapsedTicker`:

```dart
/// The "OGGI" total on the active-session card: closed-interval hours (recomputed only when the
/// event list changes) plus the live-ticking current session — added together and re-rendered
/// every tick, so the grand total visibly climbs in real time while checked in.
class _CantiereTodayTotal extends StatefulWidget {
  const _CantiereTodayTotal({required this.closedHours, required this.sessionStart});

  final Duration closedHours;
  final DateTime sessionStart;

  @override
  State<_CantiereTodayTotal> createState() => _CantiereTodayTotalState();
}

class _CantiereTodayTotalState extends State<_CantiereTodayTotal>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveElapsed = clampedElapsedSinceMidnight(widget.sessionStart, DateTime.now());
    return Text(
      formatHoursMinutes(widget.closedHours + liveElapsed),
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: context.colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
```

`KeyVal` is no longer used anywhere in this file once this task is done — leave its import in
place regardless (it may still be used elsewhere via the same import statement; do not remove the
import without first checking the rest of the file has no other `KeyVal` usage — a quick
`grep -n "KeyVal" lib/features/timbra/cantiere_timbra_screen.dart` after this task should show
zero remaining usages, in which case remove the now-unused import to keep `flutter analyze` clean).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart --plain-name "active session body"`
Expected: PASS (4/4).

- [ ] **Step 5: Run the full existing test file**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: pre-existing `'active session'` group tests that assert old-layout-specific text
(`'IN CANTIERE'`, `KeyVal` rows via `'Data'`/`'Ingresso'` labels, or the HH:mm ingresso-time
label) will now fail — expected. Update them: replace `expect(find.text('IN CANTIERE'), ...)`
with `expect(find.text('TIMBRATURA ATTIVA'), ...)` in `'shows IN CANTIERE indicator'` (rename the
test description too, e.g. `'shows TIMBRATURA ATTIVA indicator'`). The `'shows ingresso time from
active log'` test (asserting a raw `HH:mm` label) no longer applies — the new layout doesn't show
a separate ingresso-time row — delete that test. The `'names the linked ticket...'` and `'drops
the row entirely when the mirror does not hold the ticket'` tests should still pass unchanged
(the ticket label still renders as plain text, now inline with the cantiere name rather than a
`KeyVal` row — their `find.text('Sostituzione pompa')`/`find.textContaining('tick-1')` assertions
don't depend on which container renders it).

Re-run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: every group passes except `'lead branching'` (Task 5).

- [ ] **Step 6: Commit**

```bash
git add lib/features/timbra/cantiere_timbra_screen.dart test/features/timbra/cantiere_timbra_screen_test.dart
git commit -m "feat(cantiere): redesign active-session body with OGGI header and live ticker"
```

---

### Task 5: Rewrite the `'lead branching'` test group for the new menu

**Files:**
- Modify: `test/features/timbra/cantiere_timbra_screen_test.dart` (the `'lead branching'` group,
  currently lines 684-1020)

**Interfaces:**
- Consumes: the new `_CheckInBody` layout from Task 3 (button text `'Inizia timbratura'`, menu
  trigger text containing `'Per: Me'`, menu item texts `'Squadra'` and `'Me e squadra'`).
- Produces: nothing new — this task only adapts existing test bodies to interact through the new
  UI, preserving every existing assertion about `_FakeApiClient`'s recorded calls
  (`startedRequests`, `batchStartRequests`, the failures dialog text, the success-count toast
  text).

- [ ] **Step 1: Replace the three UI-presence tests**

Replace these three tests (identified in Task 3's Step 1 test additions as covering the same
ground more precisely — remove the old, now-redundant versions entirely rather than keeping both):

- `'shows the three-way choice for a lead, instead of the single button'` (old lines 696-719)
- `'shows exactly the single button for a non-lead, with no branching prompt'` (old lines 721-741)
- `'shows exactly the single button when the assignment fetch fails (offline fallback)'` (old
  lines 743-761)

Delete all three — Task 3's `'shows a single Inizia timbratura button and no menu for a non-lead'`
and `'shows the Inizia timbratura button plus a Per: Me menu for a lead'` already cover the
lead/non-lead cases with the new UI. Add one more test to Task 3's `'check-in body'` group instead
(covering the offline-fallback case Task 3 didn't add), right after `'shows the Inizia timbratura
button plus a Per: Me menu for a lead'`:

```dart
    testWidgets('shows no Per menu when the assignment fetch fails (offline fallback)', (
      tester,
    ) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Via Roma',
            ),
          );
      final api = _FakeApiClient(assegnazioniShouldThrow: true);

      await tester.pumpWidget(
        _buildScreen(db: db, apiClient: api, cantiereId: 'cant-1', currentUser: _testUser),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inizia timbratura'), findsOneWidget);
      expect(find.textContaining('Per:'), findsNothing);

      await _teardown(tester);
    });
```

- [ ] **Step 2: Rewrite the four action-outcome tests to reach their action via the menu**

Keep these four tests' bodies and assertions — only change how the action is reached (open the
menu, then tap the item, instead of tapping a dedicated button):

**`'"Tutta la squadra" calls batchStart with every assigned userId'`** (old lines 763-800) — the
`await tester.ensureVisible(find.text('Tutta la squadra')); await tester.tap(find.text('Tutta la
squadra'));` becomes:

```dart
        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Me e squadra'));
```

**`'names every offender when batch-start partially fails, without dropping anyone'`** (old lines
802-850) — same replacement (this test also uses `'Tutta la squadra'` to trigger the batch call).

**`'"Seleziona squadra" calls batchStart with only the checked subset of userIds'`** (old lines
852-899) — the `await tester.ensureVisible(find.text('Seleziona squadra')); await tester.tap(
find.text('Seleziona squadra'));` becomes:

```dart
        await tester.tap(find.textContaining('Per: Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Squadra'));
```

**`'shows a success toast counting how many people were actually started'`** (old lines 901-931)
— same replacement as the first (uses `'Tutta la squadra'`).

**`'still shows the success-count toast alongside the failures dialog on a partial success'`**
(old lines 933-971) — same replacement as the first.

**`"resolves a failed teammate's real name in the failures dialog, not just the raw id"`** (old
lines 973-1019) — same replacement as the first.

Every other line in all six tests (the `_FakeApiClient` setup, the `await tester.pump(...)`
timing, and every `expect(...)` on `api.batchStartRequests`/dialog text/toast text) stays exactly
as it was — only the two lines that locate-and-tap the old dedicated button change to
locate-and-tap the menu trigger then the menu item.

- [ ] **Step 3: Run the full test file**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: PASS — every group green, including the rewritten `'lead branching'` group and Task 3's
new `'check-in body'` group (now 8 tests: the original 7 plus the offline-fallback one added in
this task's Step 1).

- [ ] **Step 4: Commit**

```bash
git add test/features/timbra/cantiere_timbra_screen_test.dart
git commit -m "test(cantiere): adapt lead-branching tests to the collapsed Per: Me menu"
```

---

### Task 6: Final verification pass

**Files:** none modified — verification only.

- [ ] **Step 1: Run `flutter analyze` on the touched files**

Run: `flutter analyze lib/features/timbra/cantiere_timbra_screen.dart test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: "No issues found!" Fix anything flagged (an unused import is the most likely finding —
see Task 4's note about `KeyVal`).

- [ ] **Step 2: Run the full test file one more time**

Run: `flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: 100% pass.

- [ ] **Step 3: Run the broader test suite for regressions in anything that imports this file**

Run: `grep -rl "cantiere_timbra_screen.dart" test lib --include="*.dart"` to confirm nothing
outside this screen and its own test file imports it directly (expected: nothing — this screen is
reached only via routing, not imported by other feature code). If anything unexpected turns up,
run its test file too.

Run: `flutter test test/features/timbra/ test/features/cantiere/`
Expected: 100% pass — confirms no regression in the sibling `CantiereDetailScreen`/related tests
that share providers with this file (`cantieriProvider`, `cantiereByIdProvider`, etc.).

- [ ] **Step 4: Manual spec cross-check**

Re-read `docs/superpowers/specs/2026-09-05-cantiere-timbra-redesign-design.md` section by section
against the final diff:
- "OGGI"/total header block present in both bodies — confirmed by Tasks 3/4's tests.
- Single "Inizia timbratura" button always performs solo start — confirmed by Task 3's tests.
- "Per: Me ▾" menu lead-only, two items firing unchanged handlers — confirmed by Tasks 3/5's
  tests.
- Midnight-clamping — confirmed by Task 2's `clampedElapsedSinceMidnight` tests.
- No backend/queue/reconciliation/batch-start-API changes — confirmed by inspection: no task in
  this plan touched `CantiereSessionRepository`, `CantiereTimbraSyncService`,
  `CantiereWorkLogReconciler`, or any `*ApiClient` class.
- "Squadra · N persone" indicator — confirmed absent (deferred, per the spec's Non-goals).

- [ ] **Step 5: Commit (if any fixes were needed in this task)**

```bash
git add -A
git commit -m "chore(cantiere): final verification pass for timbra redesign"
```

If no fixes were needed, skip this step — nothing to commit.
