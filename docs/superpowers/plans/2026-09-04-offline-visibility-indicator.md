# Offline/Sync Visibility Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persistent, shell-level indicator showing the technician whether they're offline and
how many actions are queued waiting to sync — reading the existing, already-working offline
infrastructure, adding zero new sync/queue mechanics.

**Architecture:** One new small Riverpod provider aggregates "how many rows are queued, and are any
failed" across the three Drift tables the existing queues already use (`DraftReports`,
`PendingTickets`, `PendingTicketAttachments`), combined with the existing `connectivityProvider`.
One new widget renders the result as a slim top banner in `HomeShell`, via `Stack` — purely
additive, does not touch `Rack`'s existing bottom-inset layout math for the nav bar.

**Tech Stack:** Flutter, Riverpod (`StreamProvider` over Drift watch queries), the existing
`connectivity_provider.dart`.

**Spec:** `docs/superpowers/specs/2026-09-04-offline-realtime-engine-design.md` (§1, Visibility layer)

## Global Constraints

- No chrome when online and fully synced — this is the app's own existing convention (see the
  punch-clock/timbra screens' "absence of noise is correct" pattern) and the spec's explicit
  requirement.
- Uses the existing `connectivityProvider` (`lib/data/sync/connectivity_provider.dart:68`,
  `AsyncNotifierProvider<ConnectivityNotifier, bool>`) as the online/offline signal — no new
  connectivity detection.
- Counts rows already tracked by existing tables/state columns:
  `DraftReports.submissionState` (`DraftSubmissionState`: `draft`/`readyToSubmit`/
  `uploadingMedia`/`submitting`/`submitted`/`failed` — only `readyToSubmit`/`uploadingMedia`/
  `submitting` count as "pending"; `draft` is a normal unsent draft, not a queued item),
  `PendingTickets.state` and `PendingTicketAttachments.state` (`PendingTicketState`:
  `pendingSync`/`submitting`/`submitted`/`failed` — `pendingSync`/`submitting` count as "pending").
  `failed` rows in any table count toward a separate "N failed" signal, never silently folded into
  the pending count.
- No new queue/sync mechanism — this plan is a read-only aggregation + UI layer over infrastructure
  that already works.

---

### Task 1: `pendingSyncCountProvider` — aggregate pending/failed counts

**Files:**
- Create: `lib/data/sync/pending_sync_count_provider.dart`
- Test: `test/data/sync/pending_sync_count_provider_test.dart`

**Interfaces:**
- Produces: `pendingSyncCountProvider` — a `StreamProvider<PendingSyncCount>` where
  `PendingSyncCount` is `({int pending, int failed})` (a Dart record). Task 2 watches this.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/sync/pending_sync_count_provider_test.dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart' show appDatabaseProvider;

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  test('counts only queued rows as pending, failed rows separately, draft rows not at all', () async {
    await db.into(db.draftReports).insert(
      DraftReportsCompanion.insert(
        id: 'r1', tenantId: 't1', createdAt: DateTime.now(),
        submissionState: const Value('readyToSubmit'),
      ),
    );
    await db.into(db.draftReports).insert(
      DraftReportsCompanion.insert(
        id: 'r2', tenantId: 't1', createdAt: DateTime.now(),
        submissionState: const Value('draft'), // must NOT count
      ),
    );
    await db.into(db.draftReports).insert(
      DraftReportsCompanion.insert(
        id: 'r3', tenantId: 't1', createdAt: DateTime.now(),
        submissionState: const Value('failed'),
      ),
    );
    await db.into(db.pendingTickets).insert(
      PendingTicketsCompanion.insert(
        id: 'p1', createdAt: DateTime.now(), title: 'x', customerId: 'c1', locationId: 'l1',
        statusId: 1, typeId: 1, state: const Value('pendingSync'),
      ),
    );

    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    final result = await container.read(pendingSyncCountProvider.future);

    expect(result.pending, 2); // r1 (readyToSubmit) + p1 (pendingSync)
    expect(result.failed, 1); // r3
  });
}
```

(Check `DraftReportsCompanion.insert`'s actual required fields — e.g. whether `tenantId` is
required, whether there's a `title` or similar — against `app_database.dart`'s real
`DraftReportTable`/`PendingTickets` definitions before running; the fields above are the ones
grounded during planning, but confirm rather than assume every required field was captured.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sync/pending_sync_count_provider_test.dart`
Expected: FAIL — the file doesn't exist yet.

- [ ] **Step 3: Write the provider**

```dart
// dart format width=100
// lib/data/sync/pending_sync_count_provider.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../local/app_database.dart';
import 'submission_queue.dart' show appDatabaseProvider;

typedef PendingSyncCount = ({int pending, int failed});

const _reportPending = ['readyToSubmit', 'uploadingMedia', 'submitting'];
const _queuePending = ['pendingSync', 'submitting'];

/// Aggregates how many rows across the existing offline queues (draft reports, pending tickets,
/// pending ticket attachments) are queued waiting to sync, and how many are in a failed state —
/// pure read-side aggregation over tables the existing queues already own; this provider owns no
/// sync logic of its own.
final pendingSyncCountProvider = StreamProvider<PendingSyncCount>((ref) {
  final db = ref.watch(appDatabaseProvider);

  final reportsStream = (db.select(db.draftReports)
        ..where((r) => r.submissionState.isNotValue('submitted')))
      .watch();
  final ticketsStream = (db.select(db.pendingTickets)
        ..where((t) => t.state.isNotValue('submitted')))
      .watch();
  final attachmentsStream = (db.select(db.pendingTicketAttachments)
        ..where((a) => a.state.isNotValue('submitted')))
      .watch();

  return Rx.combineLatest3(reportsStream, ticketsStream, attachmentsStream, (
    reports,
    tickets,
    attachments,
  ) {
    var pending = 0;
    var failed = 0;

    for (final r in reports) {
      if (r.submissionState == 'failed') {
        failed++;
      } else if (_reportPending.contains(r.submissionState)) {
        pending++;
      }
    }
    for (final t in tickets) {
      if (t.state == 'failed') {
        failed++;
      } else if (_queuePending.contains(t.state)) {
        pending++;
      }
    }
    for (final a in attachments) {
      if (a.state == 'failed') {
        failed++;
      } else if (_queuePending.contains(a.state)) {
        pending++;
      }
    }

    return (pending: pending, failed: failed);
  });
});
```

(Confirm `rxdart`'s `Rx.combineLatest3` is already a dependency of this project — check
`pubspec.yaml`; if not present, add it, or use Riverpod's own `StreamProvider` composition instead
via nested `ref.watch` of three separate `StreamProvider`s combined in a fourth — pick whichever
this codebase already has a precedent for. Also confirm `appDatabaseProvider`'s actual import path
— it was grounded as living in `lib/data/sync/submission_queue.dart` earlier this session, but
verify directly before trusting this import.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sync/pending_sync_count_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/pending_sync_count_provider.dart test/data/sync/pending_sync_count_provider_test.dart
git commit -m "feat(sync): add pendingSyncCountProvider aggregating queue state"
```

---

### Task 2: `OfflineSyncBanner` widget

**Files:**
- Create: `lib/core/widgets/offline_sync_banner.dart`
- Test: `test/core/widgets/offline_sync_banner_test.dart`

**Interfaces:**
- Consumes: `connectivityProvider` (existing), `pendingSyncCountProvider` (Task 1).
- Produces: `OfflineSyncBanner` — a `ConsumerWidget` with no constructor parameters, self-contained
  (reads its own providers). Task 3 places it in `HomeShell`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/widgets/offline_sync_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/offline_sync_banner.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: OfflineSyncBanner())),
);

void main() {
  testWidgets('renders nothing when online and fully synced', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
      ]),
    );
    await tester.pump();

    expect(find.byType(OfflineSyncBanner), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.textContaining('in coda'), findsNothing);
  });

  testWidgets('shows an offline indicator when disconnected', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('shows a pending count when online but items are queued', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 3, failed: 0))),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('3'), findsOneWidget);
  });
}

class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}
```

(Confirm `ConnectivityNotifier`'s actual `build()` signature and whether it's overridable this way
— `AsyncNotifierProvider.overrideWith` expects a factory returning a fresh notifier instance, check
against an existing test elsewhere in this codebase that already overrides `connectivityProvider`,
if one exists, and mirror its exact pattern instead of guessing.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/widgets/offline_sync_banner_test.dart`
Expected: FAIL — the widget doesn't exist yet.

- [ ] **Step 3: Write the widget**

```dart
// dart format width=100
// lib/core/widgets/offline_sync_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/pending_sync_count_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A slim, persistent top banner — offline, or N-pending/N-failed. Renders nothing when online
/// and fully synced, matching this app's existing "silence is correct" convention. Purely
/// additive: place via Stack over existing content, never restructure the content it sits above.
class OfflineSyncBanner extends ConsumerWidget {
  const OfflineSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;
    final counts = ref.watch(pendingSyncCountProvider).valueOrNull ?? (pending: 0, failed: 0);

    final String? label;
    if (!isOnline) {
      label = 'Offline';
    } else if (counts.failed > 0) {
      label = '${counts.failed} da riprovare';
    } else if (counts.pending > 0) {
      label = '${counts.pending} in coda';
    } else {
      label = null;
    }

    if (label == null) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        color: counts.failed > 0 ? context.colors.red : context.colors.inkMuted,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
```

(Verify `context.colors.red`/`.inkMuted` are the correct token names against `app_palette.dart`'s
current field list before pasting verbatim.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/widgets/offline_sync_banner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/offline_sync_banner.dart test/core/widgets/offline_sync_banner_test.dart
git commit -m "feat(widgets): add OfflineSyncBanner"
```

---

### Task 3: Wire `OfflineSyncBanner` into `HomeShell`

**Files:**
- Modify: `lib/presentation/screens/home/home_shell.dart`
- Test: extend or create `test/presentation/screens/home/home_shell_test.dart`

**Interfaces:**
- Consumes: `OfflineSyncBanner` (Task 2).
- Produces: no change to `HomeShell`'s own public API — purely internal `build()` change.

- [ ] **Step 1: Write the failing test**

Add a case asserting `OfflineSyncBanner` is present in `HomeShell`'s widget tree (using whichever
provider-override harness this file's existing tests already use, if any exist — check for
`home_shell_test.dart` first; if none exists, this is a new minimal smoke test, not a full
`HomeShell` behavior suite).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/screens/home/home_shell_test.dart`
Expected: FAIL — `OfflineSyncBanner` isn't in the tree yet.

- [ ] **Step 3: Add the banner via `Stack`**

In `home_shell.dart`'s `build()` method, wrap both the narrow and wide-layout `content` in a
`Stack` with the banner pinned at the top — change:

```dart
    if (MediaQuery.sizeOf(context).width >= AppBottomNav.wideBreakpoint) {
      return Scaffold(body: Row(children: [nav, Expanded(child: content)]));
    }

    return Scaffold(
      body: content,
      extendBody: true,
      bottomNavigationBar: nav,
    );
```

to:

```dart
    if (MediaQuery.sizeOf(context).width >= AppBottomNav.wideBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            nav,
            Expanded(
              child: Stack(
                children: [content, const Align(alignment: Alignment.topCenter, child: OfflineSyncBanner())],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [content, const Align(alignment: Alignment.topCenter, child: OfflineSyncBanner())],
      ),
      extendBody: true,
      bottomNavigationBar: nav,
    );
```

Add the import: `import '../../../core/widgets/offline_sync_banner.dart';` (adjust the relative
path to match this file's actual location/existing import style).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/screens/home/home_shell_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full test suite once**

Run: `flutter test`
Expected: PASS, no regressions — this change is purely additive to `HomeShell`'s tree, should not
affect any existing navigation/layout test unless one asserts on the exact widget tree shape (in
which case, update that assertion to account for the new `Stack`, don't skip it).

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/home/home_shell.dart test/presentation/screens/home/home_shell_test.dart
git commit -m "feat(shell): wire OfflineSyncBanner into HomeShell"
```

---

## Self-review notes (per this skill's own required step)

**Spec coverage:** Task 1 covers the spec's "no new queue-counting mechanism, just a UI layer
reading what already exists" data requirement (a thin aggregator, not new queue logic). Task 2
covers the three-state indicator (silent / offline / N-pending) plus a fourth state the spec didn't
explicitly separate but the grounding surfaced as necessary — failed rows, shown distinctly rather
than folded into "pending," matching this app's existing retry-affordance conventions elsewhere.
Task 3 covers "lives in the shell... visible regardless of which screen."

**Placeholder scan:** Every code block is real, runnable code. Two explicit, scoped verification
pointers (Task 1's `rxdart`/`appDatabaseProvider` import check, Task 2's `ConnectivityNotifier`
override pattern) are flagged as "confirm before trusting," not left as invented certainty — this
plan's grounding did not have live access to run `flutter test` against every assumption, so these
are honest, narrow gaps, not vague placeholders.

**Type consistency:** `PendingSyncCount` (Task 1's record type) is consumed identically by Task 2's
widget (`.pending`/`.failed` fields). `pendingSyncCountProvider`/`connectivityProvider` names match
between the two tasks' code exactly.
