# Mobile → backend route audit (M-A, 2026-08-03)

Generated from `tool/extract_routes.dart` against
`../docs/api/openapi.snapshot.json` (227 backend routes, committed artifact,
current as of backend `master`). Regenerate with:

```bash
cmd.exe /c "cd /d D:\AEA\Sviluppi\TaskTap\mobile && C:\Users\DanielShala\Downloads\flutter\bin\dart.bat run tool/extract_routes.dart"
```

Then re-run the comparison against a fresh `../docs/api/openapi.snapshot.json`
(comparison logic isn't scripted as a single command — see "Comparison
method" below).

## Result

- **44 call sites** extracted from `lib/**/*.dart`, listed as **44 rows**
  below (one call site per row, throughout). They collapse to **43
  distinct (method, path) routes** — `GET /api/users` is called from two
  places (`admin_api_client.dart:292` and `ticket_api_client.dart:38`)
  with identical semantics, so it appears as two rows pointing at the same
  backend route.
- **43 of 43 distinct routes exist** on the backend, matched by path shape
  (segment-for-segment, case-insensitive, `$id`/`${expr}` interpolations
  treated as matching any `{param}` segment) and by HTTP method.
- **0 absent** — no client call site targets a URL the backend never
  registered.
- **0 ambiguous** by path/method — but see "The one route-existence
  finding" below for one route that exists yet is a documented
  **deprecated alias**, and "Routes present, data path missing" further
  down for a *different* category of problem entirely: routes that exist
  and are correctly named, but that no client code path ever calls, so the
  screens built on them are permanently empty. That second category is
  not a route-existence gap — it is the reason this task exists to feed
  Task 5, and it is detailed in its own section rather than left as a
  prose aside, specifically so Task 5 cannot skim past it.

This is a materially different result than expected going in: Task 1's
agent, despite never running against the backend, named its routes
correctly against 43 of 43 distinct endpoints it called. The one
route-existence finding is below — but the more consequential finding for
Task 5 is "Routes present, data path missing," not this section.

## baseURL convention (verified, not assumed)

`lib/data/api/dio_client.dart:17` sets `baseUrl: Env.apiBaseUrl`, and
`lib/core/config/env.dart:44` defines `Env.apiBaseUrl` as
`String.fromEnvironment('API_BASE_URL', defaultValue: '')` — i.e. the raw
host (e.g. `https://api.tasktap.io`), **not** anything containing `/api`.
Every call site in the codebase includes the `/api/...` segment explicitly
in its path literal (e.g. `_dio.post('/api/customers', ...)` in
`admin_api_client.dart:32`) — confirmed by reading all 8 files that hold a
`Dio` reference, not by inference. So a mobile client path of `/api/foo`
already corresponds 1:1 (case-insensitively) to backend path `/api/Foo` —
there is no extra `/api` prefix to add or strip during comparison, contrary
to the task brief's example convention (`/tickets` → `/api/Tickets`), which
does not describe how this codebase's clients are actually written.

## Comparison method

For each extracted `(method, path)`:
1. Replace `$identifier` and `${expr}` interpolations with a `{param}`
   placeholder.
2. Split into `/`-separated segments; compare segment count and, per
   segment, either literal equality (case-insensitive) or "both sides are a
   placeholder" (`{param}` vs. any `{backendName}`).
3. Confirm the matched backend path's operation object lists the same HTTP
   method.

This was cross-checked two ways: (a) programmatically against
`openapi.snapshot.json`, and (b) by reading the actual C# controller source
for 6 of the less-obvious matches (squadre membri add/remove, ticket
partial-update-by-PUT, users role/isActive query filters, notifications
read/read-all/unread-count, reports controlla/fattura, devices
get/register/unregister) to make sure the snapshot wasn't stale or hiding
an authorization/behavior mismatch that a path-only diff can't see. Findings
from that source read are folded into the "Notes" column below and into
"Out of scope" at the end.

## Route table

| Client call site | Method | Client path | Backend route | Status | Disposition |
|---|---|---|---|---|---|
| lib/features/admin/admin_api_client.dart:160 | POST | /api/cantierei | /api/cantierei (deprecated alias) | ⚠️ exists, deprecated | **mobile mistake to fix** — migrate to canonical `/api/cantieri` (see note below) |
| lib/features/admin/admin_api_client.dart:189 | PUT | /api/cantierei/$id | /api/cantierei/{id} (deprecated alias) | ⚠️ exists, deprecated | **mobile mistake to fix** — same as above |
| lib/data/timbratura/cantiere_worklog_api_client.dart:177 | GET | /api/cantiereworklog | /api/CantiereWorkLog | ✅ exists | keep |
| lib/data/timbratura/cantiere_worklog_api_client.dart:163 | POST | /api/cantiereworklog/end | /api/CantiereWorkLog/end | ✅ exists | keep |
| lib/data/timbratura/cantiere_worklog_api_client.dart:152 | POST | /api/cantiereworklog/start | /api/CantiereWorkLog/start | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:421 | GET | /api/contracts | /api/Contracts | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:438 | POST | /api/contracts | /api/Contracts | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:473 | PUT | /api/contracts/$id | /api/Contracts/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:32 | POST | /api/customers | /api/Customers | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:65 | PUT | /api/customers/$id | /api/Customers/{id} | ✅ exists | keep |
| lib/core/notifications/notification_service.dart:141 | GET | /api/devices | /api/Devices | ✅ exists | keep — verified backend scopes to caller's own devices only |
| lib/core/notifications/notification_service.dart:119 | POST | /api/devices | /api/Devices | ✅ exists | keep |
| lib/core/notifications/notification_service.dart:145 | DELETE | /api/devices/${device['id']} | /api/Devices/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:97 | POST | /api/locations | /api/Locations | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:129 | PUT | /api/locations/$id | /api/Locations/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:311 | POST | /api/materiali | /api/Materiali | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:341 | PUT | /api/materiali/$id | /api/Materiali/{id} | ✅ exists | keep |
| lib/data/notifications/notification_api_client.dart:37 | GET | /api/notifications | /api/Notifications | ✅ exists | keep |
| lib/data/notifications/notification_api_client.dart:49 | PUT | /api/notifications/$notificationId/read | /api/Notifications/{id}/read | ✅ exists | keep |
| lib/data/notifications/notification_api_client.dart:54 | PUT | /api/notifications/read-all | /api/Notifications/read-all | ✅ exists | keep |
| lib/data/notifications/notification_api_client.dart:59 | GET | /api/notifications/unread-count | /api/Notifications/unread-count | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:360 | GET | /api/prodottoassistenza | /api/ProdottoAssistenza | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:373 | POST | /api/prodottoassistenza | /api/ProdottoAssistenza | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:402 | PUT | /api/prodottoassistenza/$id | /api/ProdottoAssistenza/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:571 | GET | /api/reports | /api/Reports | ✅ exists | keep |
| lib/data/reports/report_submit_api_client.dart:47 | POST | /api/reports/$reportId/attachments | /api/Reports/{id}/attachments | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:583 | POST | /api/reports/$reportId/controlla | /api/Reports/{id}/controlla | ✅ exists | keep — but see RBAC note below |
| lib/features/admin/admin_api_client.dart:587 | POST | /api/reports/$reportId/fattura | /api/Reports/{id}/fattura | ✅ exists | keep — but see RBAC note below |
| lib/data/reports/report_submit_api_client.dart:72 | POST | /api/reports/submit | /api/Reports/submit | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:222 | POST | /api/schedules | /api/Schedules | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:259 | PUT | /api/schedules/$id | /api/Schedules/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:495 | GET | /api/squadre | /api/Squadre | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:511 | POST | /api/squadre | /api/Squadre | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:500 | GET | /api/squadre/$id | /api/Squadre/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:536 | PUT | /api/squadre/$id | /api/Squadre/{id} | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:554 | POST | /api/squadre/$squadraId/membri | /api/Squadre/{id}/membri | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:561 | DELETE | /api/squadre/$squadraId/membri/$userId | /api/Squadre/{id}/membri/{userId} | ✅ exists | keep |
| lib/data/sync/sync_service.dart:35 | GET | /api/sync/mobile | /api/Sync/mobile | ✅ exists | keep — path is a `const _path` identifier, not a literal at the call site (see extractor notes) |
| lib/features/ticket/ticket_api_client.dart:20 | POST | /api/tickets | /api/Tickets | ✅ exists | keep |
| lib/features/admin/admin_api_client.dart:283 | PUT | /api/tickets/$ticketId | /api/Tickets/{id} | ✅ exists | keep — verified: backend does a true partial update (only non-null fields), no dedicated assign endpoint exists for admin-assigns-technician, so PUT is the correct/only choice |
| lib/features/admin/admin_api_client.dart:292 | GET | /api/users | /api/Users | ✅ exists | keep — but see pagination/role-filter note below |
| lib/features/ticket/ticket_api_client.dart:38 | GET | /api/users | /api/Users | ✅ exists | keep — but see pagination/role-filter note below (same route as the row above; kept as two rows for one-call-site-per-row consistency with the rest of this table) |
| lib/data/timbratura/worklog_api_client.dart:117 | POST | /api/worklog/mobile/sessions | /api/WorkLog/mobile/sessions | ✅ exists | keep |
| lib/data/timbratura/worklog_api_client.dart:139 | GET | /api/worklog/mobile/today | /api/WorkLog/mobile/today | ✅ exists | keep |

## Absent capabilities

**None.** All 43 distinct routes extracted from `lib/` exist on the backend
with a matching HTTP method. This audit found no case of a mobile screen
calling an endpoint the backend does not have.

That is a genuinely different outcome than the task setup implied ("This is
where the real gaps surface"). It does not mean Task 1's 37 files are
clean — Tasks 2 and 3 already found real bugs at the compile and test
level, and the notes below flag real, actionable problems this audit's
scope (path+method existence) is not designed to catch. It means
specifically: **no screen will 404 because it's calling a URL the backend
never registered.** The risks that remain are behavioral, not existential.

### The one route-existence finding: `/api/cantierei` is a deprecated alias

`admin_api_client.dart` (`createCantiere` at line 160, `updateCantiere` at
line 189) calls `POST /api/cantierei` and `PUT /api/cantierei/{id}` — with
the extra "e" (Italian: "cantiere" = construction site, "cantieri" is the
correct plural; "cantierei" is not a word). The backend controller at
`src/TaskTapAPI.Api/Controllers/CantieriController.cs:21-27` registers
**two** route prefixes on the same controller:

```csharp
[Route("api/cantieri")]                  // canonical (W7 §4.2)
[Route("api/cantierei")]                 // DEPRECATED compatibility route — "cantierei" is a
                                          // typo of "cantieri". Removal condition: delete once
                                          // the Flutter client (mobile/lib/features/admin/
                                          // admin_api_client.dart, currently 2 call sites) has
                                          // migrated to the canonical route.
```

The backend team already anticipated exactly this and left a removal
condition naming this file. **This is a mobile mistake to fix, not a
backend gap to schedule** — the fix is a two-line change (drop the "e" in
both path literals at `admin_api_client.dart:161` and `:190`) and it
unblocks the backend from deleting the compatibility route. Filed as the
single most actionable finding of this audit; recommend fixing it in the
same PR that lands this audit rather than deferring to Task 5, since it's
not an "unavailable state" problem — the route works today either way, it's
purely a cleanup with a backend-side removal condition attached.

## Routes present, data path missing

This is a different category of problem than everything else in this
document, and it is the one Task 5 most needs to see, so it gets its own
heading rather than living as a bullet under "Out of scope." Every other
finding above is about whether a URL the client calls exists on the
backend. This one is the inverse: **the backend GET routes exist and are
correctly named — `GET /api/cantieri` and `GET /api/Materiali` are both
live — but no code path in `lib/` ever calls them, and no code path ever
writes their local cache tables either.** The result is not a broken call;
it's a screen that renders successfully, shows an empty list, and never
throws — the exact "silent failure" this whole audit exists to catch, and
exactly what Task 5's honest-unavailable-state work is supposed to prevent.

**Verified by two greps, not inferred from the sync code alone:**
1. `SyncService._upsert*` (`lib/data/sync/sync_service.dart`) writes
   `customers`, `locations`, `tickets`, `schedules`, `draftReports`,
   `ticketStatuses`, and `ticketTypes` — never `cantieri` or `materiali`.
2. A repo-wide search for any `db.into(db.cantieri)` / `db.into(db.materiali)`
   / `CantieriCompanion` / `MaterialiCompanion` insert anywhere in `lib/`
   (outside the generated `app_database.g.dart`) turns up **zero** writes.
   (`ReportMaterialiCompanion` does appear, but it belongs to a different
   table — `report_materiali`, the materials attached to one report — not
   the `materiali` catalog table these screens read from. Don't conflate
   the two.)

So unlike the routes flagged below in "Out of scope," this isn't a subtle
authorization or pagination bug — it's a complete absence of any producer
for two Drift tables that eleven call sites depend on as their only data
source (see the table below for the exact count and breakdown).

**This is narrower than it first looked.** Three other entities that
looked similarly at-risk — contracts, squadre, prodottoAssistenza — are
*not* affected: they aren't covered by sync either, but each has a
dedicated direct-GET method on `AdminApiClient` (`fetchContracts`,
`fetchSquadre`, `fetchProdottiAssistenza`) that its list screen actually
calls (confirmed: `admin_contract_list_screen.dart`,
`admin_squadra_list_screen.dart`, and `admin_prodotto_list_screen.dart` all
call their respective `fetch*` method). Only **cantieri** and
**materiali** have neither a sync path nor a direct-fetch call — genuinely
orphaned, not just "not synced."

**Affected providers/screens** (all confirmed by reading the file — every
one is a `db.select(db.cantieri)` / `db.select(db.materiali)` read against
a table nothing ever populates):

| Table | Provider / screen | What it's for |
|---|---|---|
| `db.materiali` | `lib/features/magazzino/magazzino_providers.dart:9` (`materialiCatalogProvider`) | Warehouse/materiali catalog screen — already has a `// TODO(backend): warehouses + movements not synced to mobile.` comment at line 8 acknowledging this |
| `db.materiali` | `lib/features/magazzino/magazzino_providers.dart:19` (`materialiCategoriesProvider`) | Category filter chips on the same screen |
| `db.materiali` | `lib/presentation/providers/schedule_providers.dart:103` (`allMaterialiProvider`) | Materiali picker, used when building/editing a schedule |
| `db.materiali` | `lib/features/admin/materiali/admin_materiale_list_screen.dart:17` | Admin materiali list |
| `db.materiali` | `lib/features/admin/materiali/admin_materiale_detail_screen.dart:16` | Admin materiali detail (single-record lookup — empty table means this 404s from the local cache even for a materiale that exists server-side) |
| `db.materiali` | `lib/features/admin/materiali/admin_materiale_form_screen.dart:44` | Admin materiali edit-form prefill |
| `db.cantieri` | `lib/presentation/providers/schedule_providers.dart:129` (`allCantieriProvider`) | Cantiere picker, used when building/editing a schedule |
| `db.cantieri` | `lib/features/timbra/cantiere_timbra_screen.dart:41` (`cantieriProvider`) | **Technician-facing**: the "which cantiere am I clocking into" picker on the cantiere timbratura (worklog) screen — a technician cannot start a cantiere work session through this screen while this table is empty |
| `db.cantieri` | `lib/features/admin/cantieri/admin_cantiere_list_screen.dart:17` | Admin cantieri list |
| `db.cantieri` | `lib/features/admin/cantieri/admin_cantiere_detail_screen.dart:17` | Admin cantieri detail |
| `db.cantieri` | `lib/features/admin/cantieri/admin_cantiere_form_screen.dart:47` | Admin cantieri edit-form prefill |

That's 2 tables, 11 call sites, across an admin CRUD flow, a warehouse
screen, a schedule-building picker, and — most seriously — the
technician-facing cantiere clock-in picker. All of them will render
successfully today, with an empty or "no results" state, and none of them
will show an error, because nothing ever fails: the query against the
local Drift table simply returns zero rows. Recommend this becomes an
explicit Task 5/6 item, distinct from ordinary "unavailable state" work,
because the fix isn't "handle the error gracefully" — there is no error to
handle — it's "wire a data source that doesn't exist yet" (either add
`cantieri`/`materiali` to `SyncService._upsert*`, or give `AdminApiClient`
`fetchCantieri()`/`fetchMateriali()` methods matching the pattern already
used for contracts/squadre/prodottoAssistenza).

## Out of scope (surfaced incidentally, not part of the route-existence audit)

These came up while reading controller source to corroborate the six
less-obvious matches. None are "route absent" findings — the routes exist
— but they're the kind of thing Task 5 (or a follow-up) should know about
because a route "existing" doesn't mean the screen built on it behaves
correctly:

- **`GET /api/Users?role=...` pagination bug.** `UsersController` applies
  `isActive` as a SQL `WHERE` before paging, but applies `role` as an
  **in-memory** filter *after* `ToPaginatedResultAsync` (because `Roles` is
  JSON-serialized, not a queryable column). Mobile's `fetchTechnicians()`
  (`admin_api_client.dart:291`, `ticket_api_client.dart:37`) calls this with
  `role=Technician&isActive=true` — if there are more users than one page
  and non-technicians are interleaved, the technician picker can silently
  return fewer entries than exist, with no error and no obvious symptom
  besides "my technician isn't in the list." Backend bug, not a mobile one;
  worth a ClickUp ticket independent of this audit.

- **`controlla`/`fattura` require Admin/Office role, not just a
  permission.** `ReportsController.Controlla`/`Fattura` check
  `[RequirePermission("write","reports")]` **and** an in-method
  `IsOfficeOrAdminAsync()` guard that 403s a plain Technician even if they
  somehow have "write reports" permission. If `admin/reports` screen
  visibility in mobile is driven off the permission alone (not role), a
  Technician could see the buttons and get an opaque 403 on tap. Worth
  checking against the mobile RBAC gating work referenced in the hardening
  program memory, but it's an authorization-surface question, not a route
  question.

- **`DevicesController.UnregisterDeviceAsync` doesn't verify device
  ownership before soft-deleting** — an authenticated user who obtains
  another user's device GUID (e.g. by enumerating IDs) could deactivate
  their push registration. Low severity (denial-of-a-notification-channel,
  not data exposure), but it's an IDOR and should get its own security
  finding rather than living buried in this doc.

- **Two entities — cantieri and materiali — have no client-side read path
  at all.** See the dedicated "Routes present, data path missing" section
  above for the full list of affected screens/providers; not repeated
  here because it's the single most important finding of this document
  and lives under its own heading precisely so it doesn't get missed.

## Extractor notes

`tool/extract_routes.dart` found **44 call sites → 43 distinct routes**,
zero unmatched-and-silently-dropped literal paths, after two fixes beyond
the brief's starting version:

1. **Whole-file scan instead of line-by-line.** The brief's extractor reads
   `file.readAsLinesSync()` and matches per line. Nearly every call site in
   this codebase wraps the argument list:
   ```dart
   final res = await _dio.post<Map<String, dynamic>>(
     '/api/customers',
     ...
   );
   ```
   The verb+paren is on one line, the path literal on the next — a
   per-line regex never sees both halves together and the call is silently
   invisible. Switched to reading the whole file as one string; Dart's
   `\s` already matches newlines, so no other regex change was needed for
   this once line-splitting was removed. This was **not a hypothetical
   risk**: I ran the brief's script verbatim (byte-for-byte, as a throwaway
   scratch file, deleted afterward) against this codebase before writing
   any fix. It printed **8 lines total, one of them truncated**
   (`/api/devices/${device[` — cut off at the inner quote, see finding #3),
   against 44 real call sites — an 82% silent miss rate. The 8 survivors
   were exactly the single-line, non-generic calls (e.g.
   `await _dio.delete('/api/squadre/$squadraId/membri/$userId');`); every
   call that wrapped its argument list onto the next line — 24 of
   `admin_api_client.dart`'s 27 call sites, and all of
   `ticket_api_client.dart`, `report_submit_api_client.dart`,
   `worklog_api_client.dart`, `cantiere_worklog_api_client.dart`, and
   `sync_service.dart` — was missed outright.

2. **Nested generic type arguments.** `_dio.post<Map<String, dynamic>>(...)`
   and `_dio.get<List<dynamic>>(...)` are the dominant call shape. The
   brief's `(?:<[^>]*>)?` stops at the *first* `>` — the one closing
   `dynamic>` — leaving a stray `>` before the `(` and failing the match.
   Replaced with a one-level-of-nesting-tolerant pattern,
   `(?:<(?:[^<>]|<[^<>]*>)*>)?`. This compounded with fix #1: the very
   first extractor run (whole-file, pre-generics-fix) still only found 22
   of the 44 routes — every call using a nested generic (the majority) was
   still silently dropped until this fix.

3. **Interpolated path segments with an embedded quote.**
   `notification_service.dart:145` calls
   `dio.delete('/api/devices/${device['id']}')` — the `${...}` interpolation
   itself contains a single-quoted string literal (`device['id']`). A plain
   `[^']+` capture stops at that inner quote and truncates the path to
   `/api/devices/${device[`. Handled by treating `${[^}]*}` as an opaque
   unit in the path-body pattern (matches through to the first `}`,
   tolerant of whatever's inside, including quotes) before falling back to
   the general non-quote-non-`$` character class.

4. **Constant reference instead of a literal.** `sync_service.dart` declares
   `static const _path = '/api/sync/mobile';` and calls
   `dio.get<Map<String, dynamic>>(_path, ...)`. Handled with a same-file,
   single-hop resolution pass: when the first argument is a bare
   identifier (not a string literal), search the same file's text for
   `const ... <ident> = '<value>'` and substitute. This is the only
   instance of this pattern in `lib/`, confirmed by grep before writing the
   resolver (not written speculatively).

### Deliberately left unmatched

- **String concatenation to build a path** (`'/api/' + segment`, or
  `'/api/$base/$sub'` style multi-variable interpolation beyond a single
  trailing id) — no instance exists in `lib/` today (verified by manually
  reading every file that references `dio`/`_dio`/`ApiClient`, not just by
  absence of a regex match), so this was not implemented. A future call
  site built this way would be silently dropped with no warning — this is
  the extractor's one real blind spot and should be re-audited if this
  script is reused after new API clients are added.
- **Cross-file constant resolution.** The resolver only looks in the same
  file as the call site. An identifier that isn't found produces a
  `WARN:` line on stderr rather than being silently dropped. In this run,
  the only identifiers that triggered a warning were `key` (from
  `zitadel_auth_repository.dart`'s `FlutterSecureStorage.delete(key: ...)`)
  and `_db` (from Drift's `.delete(_db.someTable)` query builder calls in
  `draft_report_repository.dart` and `work_session_repository.dart`) — both
  are false-positive candidates from the `.get`/`.post`/`.delete` verb-name
  regex matching non-HTTP APIs that happen to share a method name with
  Dio's. They are correctly excluded from the route list (never printed as
  a route), and the warnings are expected noise, not missed routes —
  confirmed by manually reading both files (no network code in either; they
  are pure local-Drift repositories).
- **`.request()` with a runtime-computed method** (e.g.
  `method: someVariable` instead of a string literal) — not present in
  `lib/`; the extractor would print `REQUEST(method unresolved)` if it
  encountered one, rather than silently dropping it, so this is a soft
  failure mode rather than a blind spot.
