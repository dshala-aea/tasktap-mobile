# M-A truth pass — verified baseline report

Branch `m-a-truth-pass`, off backend/mobile-repo commit `c6453d6`, HEAD at the
time of this report `211b68e`. Plan: `docs/superpowers/plans/2026-08-03-m-a-truth-pass.md`.
Full history: `.superpowers/sdd/2026-08-03-m-a-truth-pass/progress.md` (ledger)
and `task-1-report.md` … `task-5-report.md` in the same directory.

## What M-A was

37 `git status` entries (68 files in the final diff) had been written by
earlier agent sessions and **never compiled, run, or tested**: a Zitadel auth
migration replacing Supabase, nine admin CRUD domains (27 screens) wired into
the router, a push-notification stack, and a four-step new-ticket wizard.
Task 1 committed that tree verbatim as a reviewable snapshot (`c620556`,
"chore(M-A): snapshot unreviewed work before auditing it"), matching the
brief's 37-entry count exactly. Tasks 2–5 then established, in order: does it
compile, do tests pass, do the routes it calls exist, and — for the gaps that
remained — does the app tell the truth about them.

**Headline result, stated plainly and not inflated:** the code largely
compiled and ran once environment issues were cleared, and all 43 distinct
backend routes the mobile app calls exist on the backend. M-A's premise was
that "this is where the real gaps surface" at the route-audit step — that premise
was wrong. The real gaps found were elsewhere: two runtime crash bugs, one SDK
incompatibility, two Drift tables with no producer, one unwired backend route,
and three backend-side findings out of scope for this repo. None of that is a
triumph — it is the honest result of a pass whose job was to find out, not to
confirm a hypothesis.

## Environment fact that cost time

The WSL-native `flutter`/`dart` binaries **do not work** on this machine — the
Flutter SDK under `/mnt/c/Users/DanielShala/Downloads/flutter` only has a
Windows `dart-sdk` cached, and its bash frontend scripts (`bin/internal/*.sh`)
are checked out CRLF, which bash chokes on. Every command in this report and
in Tasks 2–5 instead shells through `cmd.exe` to the `.bat` frontends:

```bash
cmd.exe /c "cd /d D:\AEA\Sviluppi\TaskTap\mobile && C:\Users\DanielShala\Downloads\flutter\bin\flutter.bat analyze"
cmd.exe /c "cd /d D:\AEA\Sviluppi\TaskTap\mobile && C:\Users\DanielShala\Downloads\flutter\bin\flutter.bat test"
cmd.exe /c "cd /d D:\AEA\Sviluppi\TaskTap\mobile && C:\Users\DanielShala\Downloads\flutter\bin\dart.bat run tool/extract_routes.dart"
```

This is a durable fact about this machine, not a one-off — the CRLF fix
Task 2 applied lives outside any git repo (in the Windows-side SDK install)
and will recur if that SDK is ever reset or re-cloned.

## Analyzer

| | Issues | Command | Verification |
|---|---|---|---|
| Start (Task 2 baseline, HEAD `c620556`) | **98** (1 error, 97 info) | `cmd.exe /c "... flutter.bat analyze"` | Implementer-reported (Task 2 report), first-ever run of this code |
| Now (this report, HEAD `211b68e`) | **0** | `cmd.exe /c "... flutter.bat analyze"` | **CONTROLLER-VERIFIED** — run directly for this report: `Analyzing mobile... No issues found! (ran in 10.8s)` |

The one error was a real bug (below, "Bugs found"), not a stub or a
placeholder. The 97 info issues were four mechanical categories:
`use_null_aware_elements` (81), `deprecated_member_use` for
`DropdownButtonFormField.value`→`initialValue` (11), `unnecessary_underscores`
(4), `file_names` (1). Fixed across six commits (`ee66325`, `0c181c2`,
`0ba3e71`, `8e64c9b`, `d3a48b5`, plus the lockfile regen `a5493e9`). One of
those mechanical fixes (`dart fix --apply --code=deprecated_member_use`)
introduced a real regression — see "Bugs found" below — caught and reverted
in the same task (`e8cf7be`), not left for review to find.

`flutter analyze` is a Dart-level static check only. It does not verify
against the backend contract (see "Routes audited") and it did not catch the
lucide_icons SDK incompatibility (see "Bugs found") — that only surfaced
under `flutter test`'s kernel compiler.

## Tests

| | Pass | Fail | Command | Verification |
|---|---|---|---|---|
| Last known-green pre-branch (`a182cc3`, ancestor of `c6453d6`) | 442 | 0 | not re-run for this report | Predates both the D6b work and the Zitadel migration — recorded here as context, not re-verified |
| M-A baseline (Task 3, HEAD `7500ea9`) | 346 | 20 (compile-fail) | `cmd.exe /c "... flutter.bat test"` | Implementer-reported (Task 3 report), first-ever test run of this code |
| After lucide_icons shim, before triage | 476 | 12 | same command | Implementer-reported, intermediate state |
| Task 3 complete (HEAD `6a325f5`) | 494 | 0 | same command | **CONTROLLER-VERIFIED** per ledger |
| Task 5 complete (HEAD `211b68e`) | 495 | 0 | same command | **CONTROLLER-VERIFIED** per ledger |
| Now (this report, HEAD `211b68e`) | **495** | **0** | `cmd.exe /c "... flutter.bat test"` | **CONTROLLER-VERIFIED** — run directly for this report, tail: `00:57 +495: All tests passed!` |

The jump from 346→476 is not new coverage — it is tests that previously
couldn't even compile (see lucide_icons below) finally running. The 442
pre-branch figure and the ~495 current figure are not apples-to-apples: this
branch added tests (new-ticket form field coverage, the Firebase-guard
regression test, `unavailable_state_test.dart`) as well as fixing existing
ones, and the suite itself changed shape (Zitadel auth replaced Supabase
auth, which touches auth-adjacent tests). The honest comparison is "0 failing
now, 0 failing at the last known-green point, with a materially different
codebase in between" — not a specific count-for-count delta.

## Routes audited

Command: `cmd.exe /c "... dart.bat run tool/extract_routes.dart"`, output compared
against `../docs/api/openapi.snapshot.json` (227 backend routes). Full detail
in `docs/api-gap-list.md`.

- **44 call sites** found in `lib/**/*.dart`, collapsing to **43 distinct
  (method, path) routes**.
- **43 present / 0 absent / 0 ambiguous** by path-and-method match, verified
  two ways: programmatically against the OpenAPI snapshot, and by reading
  the C# controller source directly for 6 of the less-obvious matches
  (squadre membri, ticket PUT-as-assign, users role/isActive filters,
  notifications, reports controlla/fattura, devices).
- The route-extractor result was independently re-verified by the Task 4
  reviewer: ran the committed script, got byte-identical output, hand-counted
  verb calls per file (44, matching), and hunted for concatenated paths,
  cross-file constants, a second `Dio` instance, and `.request()`/`getUri`
  shapes — none found.

This means no mobile screen 404s against a URL the backend never registered.
It does **not** mean every screen that hits an existing route actually works
end-to-end — see "What remains" and "Backend findings" below for the
behavioral gaps a route-existence audit cannot see.

## Bugs found, by category

### Real runtime/compile bugs (the reason the truth pass existed)

1. **App crashes on first frame whenever Firebase is unavailable.**
   `lib/main.dart`. `TaskTapApp.build()` unconditionally called
   `NotificationService.instance.consumePendingDeepLink()` in a
   `postFrameCallback`; `NotificationService`'s constructor eagerly reads
   `FirebaseMessaging.instance`, which throws `[core/no-app]` unless
   `Firebase.initializeApp()` already succeeded. `main.dart`'s own comment
   documents Firebase-init failure as a **supported, silently-degraded
   path** ("Firebase is optional"), but nothing actually checked whether
   that try/catch had fired. `FIREBASE_ENABLED=true` (default) + a
   real-world init failure (missing config, no Play Services, offline at
   cold start) = full app-shell crash instead of graceful degradation.
   Found by `app_shell_test.dart` / `widget_test.dart` (Task 3).

2. **First fix of #1 was incomplete — caught by review, not by the
   implementer.** Task 3's first pass (`c82a426`) gated two of the three
   call sites that touch `NotificationService.instance`
   (`registerDeviceToken`, the deep-link callback) but missed the third:
   `impostazioni_provider.dart:161-165` (`_syncPushRegistration`), reached
   by tapping the "Notifiche push" toggle in Settings. A logged-in user
   with a real access token tapping that toggle while Firebase is down hit
   the identical `[core/no-app]` crash through a third door. Missed by the
   original test suite because `impostazioni_screen_test.dart`'s toggle
   test never stubbed `repo.currentUser`, so an unrelated null-token
   early-return masked the vulnerable branch. Fix round 1 (`6a325f5`)
   consolidated the guard into a single source of truth,
   `NotificationService.isAvailable` (fail-closed, set only by `main.dart`
   after a successful init), gated the third call site, and added a test
   that stubs a non-null token specifically to exercise the previously-dead
   branch — verified red-then-green, not assumed.

3. **SharedPreferences race — fast toggle tap crashes the settings
   screen.** `lib/features/altro/impostazioni_provider.dart`.
   `ImpostazioniNotifier`'s constructor starts `_loadFromPrefs()`
   (async, awaits `SharedPreferences.getInstance()` before assigning a
   `late final _prefs` field) without awaiting it; `toggle()` reads
   `_prefs` synchronously. A user tapping a switch immediately after
   opening Settings (slow device, cold start) throws
   `LateInitializationError`. Fixed (`f108c57`) by dropping the shared
   `late final` field and calling `SharedPreferences.getInstance()`
   directly in both places (cheap — cached after first call), removing the
   race window entirely.

4. **lucide_icons 0.257.0 is incompatible with the installed Flutter SDK
   (3.44.8 / Dart 3.12.2)** — a fourth failure category outside the
   brief's three documented buckets. `LucideIconData extends IconData`
   fails to compile because `IconData` is now a `final class`; confirmed
   via `flutter pub outdated --show-all` that 0.257.0 is the latest
   release, no fix available upstream. Blocked 20 test files from
   compiling (masked at `flutter analyze` — 0 issues both before and after
   — because the analyzer doesn't run the same kernel-compiler check as
   `flutter test`). Fixed with a local shim,
   `lib/core/icons/app_lucide_icons.dart`, reproducing the ~66 icon
   constants this app uses as plain `const IconData(...)` (codepoints
   copied verbatim from the installed package source, not reinvented),
   swapped into all 48 importing files. Reviewer verified all 66 codepoints
   byte-for-byte against pub-cache with matching `fontFamily`/`fontPackage`
   — zero icons silently changed.

### Mobile mistake (not a backend gap)

5. **`admin_api_client.dart` calls the deprecated `/api/cantierei` alias**
   instead of canonical `/api/cantieri` (create at line 160, update at line
   189). Both routes work today, but the backend controller
   (`CantieriController.cs:21-27`) names this exact mobile file and its
   call-site count as the removal condition for the deprecated route. A
   two-line fix, not applied in this task (kept the route-audit diff to
   extractor + gap list) — flagged as the single most actionable item from
   Task 4's audit.

### Stale/broken tests (not code bugs)

6. `notifiche_screen_test.dart` (4 tests) — fixture tried to bypass an
   async `_loadFromCache()` by setting `state` directly after `super(...)`,
   which raced the real load and lost. Fixed by seeding the real in-memory
   Drift DB instead. (`59b6d4d`)
7. `altro_hub_screen_test.dart` (2 tests) — a fixed-distance scroll drag no
   longer reached "Impostazioni"/logout once the admin CRUD migration grew
   the "Gestione" grid to 10 tiles. Fixed with `scrollUntilVisible`.
   (`59b6d4d`)
8. `cantiere_timbra_screen_test.dart` — Task 5's own regression: a test's
   premise (tap clock-in with zero cantieri seeded) became unreachable once
   the clock-in button was disabled for that state (see below). Fixed the
   premise (seed one cantiere, don't select it), left the assertion
   unchanged.

## What remains — deliberately not fixed on this branch

### Deferred minors (logged in the ledger, not actioned)

- `NotificationService._lastAccessToken` duplicates state that lives in
  `authStateProvider` — a silent token rotation not observed by the
  listener would re-register with a stale token.
- `NotificationService.isAvailable` is a public mutable static — fail-closed
  and single-writer today, weaker encapsulation than the private bool it
  replaced.
- `unawaited(_persist(...))` allows out-of-order persistence on rapid
  double-toggle in Settings.
- `lucide_icons` shim's `LucideIcons` class could be `abstract final class`
  like `AppBottomNavIcons`.
- `_ensureDefaultStatus()` in `new_ticket_form_screen.dart` is a silent
  no-op fallback (picks `.firstOrNull` from the status map, own comment
  admits it's a stand-in for a real `isDefault` lookup); if the cached
  `TicketStatuses` table is ever empty, submission silently no-ops with no
  user feedback.
- `/altro/non-disponibile` route renders `titolo` twice (`ScreenHeader` +
  `UnavailableState` heading); no widget test covers that route
  end-to-end; a brief window in admin form screens between `initState` and
  the async Drift lookup where `_prefillFailed` is still false.
- Two Altro-hub `UnavailableState` sites (Audit log, Ruoli e permessi) pass
  a bare feature name where the other 9 phrase it as "X non disponibile" —
  inconsistent, not false.
- `ComingSoonPlaceholder` in `oggi_screen.dart` — dead code, unreferenced
  anywhere in `lib/`, same "Disponibile a breve" pattern `ComingSoonScreen`
  was deleted for. Not routed to today, so it can't mislead a user; flagged
  for a later cleanup pass.

### Two structural findings, deliberately not fixed

1. **Cantieri and materiali have no client-side data path at all.**
   `GET /api/cantieri` and `GET /api/Materiali` both exist and are
   correctly named on the backend, but nothing in `lib/` ever calls them
   or writes their local Drift tables — verified by grepping for any
   `db.into(db.cantieri)` / `db.into(db.materiali)` / `CantieriCompanion` /
   `MaterialiCompanion` insert (zero hits outside generated code) and
   confirming `SyncService._upsert*` covers only customers, locations,
   tickets, schedules, draftReports, ticketStatuses, ticketTypes. This
   affects **11 call sites** across a warehouse screen
   (`magazzino_providers.dart`), a schedule-building picker
   (`schedule_providers.dart`), and 6 admin cantieri/materiali screens —
   most consequentially `cantiere_timbra_screen.dart`'s `cantieriProvider`,
   the technician-facing "which cantiere am I clocking into" picker, which
   cannot succeed while the table is empty (always, today). Contracts,
   squadre, and prodottoAssistenza looked similarly at risk but are *not*
   affected — each has a direct-GET `AdminApiClient` method its list screen
   calls. This branch gave all 11 sites an honest `UnavailableState`
   (Task 5, commit `3da8913`) instead of a silent empty list, and disabled
   the cantiere clock-in button rather than leave a live control that can
   never succeed — but did not wire the missing data path itself. Full
   detail and the affected-provider table:
   `docs/api-gap-list.md`, section "Routes present, data path missing".
   Fix options for the next workstream: add `cantieri`/`materiali` to
   `SyncService._upsert*`, or give `AdminApiClient` `fetchCantieri()` /
   `fetchMateriali()` matching the pattern already used for
   contracts/squadre/prodottoAssistenza.

2. **`GET /api/Reports/{id}/pdf` exists server-side, unwired on mobile.**
   Confirmed live in `openapi.snapshot.json:8279` ("Generate PDF for a
   report", 200 → PDF file); confirmed zero Dio call sites anywhere in
   `lib/` (`grep -rni "pdf" lib` — only the button's own label and one doc
   comment mention the word). Found during Task 5's post-review
   banned-phrase sweep: `rapportino_view_screen.dart:271`'s "Scarica PDF"
   button showed a "Disponibile a breve" snackbar — the exact
   no-affordance pattern the rest of the branch was removing. Fixed
   (`211b68e`) to name the real gap in the copy rather than promise a
   date. The underlying feature (call the route, download/display the PDF)
   is not built. Same category as finding 1 — belongs in the same
   follow-up.

## Backend findings — for the backend team, not this repo

Three findings surfaced while cross-checking the route audit against C#
controller source (not from independent backend testing — read the source,
did not run backend tests). These are out of scope for a mobile repo to fix
and are recorded here so they are not lost in ledger-only history:

1. **`GET /api/Users?role=` pagination bug** —
   `UsersController.cs:128-140`. `isActive` is applied as a SQL `WHERE`
   before paging; `role` is applied **in-memory after** paging, because
   `Roles` is JSON-serialized and not a queryable column. Mobile's
   technician picker (`fetchTechnicians()` in both `admin_api_client.dart`
   and `ticket_api_client.dart`) calls this with
   `role=Technician&isActive=true` — with more than one page of users and
   non-technicians interleaved, the picker can silently return fewer
   technicians than exist, no error, no obvious symptom besides "my
   technician isn't in the list."
2. **`ReportsController.Controlla`/`Fattura` RBAC double-gate** — both
   check `[RequirePermission("write","reports")]` **and** a separate
   in-method `IsOfficeOrAdminAsync()` role check, so a Technician who
   somehow holds "write reports" permission still gets a 403. If mobile's
   admin/reports screen gates button visibility on the permission alone
   (not role), a Technician could see the button and hit an opaque 403 on
   tap.
3. **Device-unregister IDOR** — `DeviceRegistrationService.cs:87-100`,
   `UnregisterDeviceAsync` does not verify the caller owns the device
   before soft-deleting it. An authenticated user who obtains another
   user's device GUID (e.g. by enumeration) could deactivate their push
   registration. Low severity (denies a notification channel, no data
   exposure) but is a real IDOR and deserves its own security finding.

All three are reviewer-confirmed against the actual C# source (not just the
OpenAPI snapshot), per the ledger's Task 4 entries.

## What the next workstream needs to know

Two plan defects this pass exposed, so they aren't repeated:

- **The route extractor in the plan, run verbatim, silently dropped 82% of
  call sites.** The brief's starting script used
  `file.readAsLinesSync()` + a per-line regex; nearly every call site in
  this codebase wraps its argument list across lines
  (`_dio.post<...>(\n  '/api/path',\n  ...)`), which a per-line scan can
  never see whole. Run byte-for-byte as given, it printed 8 lines against
  44 real call sites. The implementer measured this before fixing it
  (scratch run, deleted before commit) rather than assuming the brief's
  approach worked. Three more defects compounded it: nested generic type
  args (`(?:<[^>]*>)?` stops at the first `>`), an interpolation containing
  a quote (`${device['id']}`), and one constant-reference call site
  (`sync_service.dart`'s `_path`). Any future reuse of a route extractor
  against this codebase needs to account for all four, not just the first.
- **The documented baseURL convention was wrong.** The plan assumed
  client paths needed `/api/` prefixed onto them for comparison (example
  given: `/tickets` → `/api/Tickets`). In this codebase,
  `Env.apiBaseUrl` (`lib/core/config/env.dart:44`) is a bare host with no
  `/api`, and every one of the 8 files holding a `Dio` reference already
  writes the `/api/...` segment explicitly in its path literals. The
  comparison is 1:1, case-insensitive, nothing to strip or add. Verified
  by reading the base URL definition and all 8 call-site files directly,
  not by trusting the plan's stated convention.

Other things worth carrying forward:

- `dart fix --apply` is not safe to run blindly on this codebase —
  Task 2's `deprecated_member_use` auto-fix (`value:` → `initialValue:`)
  silently changed runtime behavior in two dropdowns with externally-reset
  state, caught only by manual re-inspection of all 11 rewritten call
  sites after the fact.
- `admin_api_client.dart` and `ticket_api_client.dart` are large,
  repetitive CRUD wrappers with **zero test coverage** — no matching files
  under `test/` for either, confirmed by Task 2. Anything built on top of
  them is leaning on untested code.
- `createMateriale`/`createCantiere` POST and stop — no local Drift
  insert, no re-fetch — so a user who creates one via the admin FAB will
  not see it appear in the list they just used to create it, independent
  of the missing-sync finding above.
- This branch proves the app compiles, its test suite is green, and every
  route it calls exists on the backend. **It proves nothing about the app
  running on real hardware** — device builds, emulator runs, and hardware
  integration tests are explicitly out of scope for M-A (user-run on
  Windows) and were not exercised here. Do not merge on the strength of
  this report alone; the plan's own gate requires the user's device
  verification first.

## Commit record

```
git log --oneline c6453d6..HEAD
```

```
211b68e fix(M-A): name the reason on the PDF download stub too
3da8913 feat(M-A): give every gap an honest state
5f5e698 docs(M-A): sharpen gap-list per review — data-path-missing gets own section
f60b187 docs(M-A): audit every mobile route against the backend contract
6a325f5 fix(mobile): gate the third NotificationService.instance call site
c028724 test(mobile): cover new-ticket form's four required backend fields
59b6d4d test(mobile): fix broken fixtures in notifiche/altro_hub screen tests
f108c57 fix(mobile): fast toggle tap could crash settings screen
c82a426 fix(mobile): app crashes on first frame whenever Firebase is unavailable
1b71b37 fix(mobile): replace lucide_icons import with a local IconData shim
7500ea9 docs(M-A): correct the flutter invocation for this environment
e8cf7be fix(M-A): restore controlled reset for wizard dropdowns after value->initialValue rename
d3a48b5 fix(M-A): rename admin_prodottoList_screen.dart to lower_case_with_underscores
8e64c9b fix(M-A): drop redundant extra underscores in unused-param wildcards
0ba3e71 fix(M-A): rename DropdownButtonFormField 'value' to 'initialValue'
0c181c2 fix(M-A): use null-aware map-entry syntax in API client request bodies
a5493e9 fix(M-A): regenerate lockfile after Supabase-to-Zitadel dependency swap
ee66325 fix(M-A): notification refresh had no access token to re-register with
c620556 chore(M-A): snapshot unreviewed work before auditing it
```

19 commits, `c620556..211b68e`, on top of the pre-branch tip `c6453d6`.
