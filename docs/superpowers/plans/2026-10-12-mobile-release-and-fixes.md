# Plan — mobile release for the customer test

**Repo:** `tasktap-mobile` (nested at `mobile/`). Default branch is `main` (not `master`).
**Base:** `origin/main` = `1d507f1` (I2 mobile half, PR #21 merged 2026-10-12).

**Why:** the backend deployed `master` on 2026-10-12, so the backend now speaks the I2 confirm
contract (`{draft, warnings}`, no `reportId`) while the only shipped mobile build (`v1.0.2`) still
parses `reportId` and routes to `rapportiniEditor(reportId)`. It fails on confirm. No external user
holds it — it ships to the Play **internal testing** track and TestFlight only — but the customer
test needs a build that matches the backend.

**Two parts, each shippable alone.** Part A is the release plus the defects that sit on the
customer's path; Part B is the template picker. If the customer test is sooner than the picker, ship
Part A and cut Part B as its own build — do not let the picker gate a working build.

---

## Part A — release + path defects

### A0. Version bump and release (mechanical, do last)

`pubspec.yaml` is `1.0.2+2`; 11 commits of unreleased work sit between `v1.0.2` and `main`. Bump to
`1.0.3+3` and tag `v1.0.3` on `main`.

- **Android:** `android-release.yml` triggers on `workflow_dispatch` (input `upload_to_play`) or a
  `v*` tag; it publishes to the Play `internal` track and overrides `--build-number` itself.
  A dispatch on `main` ships without a tag — the tag is for the record, not the pipeline.
- **iOS:** Codemagic `ios_release` → TestFlight (`codemagic.yaml:8,74-77`). Not visible from here.

Release is the user's action. The plan's job is to make `main` worth releasing.

### A1. Ticket dueDate shows the previous day west of UTC (REAL, on path)

**Not a format bug — a storage bug.** `tickets.dueDate` (`app_database.dart:208`) and
`pendingTickets.dueDate` (`:876`) are plain `DateTimeColumn`s. Drift maps a DateTime to unix seconds
and reads it back as a *local* `DateTime` (`DateTime.fromMillisecondsSinceEpoch`, no `isUtc`), so a
civil date pinned as UTC midnight comes back as the previous calendar day on any device west of UTC.
Formatting cannot recover a date that was already lost on read — `.toLocal()` and raw formatting are
both wrong for these columns.

**The repo already has the right pattern.** `Strumenti.calibrationExpiry` (`app_database.dart:1032-1041`)
is a `TextColumn` holding `'yyyy-MM-dd'`, with the reason written out: *"a Drift DateTimeColumn would
come back local and show the previous day west of UTC (see the dueDate bug in MORNING.md)"*. The wire
helper is `parseDateOnly` / `parseDateOnlyOrThrow` in `lib/core/time/business_time.dart:35,50`, whose
own doc says the value is *"a calendar label, not an instant"* — `DateTime.utc(y, m, d)`.

- Convert both `dueDate` columns to `yyyy-MM-dd` TEXT, reading through `parseDateOnly` and writing
  through one shared formatter. Do **not** hand-format per call site.
- Add a Drift schema bump + migration alongside the existing ladder in `app_database.dart`
  (see the `m.addColumn` entries and the versioned comments around `:1038-1050`, `:1442-1447`, and
  `syncCursorGeneration`'s doc comment for why a bump may need to accompany it). A TEXT column cannot
  be migrated in place from an integer epoch column: migrate by reading the old int and rewriting it
  as the yyyy-MM-dd of its **UTC** day, not its local day.
- Fix the two display sites the verifier found: `step_dettagli_ticket.dart:346` (raw
  `DateFormat('dd/MM/yyyy')`) and `ticket_list_screen.dart:508` (`.format(dueDate.toLocal())`). Both
  must format the civil date via the shared helper; the list's `.toLocal()` is as wrong as the raw
  format, for the same reason.
- **Add `test/features/ticket/edit_ticket_screen_test.dart` to the tz-matrix job's file list.**
  `.github/workflows/ci.yml:80-92` currently covers `ticket_detail_screen_test.dart` but not the edit
  screen, which is precisely why CI has never caught this. A fix without this line is unfalsifiable.
- **Census, do not fix blind:** `app_database.dart` has ~60 `DateTimeColumn`s. Most are instants
  (`createdAt`, `updatedAt`, `startedAt`, `eventTime`, `readAt`) and must stay. Enumerate the ones
  that are really civil dates (`startDate`/`endDate` at `:65-66` and `:282-283`, `activityDate:228`,
  `dateValue:632,994`) and report them as a list with a recommendation — do **not** convert them in
  this plan. Each needs its own judgement about the wire type, and a wrong call silently shifts a
  date.

### A2. Forced sign-out never wipes the previous user's data (REAL, security)

`wipeAllData()` (`app_database.dart:1525`) has exactly one caller in the whole app:
`LoginNotifier.signOut` (`auth_providers.dart:141`), which also clears prefs and resets the zone. The
interceptor's forced path calls the *repository* sign-out instead — `dio_client.dart`:
`await authRepo.signOut(); onForcedSignOut?.call();` — and `ZitadelAuthRepository.signOut` deletes
only the secure-storage refresh token and cached identity. So when an expired session forces a
sign-out, the previous user's Drift rows and prefs survive on the device.

- Route the forced path through the same teardown as a normal logout. Prefer one shared
  "end session" function both callers use, rather than two sequences that must be kept in step.
- Test it: assert a forced sign-out (invalid_grant → `SessionExpired`) empties the Drift tables and
  the prefs, mirroring whatever test covers the normal sign-out today.
- Note the *other* half of this finding is already fixed — the late-`/auth/me` cache write is guarded
  by `_stillCurrent` — so do not re-do that.

### A3. On-device dictation is unreachable on Android (REAL, flagship)

Three independent reasons, all verified:

- `android/app/src/main/AndroidManifest.xml:106-113` — `<queries>` declares only
  `intent.action.PROCESS_TEXT`. There is no `android.speech.RecognitionService` entry, and the
  plugin's own manifest is empty, so nothing merges one in. `speech_to_text` 7.4.0's README requires
  the entry for `targetSdk ≥ 30`, which this app uses.
- The capability is cached for the app's lifetime with **no invalidation anywhere**:
  `dictationCapabilityProvider` (`lib/core/dictation/dictation_service.dart:208`) is documented as
  *"Resolved once and cached: the answer does not change while the app is running"* — but a user can
  download the Italian on-device pack while the app runs, and the answer does change.
- The probe is API ≥ 31 only (`MainActivity.kt:32-38`), returning `false` below that. That part is
  **deliberate and correct** — do not change it; there is no way to ask below 31.

Fix the first two. Adding the `<queries>` entry is the substantive one. For the cache, invalidate on
app resume (and after returning from the settings screen) so a newly installed pack is picked up.

**This one cannot be verified in CI** — it needs a real Android handset with the Italian on-device
pack. Say so in the report; it belongs to I4 device verification. Do not claim it works.

### A4. Office edits to a Bozza are overwritten by the phone's submit (REAL, documented limit — needs a decision)

`submission_queue.dart:305` sends the whole local draft; `ReportSubmitService.cs:283` applies it
unconditionally (`report.Details = request.Details;`), and nothing in the payload carries a version
to compare against. Import explicitly skips locally-held rows (`import_server_report.dart:64-68`,
`sync_service.dart:427-432`), so the phone never refreshes a Bozza the office edited.

This is a **recorded known limit** (`DECISIONS.md` 2026-10-02, `MORNING.md:39`: *"known limit … phone
submit overwrites the office edits … decide if refresh-on-open is wanted"*). It needs a decision, not
a patch:

- **(a) Refresh on open** — stop treating a locally-held draft as untouchable when opening it while
  online, and let the server's copy win where the office changed it. Risk: discards the technician's
  own unsubmitted edits, so it needs a conflict rule, not a silent last-writer-wins in the other
  direction.
- **(b) Carry a version** and reject a stale submit with a 409 the phone can surface.
- **(c) Leave it documented** — acceptable only if the customer test won't have office and phone
  editing the same Bozza, which is exactly the "full lifecycle" scenario they plan to run.

Recommend **(b)** — it fails loudly instead of silently destroying work, and it is the same shape the
backend already uses elsewhere. This plan does not pick for you; it must be decided before the build.

---

## Part B — on-demand template picker (mobile half)

Backend needs nothing. `GET /api/report-templates?documentType=1` is gated on
`RapportiniReportRead` (a permission the technician already holds) and its doc says it exists "for
the picker"; `GET /api/Reports/{id}/pdf?templateKey=` already prints one copy with a chosen template
and cites ADR-0008 for it, falling back rather than failing on an unknown key.

- Anchor: `lib/features/rapportino/rapportino_view_screen.dart:718-752` — the PDF download, with
  `GET /api/Reports/$reportId/pdf` at `:745`.
- Keep the existing PDF action's behaviour (prints the assigned template) and add the ability to
  choose. One-off only: choosing must not change the tenant's assignment — setting the default stays
  in the admin screens.
- UX: a **bottom sheet**, not a popup menu. Field conditions are the bar this codebase is held to —
  gloved hands, sunlight, one-handed — so target sizes and label clarity matter more than density,
  and the sheet should be dismissible by drag. Say in the sheet that the choice applies to this
  print only.
- Degrade to today's single action when the catalogue is empty or still loading.
- Filter to `documentType = 1` (Rapportino). `ReportTemplateDto` carries `name`, `description`,
  `kind` (`Classic`/`AcroForm`) — the wire contract is pinned by the client's own
  `test/contract/openapi_contract_test.dart` snapshot, which already contains this schema.

---

## Constraints (this session's standing rules)

- **Do not run the full `flutter test` suite locally.** The `/mnt/d` mount OOM-kills a heavy run and a
  backgrounded one dies silently and reads exactly like a pass. Per-file runs of the touched tests
  are fine; the full suite is CI's job.
- One agent at a time in this nested repo; never worktree-isolate `mobile/`.
- Never `sed -i` / `perl -i` / in-place python on `/mnt/d` — they silently delete files there.
- Use `/usr/bin/grep`, `/usr/bin/wc`, `/usr/sbin/git`; the `rtk` hook mangles filtered output.
- Explicit-path `git add` only, never `git add -A`. Do not drop `stash@{0}` on
  `fix/mobile-ticket-edit-references`; never a bare `git stash` / `git stash pop`.
- No backend edits. `submission_queue.dart` stays untouched by Part B (the I2 decision).
- **Add the new tests to the tz-matrix job's list when they are time-sensitive** — otherwise the
  defect they pin can only fail on a device west of UTC, which is how A1 hid for three weeks.

## Done means

Per-file test runs green for everything touched; `flutter analyze` clean; the tz-matrix list updated;
the A1 census reported as a list rather than applied; A3 explicitly marked device-unverified; A4
marked as awaiting the decision. CI on the pushed branch is the real gate.
