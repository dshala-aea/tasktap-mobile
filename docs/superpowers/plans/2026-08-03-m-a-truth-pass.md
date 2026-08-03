# M-A — Mobile Truth Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn 37 uncommitted, never-compiled files into a verified baseline: analyzer clean, tests green, every client route proven to exist on the real backend, and every screen either working or honestly declaring itself unavailable.

**Architecture:** Preserve first, then verify. The unreviewed work is committed verbatim on a branch **before** anything is changed, so that every subsequent fix is a reviewable diff rather than an indistinguishable edit to code nobody has read. Verification then proceeds outward: does it compile → do tests pass → do the endpoints it calls actually exist → does each screen handle the failure cases. The output is a baseline commit plus a written gap list that later workstreams (M-B…M-F) build on.

**Tech Stack:** Flutter, Riverpod, Drift (SQLite), dio, go_router, oidc/Zitadel auth, flutter_test + mocktail.

## Global Constraints

- Flutter lives Windows-side: invoke it as `/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter`. WSL has **no Android SDK**, so only `analyze` and `test` run here. `flutter build apk`, emulator runs and device integration tests are user-run on Windows and are **not** steps in this plan.
- The mobile repo is its own git repository, gitignored from the backend repo. Never `git add -A` at the backend root for mobile changes, and never commit mobile files into the backend repo.
- **Drift teardown discipline:** any widget test pumping a screen that watches a Drift stream must end with `await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();` — otherwise `StreamQueryStore.markAsClosed`'s zero-duration timer outlives teardown, the suite hangs, and the failure reads as "A Timer is still pending".
- `ensureVisible(finder)` before tapping any button inside a `SingleChildScrollView`.
- A screen is not "done" until it passes the **release gate**: its endpoint exists and has been called against a real backend, its permission requirement is verified, its error state is implemented, its unavailable state is implemented.
- No new mocks. A screen calling an endpoint that does not exist gets an explicit unavailable state — never a fixture that makes it look alive.

## File Structure

**Create:**
- `docs/api-gap-list.md` — the written output of the audit: every client route, whether it exists on the backend, and the disposition of each gap. Later workstreams read this.
- `lib/core/widgets/unavailable_state.dart` — one widget for "this needs a backend capability that does not exist yet", with a reason string. Replaces per-screen improvisation and the existing `ComingSoonScreen` placeholder.
- `test/core/widgets/unavailable_state_test.dart`
- `tool/extract_routes.dart` — a script that greps the api clients for request paths and prints them, so the route inventory is regenerable rather than hand-maintained.

**Modify (expected, discovered during the audit):**
- `lib/features/admin/**/*_api_client.dart` and screens — whichever call routes the gap list proves absent.
- `lib/core/router/app_router.dart` — route wiring for any screen whose disposition changes.

---

### Task 1: Preserve the unreviewed work as a reviewable baseline

**Files:**
- No source changes. This task produces commits only.

**Interfaces:**
- Produces: branch `m-a-truth-pass` whose first commit is the verbatim uncommitted tree; every later task diffs against it.

- [ ] **Step 1: Confirm what is uncommitted**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
git status --short
git log --oneline -1
```

Expected: HEAD is `e34eb0c`, and 37 entries listed — modified files including `lib/main.dart`, `lib/core/router/app_router.dart`, `lib/presentation/providers/auth_providers.dart`; a deletion of `lib/data/auth/supabase_auth_repository.dart`; and untracked directories `lib/features/admin/`, `lib/core/notifications/`, `lib/data/notifications/`, `lib/features/ticket/steps/`.

- [ ] **Step 2: Branch and commit the tree verbatim**

Do not fix anything yet. This commit is the "what an agent wrote and nobody checked" snapshot.

```bash
git checkout -b m-a-truth-pass
git add -A
git commit -m "chore(M-A): snapshot unreviewed work before auditing it

37 files written by earlier agent sessions and never compiled, run or tested:
the Zitadel auth migration, nine admin CRUD domains already wired into the
router, push notifications, and the new-ticket form. Committed verbatim so the
truth pass produces reviewable diffs instead of edits to unread code."
```

- [ ] **Step 3: Verify the snapshot is complete**

```bash
git status --short
```

Expected: empty output.

---

### Task 2: Establish whether it compiles

**Files:**
- Modify: whichever files the analyzer condemns.

**Interfaces:**
- Produces: an analyzer-clean tree; the compile-error inventory recorded in the commit message.

- [ ] **Step 1: Run the analyzer and capture the output**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter analyze 2>&1 | tee /tmp/claude-0/-mnt-d-AEA-Sviluppi-TaskTap/4d4c7314-1ca1-4d92-938c-c2899654db98/scratchpad/analyze-baseline.txt
```

Expected: unknown — this is the first time this code has been analyzed. Record the exact issue count.

- [ ] **Step 2: Fix errors, one commit per coherent group**

Work errors before warnings, and group commits by cause rather than by file — "unresolved import after the Supabase repository was deleted" is one commit, "missing required constructor argument in admin forms" is another. For each group:

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter analyze 2>&1 | head -40
```

Fix, re-run, and commit with a message naming the cause:

```bash
git add <files>
git commit -m "fix(M-A): <cause in plain words>"
```

**Do not** silence an error by deleting the call site or stubbing the method. If a screen references something that does not exist, that is a finding for the gap list in Task 4, not a thing to paper over — record it and give the screen an unavailable state in Task 5.

- [ ] **Step 3: Verify clean**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter analyze
```

Expected: `No issues found!`

---

### Task 3: Establish whether the tests pass

**Files:**
- Modify: test files broken by the auth migration — `test/presentation/screens/login_screen_test.dart`, `test/presentation/providers/auth_providers_test.dart`, `test/features/altro/notifiche_screen_test.dart` are already modified in the snapshot and are the likely suspects.

**Interfaces:**
- Consumes: the analyzer-clean tree from Task 2
- Produces: a green suite with a recorded test count

- [ ] **Step 1: Run the suite and capture the baseline**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter test 2>&1 | tail -40
```

Expected: unknown. The last recorded green state was 442 tests at commit `a182cc3`, before the D6b work and the Zitadel migration.

- [ ] **Step 2: Triage each failure into one of three buckets**

For every failing test, decide and write down which it is:

1. **Test is stale** — it asserts Supabase-era behaviour that the Zitadel migration deliberately changed. Update the test to the new expected behaviour.
2. **Test is right, code is wrong** — the migration broke something real. Fix the code.
3. **Test hangs** — almost certainly the Drift teardown gotcha. Add the unmount pair to the offending test:

```dart
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
```

Bucket 2 findings are the valuable ones. Record each in the commit message.

- [ ] **Step 3: Add the missing test for the new-ticket form**

`test/features/ticket/new_ticket_form_test.dart` exists in the snapshot but was never run. Confirm it covers the four required fields the backend demands (`customerId`, `locationId`, `statusId`, `typeId` are non-nullable on `CreateTicketRequest`) and that submission is blocked when any is missing. If it does not, add:

```dart
  testWidgets('blocks submit until cliente, sede, stato and tipo are chosen', (tester) async {
    await tester.pumpWidget(buildTestApp(const NewTicketFormScreen()));
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('new_ticket_submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Seleziona un cliente'), findsOneWidget);
    expect(find.text('Seleziona una sede'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
```

Adjust the key and the copy to whatever the screen actually uses — read it first.

- [ ] **Step 4: Verify green**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter test 2>&1 | tail -5
```

Expected: `All tests passed!` with the count recorded.

- [ ] **Step 5: Commit**

```bash
git add test lib
git commit -m "test(M-A): green suite on the audited tree

<N> passing. Stale Supabase-era assertions updated to the Zitadel flow;
<list any bucket-2 findings — real bugs the tests caught>."
```

---

### Task 4: Prove every client route exists on the backend

**Files:**
- Create: `tool/extract_routes.dart`, `docs/api-gap-list.md`

**Interfaces:**
- Consumes: the backend's committed contract at `../docs/api/openapi.snapshot.json` and `../docs/api/app-route-inventory.md`
- Produces: `docs/api-gap-list.md` — the authoritative list of routes, existence, and disposition, read by M-B…M-F

- [ ] **Step 1: Write the route extractor**

Create `tool/extract_routes.dart`:

```dart
// Prints every HTTP path literal used by the app's api clients, one per line,
// as "<file>:<line>\t<method>\t<path>". Run:
//   dart run tool/extract_routes.dart > /tmp/mobile-routes.txt
import 'dart:io';

final _call = RegExp(r"""\.(get|post|put|patch|delete)(?:<[^>]*>)?\(\s*'([^']+)'""");

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final m in _call.allMatches(lines[i])) {
        stdout.writeln('${file.path}:${i + 1}\t${m.group(1)!.toUpperCase()}\t${m.group(2)}');
      }
    }
  }
}
```

- [ ] **Step 2: Run it**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
/mnt/c/Users/DanielShala/Downloads/flutter/bin/dart run tool/extract_routes.dart | sort -u -k3 > /tmp/claude-0/-mnt-d-AEA-Sviluppi-TaskTap/4d4c7314-1ca1-4d92-938c-c2899654db98/scratchpad/mobile-routes.txt
wc -l /tmp/claude-0/-mnt-d-AEA-Sviluppi-TaskTap/4d4c7314-1ca1-4d92-938c-c2899654db98/scratchpad/mobile-routes.txt
```

Expected: one line per distinct call site. Paths built by interpolation (`'/tickets/$id'`) appear with the `$id` intact — that is fine, match them by prefix in the next step.

- [ ] **Step 3: Compare against the backend contract**

For each extracted path, check whether the backend serves it:

```bash
grep -o '"/api/[^"]*"' ../docs/api/openapi.snapshot.json | sort -u > /tmp/claude-0/-mnt-d-AEA-Sviluppi-TaskTap/4d4c7314-1ca1-4d92-938c-c2899654db98/scratchpad/backend-routes.txt
```

Note the two prefix conventions before comparing: the mobile `dio` client's `baseURL` already contains `/api`, so a client path of `/tickets` corresponds to a backend path of `/api/Tickets`. ASP.NET routing is case-insensitive, so compare case-insensitively.

- [ ] **Step 4: Write the gap list**

Create `docs/api-gap-list.md` with one row per distinct route:

```markdown
# Mobile → backend route audit (M-A, 2026-08-03)

Generated from `tool/extract_routes.dart` against `../docs/api/openapi.snapshot.json`.
Regenerate with the same two commands when routes change.

| Client call site | Method | Client path | Backend route | Status | Disposition |
|---|---|---|---|---|---|
| lib/features/admin/customers/admin_api_client.dart:42 | GET | /customers | /api/Customers | ✅ exists | keep |
| ... | ... | ... | — | ❌ absent | unavailable state, reason: <capability> |

## Absent capabilities

One section per missing endpoint: what the screen wanted, what the backend has
instead, and whether it is a backend gap to schedule or a mobile mistake to fix.
```

Fill it in completely — every extracted route gets a row. A route you cannot classify is a finding, not a blank cell.

- [ ] **Step 5: Commit**

```bash
git add tool/extract_routes.dart docs/api-gap-list.md
git commit -m "docs(M-A): audit every mobile route against the backend contract

<N> distinct routes, <M> absent. The extractor is committed so the list is
regenerable rather than a one-off. Absent capabilities are listed with what the
screen wanted and what exists instead."
```

---

### Task 5: Give every gap an honest state

**Files:**
- Create: `lib/core/widgets/unavailable_state.dart`, `test/core/widgets/unavailable_state_test.dart`
- Modify: each screen the gap list marks absent; `lib/features/altro/coming_soon_screen.dart` (replaced by the new widget)

**Interfaces:**
- Consumes: `docs/api-gap-list.md` from Task 4
- Produces: `UnavailableState({required String titolo, required String motivo})` — the one way the app says "this needs something the backend does not have"

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/unavailable_state_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/unavailable_state.dart';

void main() {
  testWidgets('states the reason, not just that something is missing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: UnavailableState(
          titolo: 'Matricole non disponibili',
          motivo: 'Il catalogo prodotti gestisce una sola matricola per prodotto.',
        ),
      ),
    ));

    expect(find.text('Matricole non disponibili'), findsOneWidget);
    expect(
      find.text('Il catalogo prodotti gestisce una sola matricola per prodotto.'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter test test/core/widgets/unavailable_state_test.dart
```

Expected: FAIL — `unavailable_state.dart` does not exist.

- [ ] **Step 3: Write the widget**

Create `lib/core/widgets/unavailable_state.dart`, styled on the design system's `EmptyState` (60px `BG3` circle + 26px `DIS` icon, Sora 700/16 title, Manrope 13 `MUTED` body capped at 280px, centred, 60/30 padding):

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shown where a screen needs a backend capability that does not exist yet.
///
/// Always states the reason. "Prossimamente" tells a technician nothing and hides
/// a real gap behind a promise nobody scheduled.
class UnavailableState extends StatelessWidget {
  const UnavailableState({super.key, required this.titolo, required this.motivo});

  final String titolo;
  final String motivo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(color: AppColors.bg3, shape: BoxShape.circle),
              child: const Icon(Icons.info_outline, size: 26, color: AppColors.disabled),
            ),
            const SizedBox(height: 16),
            Text(titolo, style: AppTextStyles.sora700.copyWith(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                motivo,
                style: AppTextStyles.manrope.copyWith(fontSize: 13, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Read `lib/core/theme/app_colors.dart` and `app_text_styles.dart` first and use whatever the real member names are — the names above follow the design spec's token names, not necessarily the existing Dart identifiers.

- [ ] **Step 4: Run test to verify it passes**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter test test/core/widgets/unavailable_state_test.dart
```

Expected: PASS.

- [ ] **Step 5: Apply it to every gap**

For each row in `docs/api-gap-list.md` marked absent, replace the screen's data-fetching body with `UnavailableState` carrying the reason from the gap list. Delete `lib/features/altro/coming_soon_screen.dart` and repoint `AppRoutes.altroComingSoon` usages (`app_router.dart:511`, `altro_hub_screen.dart:299,316`) at the new widget with a real reason each.

- [ ] **Step 6: Verify**

```bash
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter analyze
/mnt/c/Users/DanielShala/Downloads/flutter/bin/flutter test 2>&1 | tail -5
grep -rn "ComingSoon" lib
```

Expected: no issues, all tests pass, and the grep returns nothing.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "feat(M-A): every gap states its reason

Replaces ComingSoonScreen, which promised a date nobody had set. Each screen
whose endpoint the audit proved absent now names the missing capability, so the
gap is visible to a technician and traceable to docs/api-gap-list.md."
```

---

### Task 6: Record the verified baseline

**Files:**
- Create: `docs/superpowers/plans/2026-08-03-m-a-truth-pass-report.md`

- [ ] **Step 1: Write the report**

Record, with real numbers rather than adjectives: analyzer issues at the start and now; test count at the start and now; routes audited, present, absent; bugs found by category (stale test, real bug, absent endpoint); and what the next workstream should know. Every claim carries the command that produced it.

- [ ] **Step 2: Commit and report back**

```bash
git add docs/superpowers/plans/2026-08-03-m-a-truth-pass-report.md
git commit -m "docs(M-A): truth pass report"
git log --oneline e34eb0c..HEAD
```

The branch is then ready for review. **Do not merge** without the user's device verification — nothing in this plan proves the app runs on hardware, only that it compiles, tests green, and calls endpoints that exist.

---

## Self-review notes

- **Spec coverage:** the mobile spec's M-A section requires analyzer clean, tests green, routes checked against the real backend inventory, a written gap list, and the four-part release gate. Tasks 2, 3, 4, 4, and 5 cover those in order. Task 1 exists because the spec's premise — 37 files nobody has compiled — makes an unreviewable working tree the first real risk.
- **Deliberately not covered:** device builds, emulator runs, hardware integration tests and field testing. Those are user-run on Windows and named as such in the spec's environment constraints; a plan step an agent cannot execute is a lie in a checklist.
- **Type consistency:** `UnavailableState({titolo, motivo})` is defined in Task 5 Step 3 and used under that signature in Step 5 and the Step 1 test.
- **Known unknown:** Task 2 and Task 3 have no predicted output because this code has never been compiled or run. Both tasks therefore capture a baseline first and triage second, rather than asserting an expected count the plan cannot know.
