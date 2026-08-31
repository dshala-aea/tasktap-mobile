# Cantieri Nav Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Timbra bottom-nav tab with a Cantieri tab giving operators direct access to
their assigned worksites, relocate the ticket-detail "Timbra cantiere" action to a new Cantiere
detail screen, and give tickets a real (synced) link to their cantiere.

**Architecture:** Mobile-only (investigation during planning confirmed the backend already sends
`Ticket.CantiereId` on every sync — the full `Ticket` entity flows through
`MobileUserSyncResult.Tickets` unfiltered — so this is a client-side "parse and store a field
that's already on the wire" change, not a new endpoint). Two new technician-facing screens read
existing/extended local Drift-cached data (`cantieriProvider`, the new `Tickets.cantiereId`
column) — no new network calls beyond what already exists. The router's shell branch and the
bottom nav's tab list are swapped in lockstep; `CantiereTimbraScreen` gains a direct-entry mode
that bypasses its existing cantiere picker.

Task order matters here more than usual: the route-string constants (Task 3) are split out from
the actual route/screen wiring (Task 8) specifically so the two new screens (Tasks 6, 7), which
reference those constants, can be written and tested before the router wiring that imports them
exists. Do not reorder tasks without re-checking this chain.

**Tech Stack:** Flutter, Riverpod, go_router, Drift (SQLite), Dio.

**Spec:** `docs/superpowers/specs/2026-08-31-cantieri-nav-restructure-design.md`

## Global Constraints

- Mobile stays technician-persona; do not reuse or extend the admin CRUD screens
  (`lib/features/admin/cantieri/*`) for the new technician-facing screens (spec Decisions).
- No new backend endpoint or DTO change: `Ticket.CantiereId` already reaches
  `MobileUserSyncResult.Tickets` today (verified during planning — see Task 1's own note).
- A new column on a delta-synced table needs a `syncCursorGeneration` bump alongside it, or every
  device already in the field keeps the column null forever (see `app_database.dart`'s own doc
  comment on `syncCursorGeneration`, and the `tickets.priority`/`tickets.numero` precedents it
  documents). This is NOT the `DraftReports.cantiereId` precedent (that column is client-authored
  and explicitly needs no bump) — do not copy that one.
- Follow existing Vetro widget vocabulary exactly: `VetroCard`, `VetroButton`, `ListRow`,
  `SectionTitle`, `ScreenHeader`, `UnavailableState`, `AppChip`/`AppBadge` (both in
  `core/widgets/badge.dart`). Do not invent new primitives for what these already cover.

---

### Task 1: `Tickets.cantiereId` column, migration, and sync-cursor bump

**Files:**
- Modify: `lib/data/local/app_database.dart`
- Test: `test/data/local/app_database_test.dart` (create if it doesn't exist — check first)

**Interfaces:**
- Produces: `Tickets.cantiereId` (`TextColumn`, nullable) on the local Drift table; row class
  `Ticket.cantiereId` (`String?`). `AppDatabase.schemaVersion` becomes `23`.
  `AppDatabase.syncCursorGeneration` becomes `'v6'`.

- [ ] **Step 1: Check for an existing Drift table round-trip test to extend**

Run: `find test -iname "*app_database*"`

If a suitable file exists, add the new test there. If not, create
`test/data/local/app_database_test.dart` with the boilerplate below plus the test in Step 3.

- [ ] **Step 2: Add the column to the `Tickets` table**

In `lib/data/local/app_database.dart`, inside `class Tickets extends Table` (around line 96,
right after `commessaId`), add:

```dart
  /// The cantiere (worksite) this ticket is linked to, when it has one — a ticket may or may not
  /// be linked to a cantiere. Already on the wire the whole time (mobile sync returns the full
  /// `Ticket` entity, which has carried `CantiereId` since it was added server-side), just never
  /// parsed or stored — same situation as `numero` (schema 12) and `priority`/`dueDate`
  /// (schema 20). See `syncCursorGeneration`'s own doc comment for why this needs a bump too.
  TextColumn get cantiereId => text().nullable()();
```

- [ ] **Step 3: Write the failing test**

```dart
// test/data/local/app_database_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

void main() {
  group('Tickets.cantiereId', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('round-trips through insert and select', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Test ticket',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              cantiereId: const Value('cantiere-1'),
            ),
          );

      final row = await (db.select(
        db.tickets,
      )..where((t) => t.id.equals('t1'))).getSingle();

      expect(row.cantiereId, 'cantiere-1');
    });

    test('defaults to null when not set', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Test ticket 2',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final row = await (db.select(
        db.tickets,
      )..where((t) => t.id.equals('t2'))).getSingle();

      expect(row.cantiereId, isNull);
    });
  });
}
```

Add `import 'package:drift/drift.dart' show Value;` at the top alongside the other imports.

- [ ] **Step 4: Run the build_runner and run the test to verify it fails**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/data/local/app_database_test.dart`

Expected: FAIL — `cantiereId` isn't a named parameter on `TicketsCompanion.insert` yet (compile
error) until Step 2's column exists AND build_runner has regenerated `app_database.g.dart`. If
Step 2 is already done, re-run build_runner and this becomes a genuine red test only if you
temporarily skip Step 2 — in practice here, do Step 2 first, then this step both regenerates code
and runs a passing test. Treat "compiles and passes" as confirmation the column exists and is
wired; there is no meaningful red state to observe once the column is declared, since Drift
generates the companion from the table definition directly.

- [ ] **Step 5: Bump `schemaVersion` and add the migration step**

In `lib/data/local/app_database.dart`, change:

```dart
  int get schemaVersion => 22;
```

to:

```dart
  int get schemaVersion => 23;
```

Then in the `onUpgrade` block, after the `if (from < 22)` block (around line 871), add:

```dart
        if (from < 23) {
          // Ticket<->Cantiere link — see Tickets.cantiereId's own doc comment. Same reasoning as
          // schema 20 (tickets.priority/dueDate): already on the wire, needs syncCursorGeneration
          // bumped below or an already-synced device never backfills it.
          await m.addColumn(tickets, tickets.cantiereId);
        }
```

- [ ] **Step 6: Bump `syncCursorGeneration`**

In `lib/data/local/app_database.dart`, update the doc comment and constant:

```dart
  /// v5 — 2026-08-27, schema 22 added `materiale_barcodes` (new table, not a column, but the
  ///      same delta blind spot: existing MaterialeBarcode rows on the backend would never
  ///      backfill for a device whose cursor is already past their (unrelated) last change).
  /// v6 — 2026-08-31, schema 23 added `tickets.cantiereId`. Same reasoning as v4
  ///      (tickets.priority/dueDate): already on the wire, a delta sync would never refill it for
  ///      tickets that haven't otherwise changed.
  static const String syncCursorGeneration = 'v6';
```

- [ ] **Step 7: Run the full test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/data/local/app_database_test.dart`

Expected: PASS (2 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/data/local/app_database.dart test/data/local/app_database_test.dart
git commit -m "feat(mobile): add Tickets.cantiereId column, bump sync cursor to v6"
```

---

### Task 2: Parse and sync `cantiereId` onto local tickets

**Files:**
- Modify: `lib/data/sync/sync_dto.dart`
- Modify: `lib/data/sync/sync_service.dart`
- Test: `test/data/sync/sync_dto_test.dart` (check if it exists first; if not, add to whichever
  test file already covers `TicketDto`)

**Interfaces:**
- Consumes: `Tickets.cantiereId` (Task 1).
- Produces: `TicketDto.cantiereId` (`String?`).

- [ ] **Step 1: Find the existing `TicketDto` test coverage**

Run: `grep -rln "TicketDto" test/`

Add the new test to whichever file already round-trips `TicketDto.fromJson` (likely
`test/data/sync/sync_dto_test.dart` or similar — use its existing fixture-building pattern).

- [ ] **Step 2: Write the failing test**

Add a test alongside the existing `TicketDto.fromJson` coverage:

```dart
test('TicketDto.fromJson parses cantiereId', () {
  final json = {
    'id': 't1',
    'tenantId': 'tenant1',
    'createdAt': '2026-08-31T00:00:00Z',
    'title': 'Test',
    'customerId': 'c1',
    'locationId': 'l1',
    'statusId': 1,
    'typeId': 1,
    'cantiereId': 'cantiere-1',
  };

  final dto = TicketDto.fromJson(json);

  expect(dto.cantiereId, 'cantiere-1');
});

test('TicketDto.fromJson tolerates a missing cantiereId', () {
  final json = {
    'id': 't1',
    'tenantId': 'tenant1',
    'createdAt': '2026-08-31T00:00:00Z',
    'title': 'Test',
    'customerId': 'c1',
    'locationId': 'l1',
    'statusId': 1,
    'typeId': 1,
  };

  final dto = TicketDto.fromJson(json);

  expect(dto.cantiereId, isNull);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `fvm flutter test test/data/sync/sync_dto_test.dart`
Expected: FAIL — `TicketDto` has no `cantiereId` getter yet.

- [ ] **Step 4: Add `cantiereId` to `TicketDto`**

In `lib/data/sync/sync_dto.dart`, in `class TicketDto` (around line 191), add the field next to
`commessaId`:

```dart
  final String? commessaId;

  /// The cantiere this ticket is linked to, when it has one. See `Tickets.cantiereId`'s own doc
  /// comment in app_database.dart for why this needed a schema+cursor bump to actually reach the
  /// device rather than just being added to this DTO.
  final String? cantiereId;
```

In the constructor, add `this.cantiereId,` next to `this.commessaId,`. In `TicketDto.fromJson`,
add:

```dart
    commessaId: j['commessaId'] as String?,
    cantiereId: j['cantiereId'] as String?,
```

(placed right after the existing `commessaId:` line).

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm flutter test test/data/sync/sync_dto_test.dart`
Expected: PASS.

- [ ] **Step 6: Wire it into `SyncService._upsertTickets`**

In `lib/data/sync/sync_service.dart`, in `_upsertTickets` (around line 215), add
`cantiereId: Value(t.cantiereId),` to the `TicketsCompanion.insert(...)` call, right after
`commessaId: Value(t.commessaId),`.

- [ ] **Step 7: Run the full mobile test suite for these two files**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/data/sync/`

Expected: PASS, no regressions.

- [ ] **Step 8: Commit**

```bash
git add lib/data/sync/sync_dto.dart lib/data/sync/sync_service.dart test/data/sync/
git commit -m "feat(mobile): sync Ticket.cantiereId from the server"
```

---

### Task 3: Route-string constants for Cantieri

**Files:**
- Modify: `lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppRoutes.cantieri`, `AppRoutes.cantieriDetail`, `AppRoutes.cantieriDetailPath(id)`;
  `AppRoutes.cantiereTimbraPath` gains a `cantiereId` param. Consumed by Tasks 6, 7, 10.

Deliberately split from the actual router/screen wiring (Task 8): these are plain static string
builders with no dependency on the new screens, so the screens (Tasks 6, 7) can reference and test
against them before the screens exist to be routed to. Doing this as one task at the end (as an
earlier draft of this plan had it) breaks task ordering — Task 6 would need constants Task 8
hadn't defined yet.

There is no isolated unit test for these constants in this codebase (they're plain string
builders, matching how the existing `ticketDetailPath`/`clientiDetail`/`rapportiniEditor` builders
next to them are also untested directly — covered transitively wherever they're used). Verification
for this task is `dart analyze` passing.

- [ ] **Step 1: Add the new route constants**

In `lib/core/router/app_router.dart`, in `abstract final class AppRoutes` (around line 71), keep
the existing `timbra` constant (its meaning changes in Task 8, not here) and add the new ones
right after it:

```dart
  static const String timbra = '/timbra';

  /// Technician-facing cantieri (worksites) list — the Cantieri tab.
  static const String cantieri = '/cantieri';
  static const String cantieriDetail = '/cantieri/:id';

  /// Build the detail path for a given cantiere id.
  static String cantieriDetailPath(String id) => '/cantieri/$id';
```

- [ ] **Step 2: Extend `cantiereTimbraPath` with a `cantiereId` param**

In the same file, change (around line 91):

```dart
  /// Build the cantiere timbra path with optional query params.
  static String cantiereTimbraPath({String? ticketId, String? customerId}) {
    final params = <String>[];
    if (ticketId != null) params.add('ticketId=$ticketId');
    if (customerId != null) params.add('customerId=$customerId');
    return params.isEmpty
        ? cantiereTimbra
        : '$cantiereTimbra?${params.join('&')}';
  }
```

to:

```dart
  /// Build the cantiere timbra path with optional query params.
  static String cantiereTimbraPath({
    String? ticketId,
    String? customerId,
    String? cantiereId,
  }) {
    final params = <String>[];
    if (ticketId != null) params.add('ticketId=$ticketId');
    if (customerId != null) params.add('customerId=$customerId');
    if (cantiereId != null) params.add('cantiereId=$cantiereId');
    return params.isEmpty
        ? cantiereTimbra
        : '$cantiereTimbra?${params.join('&')}';
  }
```

- [ ] **Step 3: Run analyze to verify it compiles**

Run: `fvm dart analyze lib/core/router/app_router.dart`
Expected: No issues (these are additive constants; nothing else in the codebase references them
yet, so nothing can be broken by adding them).

- [ ] **Step 4: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat(mobile): add Cantieri route constants and cantiereId to cantiereTimbraPath"
```

---

### Task 4: `cantiereByIdProvider` and `ticketsForCantiereProvider`

**Files:**
- Create: `lib/features/cantiere/cantiere_providers.dart`
- Test: `test/features/cantiere/cantiere_providers_test.dart`

**Interfaces:**
- Consumes: `AppDatabase.cantieri`/`AppDatabase.tickets` (existing Drift tables, plus Task 1's
  `cantiereId` column), `appDatabaseProvider` (existing, from `app_database.dart`).
- Produces: `cantiereByIdProvider` (`FutureProvider.family<CantieriData?, String>`),
  `ticketsForCantiereProvider` (`StreamProvider.family<List<Ticket>, String>`). Consumed by
  Tasks 7 and 10.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/cantiere/cantiere_providers_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('cantiereByIdProvider', () {
    test('returns the matching cantiere', () async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Test',
            ),
          );

      final result = await container.read(cantiereByIdProvider('c1').future);

      expect(result?.name, 'Cantiere Test');
    });

    test('returns null when no cantiere matches', () async {
      final result = await container.read(cantiereByIdProvider('missing').future);

      expect(result, isNull);
    });
  });

  group('ticketsForCantiereProvider', () {
    test('returns only tickets linked to that cantiere', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Linked',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              cantiereId: const Value('cantiere-1'),
            ),
          );
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Unlinked',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final result = await container.read(
        ticketsForCantiereProvider('cantiere-1').future,
      );

      expect(result.map((t) => t.id), ['t1']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/cantiere/cantiere_providers_test.dart`
Expected: FAIL — the file `lib/features/cantiere/cantiere_providers.dart` doesn't exist yet.

- [ ] **Step 3: Create the providers**

```dart
// dart format width=100
// lib/features/cantiere/cantiere_providers.dart
//
// Providers backing the technician-facing Cantieri tab (CantieriListScreen,
// CantiereDetailScreen). Both read the local Drift mirror only — no independent network call,
// same offline-first shape as cantieriProvider (features/timbra/cantiere_timbra_screen.dart),
// which this file's cantiereByIdProvider complements with a single-row lookup by id.

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';

/// A single cantiere by id, or null if none is synced locally with that id. Not filtered by
/// status (unlike `cantieriProvider`) — a cantiere reached via a ticket's link may be
/// Completed/Cancelled, and that's a legitimate state to display, not an error.
final cantiereByIdProvider = FutureProvider.family<CantieriData?, String>((ref, id) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await (db.select(db.cantieri)..where((c) => c.id.equals(id))).get();
  return rows.isNotEmpty ? rows.first : null;
});

/// Tickets linked to the given cantiere (`Ticket.cantiereId == id`), for the "Tickets in questo
/// cantiere" section on CantiereDetailScreen. Local-only, like every other list in this app —
/// the technician's own ticket sync scope already determines what's available here.
final ticketsForCantiereProvider = StreamProvider.family<List<Ticket>, String>((ref, cantiereId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.cantiereId.equals(cantiereId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/features/cantiere/cantiere_providers_test.dart`

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/cantiere/cantiere_providers.dart test/features/cantiere/cantiere_providers_test.dart
git commit -m "feat(mobile): add cantiereByIdProvider and ticketsForCantiereProvider"
```

---

### Task 5: `CantiereTimbraScreen` direct-entry mode (skip the picker)

**Files:**
- Modify: `lib/features/timbra/cantiere_timbra_screen.dart`
- Test: `test/features/timbra/cantiere_timbra_screen_test.dart` (check if it exists; add to it, or
  create following the pattern of a sibling widget test in `test/features/timbra/` if not)

**Interfaces:**
- Consumes: `cantiereByIdProvider` (Task 4).
- Produces: `CantiereTimbraScreen({ticketId, customerId, cantiereId})` — new optional
  `cantiereId` param. Consumed by Tasks 7 and 8.

- [ ] **Step 1: Write the failing test**

Add to the test file (create with this plus a `MaterialApp`/`ProviderScope` harness matching
whatever pattern this app's other screen tests already use — check
`test/features/timbra/timbra_screen_test.dart` if one exists for the harness shape):

```dart
testWidgets('given a cantiereId, the picker is not shown', (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: 'c1',
          tenantId: 'tenant1',
          createdAt: DateTime.utc(2026, 8, 31),
          name: 'Cantiere Diretto',
        ),
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CantiereTimbraScreen(cantiereId: 'c1')),
    ),
  );
  await tester.pumpAndSettle();

  // The full picker section header only renders in picker mode.
  expect(find.text('Seleziona cantiere'), findsNothing);
  expect(find.text('Cantiere Diretto'), findsOneWidget);

  await db.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/timbra/cantiere_timbra_screen_test.dart`
Expected: FAIL — `CantiereTimbraScreen` has no `cantiereId` constructor parameter yet.

- [ ] **Step 3: Add `cantiereId` to `CantiereTimbraScreen` and wire it through**

In `lib/features/timbra/cantiere_timbra_screen.dart`, change the constructor (around line 201):

```dart
class CantiereTimbraScreen extends ConsumerStatefulWidget {
  const CantiereTimbraScreen({super.key, this.ticketId, this.customerId, this.cantiereId});

  /// The ticket that launched this screen (optional context link).
  final String? ticketId;

  /// The customerId from the ticket (used to pre-filter the cantiere list).
  final String? customerId;

  /// When set, this screen skips its cantiere picker entirely and acts on this cantiere directly
  /// — the entry point from CantiereDetailScreen (and, transitively, the Cantieri tab). `ticketId`
  /// stays honored alongside it when both are present (arrived via the ticket-detail chip), so the
  /// resulting session is still tagged with that ticket.
  final String? cantiereId;
```

Add the import: `import '../cantiere/cantiere_providers.dart';` (for `cantiereByIdProvider`).

In `_CantiereTimbraScreenState.build()` (around line 244), add the fixed-cantiere lookup and pass
it through:

```dart
  @override
  Widget build(BuildContext context) {
    final cantieriAsync = ref.watch(cantieriProvider);
    final localEventsAsync = ref.watch(todayCantiereEventsProvider);
    final active = ref.watch(cantiereActiveSessionProvider);
    final serverLog = ref.watch(activeCantiereLogProvider).valueOrNull;
    final hasPendingSync = ref.watch(cantiereHasPendingSyncProvider);

    final fixedCantiereAsync = widget.cantiereId != null
        ? ref.watch(cantiereByIdProvider(widget.cantiereId!))
        : null;
    final effectiveSelected = widget.cantiereId != null
        ? fixedCantiereAsync?.valueOrNull
        : _selectedCantiere;
```

Then in the `_CheckInBody(...)` construction further down, change `selectedCantiere:
_selectedCantiere,` to `selectedCantiere: effectiveSelected,` and add
`showPicker: widget.cantiereId == null,`.

- [ ] **Step 4: Add the `showPicker` param to `_CheckInBody` and branch its body**

In `lib/features/timbra/cantiere_timbra_screen.dart`, `class _CheckInBody` (around line 533), add
`required this.showPicker,` to the constructor and `final bool showPicker;` as a field.

In `_CheckInBody.build()` (around line 604), wrap the existing "Section header + cantieriAsync.when(...)"
block (the `Text('Seleziona cantiere', ...)` through the closing of the `cantieriAsync.when(...)`
call) in an `if (showPicker) ... else`:

```dart
          if (showPicker) ...[
            // Section header
            Text(
              'Seleziona cantiere',
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
              // ... existing loading/error/data branches, unchanged ...
            ),
          ] else
            VetroCard(
              child: selectedCantiere == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.base),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : Row(
                      children: [
                        Icon(LucideIcons.hardHat, size: 18, color: context.colors.ink),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedCantiere.name,
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
            ),
```

(Keep the existing `cantieriAsync.when(...)` branches exactly as they are inside the `if
(showPicker)` block — only the wrapping is new.)

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/features/timbra/cantiere_timbra_screen_test.dart`

Expected: PASS.

- [ ] **Step 6: Run the existing cantiere_timbra_screen tests to confirm no regression**

Run: `fvm flutter test test/features/timbra/`
Expected: PASS, no regressions (the picker path — `cantiereId: null` — must render exactly as
before).

- [ ] **Step 7: Commit**

```bash
git add lib/features/timbra/cantiere_timbra_screen.dart test/features/timbra/cantiere_timbra_screen_test.dart
git commit -m "feat(mobile): CantiereTimbraScreen accepts a direct cantiereId, skipping the picker"
```

---

### Task 6: `CantieriListScreen`

**Files:**
- Create: `lib/features/cantiere/cantieri_list_screen.dart`
- Test: `test/features/cantiere/cantieri_list_screen_test.dart`

**Interfaces:**
- Consumes: `cantieriProvider` (existing, exported from
  `lib/features/timbra/cantiere_timbra_screen.dart`), `AppRoutes.cantieriDetailPath` (Task 3).
- Produces: `CantieriListScreen` widget. Consumed by Task 8 (router).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/cantiere/cantieri_list_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/cantiere/cantieri_list_screen.dart';

void main() {
  testWidgets('shows an empty state when no cantieri are synced', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantieriListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nessun cantiere disponibile'), findsOneWidget);

    await db.close();
  });

  testWidgets('lists synced cantieri alphabetically', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c2',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Zeta Cantiere',
          ),
        );
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Alfa Cantiere',
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantieriListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final alfaFinder = find.text('Alfa Cantiere');
    final zetaFinder = find.text('Zeta Cantiere');
    expect(alfaFinder, findsOneWidget);
    expect(zetaFinder, findsOneWidget);
    expect(
      tester.getTopLeft(alfaFinder).dy,
      lessThan(tester.getTopLeft(zetaFinder).dy),
    );

    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/cantiere/cantieri_list_screen_test.dart`
Expected: FAIL — `lib/features/cantiere/cantieri_list_screen.dart` doesn't exist yet.

- [ ] **Step 3: Create the screen**

```dart
// dart format width=100
// lib/features/cantiere/cantieri_list_screen.dart
//
// Technician-facing list of the operator's own cantieri (worksites) — the Cantieri tab.
// Deliberately not a reuse of admin_cantiere_list_screen.dart: that one is CRUD-oriented,
// office/admin-only. This one reads cantieriProvider exactly as CantiereTimbraScreen's picker
// already does — already scoped server-side to the technician's own CantiereAssignment rows
// (falling back to all active cantieri when they have none), so no new filtering logic here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../timbra/cantiere_timbra_screen.dart' show cantieriProvider;

class CantieriListScreen extends ConsumerWidget {
  const CantieriListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantieriAsync = ref.watch(cantieriProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.base,
                AppSpacing.pagePadding,
                AppSpacing.sm,
              ),
              child: ScreenHeader(title: 'Cantieri'),
            ),
            Expanded(
              child: cantieriAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const UnavailableState(
                  icon: LucideIcons.hardHat,
                  titolo: 'Impossibile caricare i cantieri',
                  motivo: 'Trascina in basso per aggiornare, oppure riprova tra poco.',
                ),
                data: (cantieri) {
                  if (cantieri.isEmpty) {
                    return const UnavailableState(
                      icon: LucideIcons.hardHat,
                      titolo: 'Nessun cantiere disponibile',
                      motivo:
                          'Non risultano cantieri sincronizzati su questo dispositivo. Trascina '
                          'in basso per aggiornare, oppure riprova tra poco.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    itemCount: cantieri.length,
                    itemBuilder: (context, i) {
                      final c = cantieri[i];
                      return ListRow(
                        leading: Icon(LucideIcons.hardHat, color: context.colors.inkMuted),
                        title: c.name,
                        subtitle: c.address,
                        showDivider: i != cantieri.length - 1,
                        onTap: () => context.push(AppRoutes.cantieriDetailPath(c.id)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Note: `ScreenHeader` here has no `showBack` — this is a shell-hosted tab root, matching how the
other four tab roots (Dashboard, Ticket list, Calendario, Altro hub) are not back-navigable
either.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/features/cantiere/cantieri_list_screen_test.dart`

Expected: PASS (2 tests). `AppRoutes.cantieriDetailPath` already exists from Task 3, so this
should compile and pass cleanly with no stub needed.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cantiere/cantieri_list_screen.dart test/features/cantiere/cantieri_list_screen_test.dart
git commit -m "feat(mobile): add CantieriListScreen"
```

---

### Task 7: `CantiereDetailScreen`

**Files:**
- Create: `lib/features/cantiere/cantiere_detail_screen.dart`
- Test: `test/features/cantiere/cantiere_detail_screen_test.dart`

**Interfaces:**
- Consumes: `cantiereByIdProvider`, `ticketsForCantiereProvider` (Task 4), `CantiereTimbraScreen`
  (Task 5), `AppRoutes.cantiereTimbraPath` (Task 3), `AppRoutes.ticketDetailPath` (existing).
- Produces: `CantiereDetailScreen({required cantiereId, this.ticketId})`. Consumed by Task 8
  (router) and Task 10 (ticket-detail chip).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/cantiere/cantiere_detail_screen_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_detail_screen.dart';

void main() {
  testWidgets('shows cantiere info and an empty tickets section', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
            address: const Value('Via Roma 1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Alpha'), findsOneWidget);
    expect(find.text('Via Roma 1'), findsOneWidget);
    expect(find.text('Timbra cantiere'), findsOneWidget);
    expect(find.text('Nessun ticket collegato'), findsOneWidget);

    await db.close();
  });

  testWidgets('lists linked tickets when present', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            title: 'Ticket collegato',
            customerId: 'cust1',
            locationId: 'l1',
            statusId: 1,
            typeId: 1,
            cantiereId: const Value('c1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ticket collegato'), findsOneWidget);

    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/cantiere/cantiere_detail_screen_test.dart`
Expected: FAIL — the file doesn't exist yet.

- [ ] **Step 3: Create the screen**

```dart
// dart format width=100
// lib/features/cantiere/cantiere_detail_screen.dart
//
// Cantiere info + the "Timbra cantiere" action (relocated from ticket detail — see this app's
// nav-restructure spec) + tickets linked to this cantiere. Reached from CantieriListScreen (no
// ticketId) or from a ticket's cantiere chip (ticketId set, carried through to the Timbra action
// so the resulting session still gets tagged the way it did when the button lived on the ticket).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/vetro_button.dart';
import '../../core/widgets/vetro_card.dart';
import '../../core/widgets/widgets.dart';
import 'cantiere_providers.dart';

class CantiereDetailScreen extends ConsumerWidget {
  const CantiereDetailScreen({super.key, required this.cantiereId, this.ticketId});

  final String cantiereId;

  /// Carried through from a ticket's cantiere chip, when reached that way — see this file's own
  /// header comment. Null when reached from the Cantieri tab directly.
  final String? ticketId;

  static String _statusLabel(int status) {
    switch (status) {
      case 0:
        return 'Attivo';
      case 1:
        return 'Completato';
      case 2:
        return 'Annullato';
      default:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiereAsync = ref.watch(cantiereByIdProvider(cantiereId));
    final ticketsAsync = ref.watch(ticketsForCantiereProvider(cantiereId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Cantiere', showBack: true),
            Expanded(
              child: cantiereAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const UnavailableState(
                  icon: LucideIcons.hardHat,
                  titolo: 'Impossibile caricare il cantiere',
                  motivo: 'Riprova tra poco.',
                ),
                data: (cantiere) {
                  if (cantiere == null) {
                    return const UnavailableState(
                      icon: LucideIcons.hardHat,
                      titolo: 'Cantiere non trovato',
                      motivo: 'Non risulta sincronizzato su questo dispositivo.',
                    );
                  }

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
                        VetroCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cantiere.name,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.ink,
                                ),
                              ),
                              if (cantiere.address != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  cantiere.address!,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              AppBadge(label: _statusLabel(cantiere.status)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        VetroButton(
                          label: 'Timbra cantiere',
                          icon: const Icon(LucideIcons.mapPin),
                          onPressed: () => context.push(
                            AppRoutes.cantiereTimbraPath(
                              cantiereId: cantiere.id,
                              ticketId: ticketId,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionTitle(title: 'Ticket collegati'),
                        const SizedBox(height: 8),
                        ticketsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text(
                            'Impossibile caricare i ticket collegati.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: context.colors.red,
                            ),
                          ),
                          data: (tickets) {
                            if (tickets.isEmpty) {
                              return Text(
                                'Nessun ticket collegato',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: context.colors.inkMuted,
                                ),
                              );
                            }
                            return VetroCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: tickets.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final t = entry.value;
                                  return ListRow(
                                    title: t.title,
                                    showDivider: i != tickets.length - 1,
                                    onTap: () =>
                                        context.push(AppRoutes.ticketDetailPath(t.id)),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/features/cantiere/cantiere_detail_screen_test.dart`

Expected: PASS (2 tests). `AppRoutes.cantiereTimbraPath(cantiereId:)` (Task 3) and
`CantiereTimbraScreen(cantiereId:)` (Task 5) both already exist by this point.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cantiere/cantiere_detail_screen.dart test/features/cantiere/cantiere_detail_screen_test.dart
git commit -m "feat(mobile): add CantiereDetailScreen"
```

---

### Task 8: Router wiring — Cantieri tab, standalone Timbra route

**Files:**
- Modify: `lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: `CantieriListScreen` (Task 6), `CantiereDetailScreen` (Task 7),
  `AppRoutes.cantieri`/`cantieriDetail` (Task 3).
- Produces: shell branch 2 now serves `CantieriListScreen`/`CantiereDetailScreen` instead of
  `TimbraScreen`; `TimbraScreen` becomes a standalone pushed route
  (`parentNavigatorKey: rootNavigatorKey`) rather than a shell branch; the `cantiereTimbra` route
  now parses a `cantiereId` query param.

There is no isolated unit test for router wiring in this codebase (confirmed during planning — no
`app_router_test.dart` exists). Verification for this task is: the app compiles, and Task 9's
`bottom_nav_test.dart` + Task 11's `dashboard_screen_test.dart` (which push through these routes)
passing is the real signal. Do the edit, then run the full test suite at the end of this task.

- [ ] **Step 1: Import the new screens**

Add near the other feature imports in `lib/core/router/app_router.dart`:

```dart
import '../../features/cantiere/cantieri_list_screen.dart';
import '../../features/cantiere/cantiere_detail_screen.dart';
```

- [ ] **Step 2: Pass `cantiereId` through the `cantiereTimbra` route**

In the `GoRoute(path: AppRoutes.cantiereTimbra, ...)` block (around line 170), change:

```dart
      GoRoute(
        path: AppRoutes.cantiereTimbra,
        builder: (context, state) {
          final ticketId = state.uri.queryParameters['ticketId'];
          final customerId = state.uri.queryParameters['customerId'];
          return CantiereTimbraScreen(
            ticketId: ticketId,
            customerId: customerId,
          );
        },
      ),
```

to:

```dart
      GoRoute(
        path: AppRoutes.cantiereTimbra,
        builder: (context, state) {
          final ticketId = state.uri.queryParameters['ticketId'];
          final customerId = state.uri.queryParameters['customerId'];
          final cantiereId = state.uri.queryParameters['cantiereId'];
          return CantiereTimbraScreen(
            ticketId: ticketId,
            customerId: customerId,
            cantiereId: cantiereId,
          );
        },
      ),
```

- [ ] **Step 3: Move `TimbraScreen` out of the shell into a standalone route**

Remove the whole "2 — Timbra" `StatefulShellBranch` block (around lines 226-235):

```dart
          // 2 — Timbra
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'timbra'),
            routes: [
              GoRoute(
                path: AppRoutes.timbra,
                builder: (context, state) => const TimbraScreen(),
              ),
            ],
          ),
```

Replace it with the new Cantieri branch, in the same position (index 2, so the bottom-nav's tab
order and the shell's `currentIndex` stay in lockstep with Task 9's `AppBottomNav.defaultItems`):

```dart
          // 2 — Cantieri
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'cantieri'),
            routes: [
              GoRoute(
                path: AppRoutes.cantieri,
                builder: (context, state) => const CantieriListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    // Full-screen, no persistent bottom nav — same reasoning as ticket detail's
                    // own `parentNavigatorKey` (see that route's comment above).
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => CantiereDetailScreen(
                      cantiereId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
```

Then add a standalone `TimbraScreen` route near the other standalone routes (next to the
`cantiereTimbra` `GoRoute`, right after it):

```dart
      // ── Personal Timbra (pushed from a Dashboard quick action) ──────────────
      GoRoute(
        path: AppRoutes.timbra,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TimbraScreen(),
      ),
```

- [ ] **Step 4: Run the full mobile test suite**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm dart analyze` then `fvm flutter test`

Expected: `dart analyze` clean. Some pre-existing tests will fail here and get fixed in Tasks 9-11
(bottom nav tab list, ticket detail button, dashboard quick action) — that's expected at this
point in the plan; confirm the failures are exactly those three areas and nothing else broke.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat(mobile): wire Cantieri tab into the shell, make Timbra a standalone route"
```

---

### Task 9: Bottom nav — swap Timbra for Cantieri

**Files:**
- Modify: `lib/core/widgets/bottom_nav.dart`
- Test: `test/core/widgets/bottom_nav_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppBottomNavIcons.cantieri`; `AppBottomNav.defaultItems` index 2 is now "Cantieri"
  instead of "Timbra".

- [ ] **Step 1: Read the existing test to see what it currently asserts**

Run: `cat test/core/widgets/bottom_nav_test.dart`

Update whichever assertions name "Timbra" at index 2 to name "Cantieri" instead, following the
existing test's own style. If it iterates `AppBottomNav.defaultItems` by label, update the
expected label list; if it asserts on `AppBottomNavIcons.timbra`, remove that assertion (or point
it at `AppBottomNavIcons.cantieri` if the test specifically checks each icon's identity).

- [ ] **Step 2: Write/update the failing assertion**

Add (or update an existing test to include) this assertion in
`test/core/widgets/bottom_nav_test.dart`:

```dart
test('defaultItems has Cantieri at index 2, not Timbra', () {
  expect(AppBottomNav.defaultItems[2].label, 'Cantieri');
  expect(
    AppBottomNav.defaultItems.map((i) => i.label),
    isNot(contains('Timbra')),
  );
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `fvm flutter test test/core/widgets/bottom_nav_test.dart`
Expected: FAIL — index 2 is still "Timbra".

- [ ] **Step 4: Swap the tab**

In `lib/core/widgets/bottom_nav.dart`, change `AppBottomNavIcons` (around line 12):

```dart
abstract final class AppBottomNavIcons {
  static const IconData dashboard = LucideIcons.home;
  static const IconData ticket = LucideIcons.ticket;
  static const IconData cantieri = LucideIcons.hardHat;
  static const IconData calendario = LucideIcons.calendar;
  static const IconData altro = LucideIcons.moreHorizontal;
}
```

(`timbra` removed — it was the only reference to `LucideIcons.clock` in this file; the Dashboard
quick-action tile added in Task 11 uses `LucideIcons.clock` directly, so removing it here doesn't
orphan the icon's only usage.)

Then change `defaultItems` (around line 56):

```dart
  static const List<AppBottomNavItem> defaultItems = [
    AppBottomNavItem(icon: AppBottomNavIcons.dashboard, label: 'Dashboard'),
    AppBottomNavItem(icon: AppBottomNavIcons.ticket, label: 'Ticket'),
    AppBottomNavItem(icon: AppBottomNavIcons.cantieri, label: 'Cantieri'),
    AppBottomNavItem(icon: AppBottomNavIcons.calendario, label: 'Calendario'),
    AppBottomNavItem(icon: AppBottomNavIcons.altro, label: 'Altro'),
  ];
```

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm flutter test test/core/widgets/bottom_nav_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/bottom_nav.dart test/core/widgets/bottom_nav_test.dart
git commit -m "feat(mobile): swap Timbra tab for Cantieri in the bottom nav"
```

---

### Task 10: Ticket detail — remove the button, add the cantiere chip

**Files:**
- Modify: `lib/features/ticket/ticket_detail_screen.dart`
- Test: `test/features/ticket/ticket_detail_screen_test.dart`

**Interfaces:**
- Consumes: `Ticket.cantiereId` (Task 1), `AppRoutes.cantieriDetailPath` (Task 3),
  `cantiereByIdProvider` (Task 4).

- [ ] **Step 1: Read the existing test's button assertions**

Run: `grep -n "Timbra cantiere\|cantiereTimbra" test/features/ticket/ticket_detail_screen_test.dart`

(Already found during planning: lines ~349, 363, 370 reference the old button — a comment
describing the layout and an `expect(find.text('Timbra cantiere'), findsOneWidget)`.)

- [ ] **Step 2: Update the test — remove the old button assertion, add the chip assertions**

Remove or rewrite the test containing `expect(find.text('Timbra cantiere'), findsOneWidget)` (and
its surrounding comments describing the old two-row button layout) so it no longer expects that
button. Add two new tests:

```dart
testWidgets('shows a cantiere chip when the ticket has one linked', (tester) async {
  // Build the harness the same way this file's other tests do (ProviderScope + a Ticket row
  // seeded with cantiereId set) — mirror an existing test's setup in this file for the exact
  // harness shape, then:

  expect(find.textContaining('Cantiere:'), findsOneWidget);
});

testWidgets('shows no cantiere chip when the ticket has none linked', (tester) async {
  // Same harness, ticket seeded with cantiereId: null.

  expect(find.textContaining('Cantiere:'), findsNothing);
});
```

Fill in the exact seeding/pump calls using this file's own existing setup pattern (read the file
first — it already seeds a `Ticket` row for its other tests; reuse that helper/fixture and just
vary `cantiereId`).

- [ ] **Step 3: Run test to verify it fails**

Run: `fvm flutter test test/features/ticket/ticket_detail_screen_test.dart`
Expected: FAIL — the old test fails because the button check will be removed/rewritten, and the
new chip tests fail because the chip doesn't exist yet.

- [ ] **Step 4: Remove the "Timbra cantiere" button**

In `lib/features/ticket/ticket_detail_screen.dart`, find the bottom-actions block (identified
during planning at approximately lines 434-472 — the comment beginning "Bottom actions — one
primary, state-driven" through the `Column` containing `VetroButton(label: 'Crea rapportino', ...)`
and the secondary `VetroButton(label: 'Timbra cantiere', ...)`). Remove the secondary button and
its `SizedBox(height: 8)` spacer, leaving only:

```dart
          if (ticket.assignedUserId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.sm,
                AppSpacing.pagePadding,
                AppSpacing.base,
              ),
              child: VetroButton(
                label: 'Crea rapportino',
                onPressed: () => _createRapportino(context, ref, ticket, locationAddress),
              ),
            )
          else
            const SizedBox.shrink(),
```

Update the comment above it (was: "one primary, state-driven ... 'Timbra cantiere' is real and
still one tap away, but demoted...") to reflect that Timbra cantiere no longer lives here at all —
it moved to Cantiere detail (see this ticket's cantiere chip instead, added next).

- [ ] **Step 5: Add the cantiere chip**

In the same file, find where `ticket` fields are laid out in the scrollable body (the
`_TicketDetailBody` widget, around line 167 onward — the same area that reads `statusName`/
`typeName`). Add a chip near the top of that body, after the title/status row (the exact
surrounding layout is this file's own — place it where a one-line contextual fact about the
ticket already goes, matching the existing visual rhythm rather than a fixed line number):

```dart
                if (ticket.cantiereId != null) ...[
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final cantiereAsync = ref.watch(
                        cantiereByIdProvider(ticket.cantiereId!),
                      );
                      final label =
                          cantiereAsync.valueOrNull?.name ?? ticket.cantiereId!;
                      return AppChip(
                        label: 'Cantiere: $label',
                        onTap: () => context.push(
                          AppRoutes.cantieriDetailPath(ticket.cantiereId!),
                        ),
                      );
                    },
                  ),
                ],
```

`AppChip` shows a plain text label with no leading icon — fine as-is (the "Cantiere:" prefix in
the label already says what it is), no need to add icon support to the shared widget for this one
call site. Add the import: `import '../cantiere/cantiere_providers.dart';`

- [ ] **Step 6: Run test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/features/ticket/ticket_detail_screen_test.dart`

Expected: PASS.

- [ ] **Step 7: Run the full ticket test directory to confirm no other regression**

Run: `fvm flutter test test/features/ticket/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/ticket/ticket_detail_screen.dart test/features/ticket/ticket_detail_screen_test.dart
git commit -m "feat(mobile): move Timbra cantiere off ticket detail, add a cantiere chip"
```

---

### Task 11: Dashboard — personal Timbra quick-action tile

**Files:**
- Modify: `lib/features/dashboard/dashboard_screen.dart`
- Test: `test/features/dashboard/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `AppRoutes.timbra` (a standalone push route as of Task 8).

- [ ] **Step 1: Read the existing test for the quick-action row**

Run: `grep -n "Nuovo\|Timbra cantiere\|QuickAction" test/features/dashboard/dashboard_screen_test.dart`

- [ ] **Step 2: Check whether `LucideIcons.timer` exists**

Run: `grep -n "timer" lib/core/icons/app_lucide_icons.dart`

If it doesn't exist, use `LucideIcons.clock` for the new tile too (Step 4 below) — the two tiles'
labels already distinguish them, so a shared icon is acceptable; do not add a new icon constant
for this alone.

- [ ] **Step 3: Write the failing test**

Add to `test/features/dashboard/dashboard_screen_test.dart`, following its existing harness
pattern:

```dart
testWidgets('shows a Timbra quick action that pushes the standalone Timbra route', (tester) async {
  // Build with this file's existing harness/overrides.

  expect(find.textContaining('mie\ntimbrature'), findsOneWidget);
});
```

(Match this file's existing pump/harness conventions — read the file first for the exact
`ProviderScope` overrides its other tests already set up, e.g. for `dashboardStatsProvider`/
`visibleTrackersProvider`, and reuse the same setup. If this file's other `onTap` tests assert on
the actual navigation target rather than just label text — e.g. a mock `GoRouter`/route capture —
follow that same technique here instead of a text-only assertion, so this test also verifies the
tile pushes `AppRoutes.timbra` specifically and not `AppRoutes.cantiereTimbra`.)

- [ ] **Step 4: Run test to verify it fails**

Run: `fvm flutter test test/features/dashboard/dashboard_screen_test.dart`
Expected: FAIL — no third tile exists yet.

- [ ] **Step 5: Add the third quick-action tile**

In `lib/features/dashboard/dashboard_screen.dart`, in the "Start something" `Row` (around lines
142-158), the two `Expanded(child: QuickAction(...))` children stay as-is; add a third:

```dart
                child: Row(
                  children: [
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.ticket,
                        label: 'Nuovo\nticket',
                        onTap: () => context.push('/ticket/new'),
                      ),
                    ),
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.clock,
                        label: 'Timbra\ncantiere',
                        onTap: () => context.push(AppRoutes.cantiereTimbra),
                      ),
                    ),
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.clock, // or LucideIcons.timer, see Step 2
                        label: 'Le mie\ntimbrature',
                        onTap: () => context.push(AppRoutes.timbra),
                      ),
                    ),
                  ],
                ),
```

Update the comment above this `Row` (currently: "These are the two things a technician *starts*
from here...") to say three, and that "Le mie timbrature" is a *view*, not a start action — it's
grouped here anyway because it's the personal-Timbra home now that the tab is gone, not because it
fits the section's original "starts from here" framing exactly. If that tension reads badly in
practice, moving it to its own row below is a reasonable adjustment — this is a UI judgment call,
not a hard requirement.

- [ ] **Step 6: Run test to verify it passes**

Run: `fvm dart run build_runner build --delete-conflicting-outputs` then
`fvm flutter test test/features/dashboard/dashboard_screen_test.dart`

Expected: PASS.

- [ ] **Step 7: Run the full mobile test suite**

Run: `fvm dart analyze` then `fvm flutter test`

Expected: `dart analyze` clean, full suite green. This is the final task — confirm nothing from
Tasks 1-10 regressed now that everything is wired together.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/dashboard_screen.dart test/features/dashboard/dashboard_screen_test.dart
git commit -m "feat(mobile): add personal Timbra quick-action tile to Dashboard"
```
