# Plan — mobile half of (b): send the version the phone last saw, and survive a 409

**Repo:** `mobile` (`tasktap-mobile`). **Branch:** `feat/mobile-submit-version`, cut from
`feat/mobile-release-fixes` @ `7646085` — **not** from `main`, deliberately (see "Stacking" below).

**Why this exists.** The backend now refuses a rapportino submit built against a version the
client no longer holds (`tasktap-api` PR #62, branch `feat/submit-expected-version`):

- `POST /api/reports/submit` accepts an optional `expectedVersion`.
- `GET /api/reports/{id}` returns the report row's `version` (PostgreSQL `xmin`, decimal string).
- A mismatch is the **existing** 409 `concurrency_conflict` (`ErrorHandlingMiddleware`), not a new
  error type.
- `null` means "do not check" — every build that predates the field keeps today's behaviour.

Without this half the guard is inert: the phone never sends `expectedVersion`, so the backend's
`null` path runs and the office's edit is destroyed silently. This is the half that makes the
backend change mean anything.

## Stacking — do not rebase onto `main`

`main` is schema v37; `feat/mobile-release-fixes` is v38 (`Tickets.dueDate` / `PendingTickets.dueDate`
→ `yyyy-MM-dd` TEXT). **This work takes v39.** Two branches must never each claim v38 for different
shapes: whichever merged second would leave devices stamped 38 with the wrong schema, and the
`from < 38` due-date conversion would either never run (the bug survives silently) or run twice
against already-TEXT values. Keep this branch stacked; if the release branch lands first, rebase
this one on the new `main`.

## The requirement that decides whether this works

**The version must be captured when the phone last *saw* the server's copy — never fetched at
submit time.** A version fetched immediately before submitting always matches the row it is being
compared against, so the guard would detect nothing while looking perfectly correct, and the tests
would still pass. Concretely: persist it when the phone ingests a server report, and read it back
out of the draft on submit. If any part of this design ends up calling `GET /api/reports/{id}`
inside the submit path, stop — that is the failure mode.

Corollary, and the second thing to get right: **enumerate every path that brings a server report
into a submittable draft on this device**, and either set the version there or say why not. Known
ones:

- `import_server_report.dart:74-108` — the `insertOnConflictUpdate` that mirrors the fetched report
  into Drift. This is where `report.version` belongs.
- `sync_service.dart:428-433` — the background sync-down. It **skips** any row with
  `isLocalOnly == true` (`continue`), i.e. the technician's working copy is never refreshed from the
  server, so it is not the path that sets the version for a draft being edited. Rows it does write
  arrive from the bulk mobile-sync DTO, which carries no version (adding one is a backend change,
  out of scope here). Establish what that means for those rows and **report it** — do not leave it
  as an unexamined gap.
- `createCantiereReportDraft` — mints a server Report id for a locally-created draft. If the office
  can edit that report before the phone submits, a version is wanted; the phone can only learn it by
  fetching, and fetching *at that moment* is legitimate (it is the last thing the phone saw).

## Design

1. `ServerReportDto` (`lib/data/reports/server_report_dto.dart:118`) gains `version` (`String?`).
   Read it from the raw JSON map, not a generated model: `GET /api/reports/{id}` is a hand-rolled
   anonymous projection with **no response schema in the OpenAPI snapshot**, so `version` will never
   appear in any generated client type. This DTO is already hand-written against raw JSON for
   exactly this reason.
2. `DraftReports.expectedVersion` — nullable `TextColumn`. Migration v39 (`from < 39` →
   `m.addColumn`), `schemaVersion` 38 → 39.
3. Set it at every ingestion point identified above.
4. `SubmitReportRequest` (`lib/data/reports/submit_report_request.dart:12`) gains
   `expectedVersion`, emitted in `toJson` only when non-null; populated in
   `submission_queue.dart:_buildRequest` (`:282`) from the draft. A locally-created draft that has
   never been on the server leaves it null → the backend skips the check, exactly as today.
5. **409 is terminal and explained.** `_isTransient` (`submission_queue.dart:275-280`) already
   returns false for 409, so the row stays `failed`, keeps its attempt budget and is never
   auto-retried — that part needs no change and must not regress. What is missing is the sentence:
   the technician currently gets the generic `humanErrorMessage(e, azione: 'inviare il
   rapportino')`. A 409 must say what actually happened — the rapportino was modified in the office
   after this copy was taken — so the person holding the phone knows to stop retrying and call.
   **Never delete the draft on a 409** (`:248`).

## Out of scope — do not invent

There is no resolution UI for a conflicted draft in this plan. After a 409 the draft stays on the
device, `failed`, with its local edits intact, and the technician is told why. A merge or
re-import flow ("take the office's version", "keep mine") is a product decision for the owner, and
building a guess at it would discard someone's work in one direction or the other. State plainly in
the hand-back that the draft is a dead end until that decision is made — do not paper over it with
a retry button.

## Tests

- A draft imported from a server report carries that report's `version`, and the submit payload
  carries it back out (round-trip, through the real `_buildRequest`).
- A draft created locally (never on the server) sends `expectedVersion: null`.
- **The regression test for the reported defect:** a 409 from the submit endpoint leaves the row
  `failed`, `errorTransient == false`, does not increment the attempt counter, does not delete the
  draft, and produces a message naming the conflict rather than the generic send failure.
- The migration test builds a real v38 database and asserts the added column exists and existing
  rows survive with `expectedVersion` null. Follow the shape of
  `test/data/local/migration_v38_test.dart`.
- Whatever the ingestion-path investigation concludes, pin it with a test so the boundary of the
  guard is explicit rather than assumed.

## Constraints

- `ServerReportDto` is mirrored by tests; a field added on one side and not the other is invisible to
  the compiler. Check `test/data/reports/` fixtures.
- The full suite OOM-kills on this mount. Run only the touched files locally and say so; CI is the
  gate.
- New test files must be added to the tz matrix file list in `.github/workflows/ci.yml` (~`:84-95`)
  or they will not run there — the same omission that let the due-date bug live.
- Never `sed -i` / `perl -i` / in-place python on `/mnt/d`.
- Explicit-path `git add` only.

## Done means

`flutter analyze` clean; the targeted tests written and executed; migration test green; the
ingestion paths enumerated with an explicit statement of which ones set the version and which do
not; the 409 message written; the hand-back states what could not be run locally.
