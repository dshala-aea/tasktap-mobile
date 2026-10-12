# I2 confirm resolves — mobile cut-over — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the copilot's Conferma mean what the server now makes it mean — a resolved draft the phone turns into its own local rapportino — so a technician who confirms a voice/AI draft gets an editable rapportino on the phone instead of a server report the phone then has to download and resynchronise.

**Architecture:** Apply, do not import. `POST /api/ai/conversations/{id}/confirm` now resolves the draft against real tenant data and persists nothing (spec §5.4), so the client owns the write. Mobile writes the resolved draft into the editor's own Drift draft — the same tables, the same rows, the same columns the wizard already fills by hand — and then uses the existing save/submit path. The offline `SubmissionQueue` is not touched and is not extended: it already makes exactly one server call, it is already idempotent by `Idempotency-Key`, and of the five writes a report needs, that is the only one the server makes retry-safe.

**Tech Stack:** Flutter/Dart, Drift (SQLite, schemaVersion 37 — unchanged), Riverpod (`StateNotifierProvider.autoDispose`), dio, `flutter_test` + `mocktail`. No backend work: I2 landed on `origin/master` as PR #61.

**Spec:** `/mnt/d/AEA/Sviluppi/TaskTap/docs/superpowers/specs/2026-10-09-voice-rapportino-architecture-design.md` (root repo) — §5.4 (the confirm contract), §5.5 (the client split: **mobile applies, web creates**), §9 I2 acceptance ("mobile's editor shows the applied draft"). This repo's own offline decisions, which this plan must not contradict: `/mnt/d/AEA/Sviluppi/TaskTap/mobile/docs/superpowers/specs/2026-10-08-offline-architecture-reanalysis-design.md` — Option E §5, scope D-1(a) §10, and §6.7 "**Retries. Unchanged:** … `SubmissionQueue` keeps its 5-attempt transient cap." Cross-repo hand-off: `/mnt/d/AEA/Sviluppi/TaskTap/docs/superpowers/plans/2026-10-10-i2-confirm-resolves-backend.md`, which exists on `origin/master` of the root repo (**not** in its working tree, which is a divergent checkout — do not go looking for it with an editor). It names this work as "mobile (apply the draft; retire the copilot's `importServerReportForEditing` call)" and calls the file `2026-10-10-i2-confirm-resolves-mobile.md`. This plan is dated one day later than that forward reference; the content is the same work.

Paths are absolute throughout, because this plan is read from `mobile/` but half its evidence lives in the root repo one directory up, and a relative path that is right in one of them is a lie in the other.

## Revision note (2026-10-12, first pass)

Four corrections to the task brief, each read out of the source rather than assumed. The first is the one that changes the shape of the plan; the other three are field-level facts that would have produced a DTO that compiles, analyzes clean and parses to null.

1. **Mobile does NOT adopt the five-call write sequence. Web does.** The brief described a server write sequence — `POST /api/Reports` → `PUT .../staff` → `POST .../materiali` → `PUT .../observations` → `POST /api/Reports/submit` — and asked how `submission_queue.dart` should express it. It should not: that sequence is the **web** client's shape, and the binding authority says so three times over. Spec §5.5: "**Mobile** applies the returned draft to the editor's own model, which it already owns, and then uses the existing save/submit path… **Web** creates its server report when the editor opens, using the existing `POST /api/Reports`." The backend plan's hand-off names the two client tasks as "the web (`create-on-open` + `sessionStorage` recovery, §5.5) and **mobile (apply the draft; retire the copilot's `importServerReportForEditing` call)**". Spec §9's I2 acceptance criterion is "**mobile's editor shows the applied draft**" — an editor outcome, not a server-object outcome. So mobile's cut-over ends in a local Drift write, and the single server call it makes is the one it already makes.

   The sequence was checked against the controllers anyway, and it is real on the server — this is a scope correction, not a "the endpoints do not exist" correction. All five verified on `origin/master`:

   | # | Route | Action | Idempotent on retry? | Verified at (`origin/master` = `2feeb3e3`) |
   |---|---|---|---|---|
   | 1 | `POST /api/Reports` | `ReportsController.Create` | **No** — mints a new `Report` per call | `[HttpPost]` `:326`, `Create` `:328`, `CreateReportRequest` |
   | 2 | `PUT /api/reports/{reportId}/staff` | `ReportStaffController.BulkUpsert` | Yes — upsert keyed ReportId+UserId | `:70`/`:72`, `List<UpsertReportStaffRequest>` |
   | 3 | `POST /api/reports/{reportId}/materiali` | `ReportMaterialeController.Create` | **No** — see point 2 | `:77`/`:79`, `UpsertReportMaterialeRequest` |
   | 4 | `PUT /api/reports/{reportId}/observations` | `ReportControlObservationsController.BulkUpsert` | Yes — upsert keyed TicketControlId | `:81`/`:84`/`:86`, `List<UpsertReportControlObservationRequest>` |
   | 5 | `POST /api/Reports/submit` | `ReportsController.Submit` | Yes — the only `Idempotency-Key` in the set | `:533`/`:538`, `[FromHeader(Name = "Idempotency-Key")]` `:540` |

   **Read every one of these with `git show origin/master:<path>`, never from the working tree.** This repo's checkout is divergent — at the time of writing `HEAD` is `ebdc01da` and `origin/master` is `2feeb3e3`, and route-level differences between them are real (the working tree has been observed missing an endpoint that `origin/master` declares). A route list taken from an open editor is a statement about somebody's afternoon, not about the contract. The same rule is why Task A1 merges the snapshot from `origin/master` rather than copying the root repo's working-tree file.

   Step 4 is the `PUT`, not the POST bulk form. `ReportControlObservationsController` declares `[Route("api/reports/{reportId:guid}/observations")]` and **two** mutating endpoints under it:

   - **`[HttpPut] BulkUpsert`** (`:81` attribute, `:84` method, `[FromBody] List<UpsertReportControlObservationRequest> requests` at `:86`) → `_reportService.BulkUpsertObservationsAsync(...)` → `Ok(new MessageResponse("Observations updated"))`. **This is the one.** A JSON array of per-control answers.
   - **`[HttpPost("bulk")] Bulk`** (`:97`, `:100`) → `_bulk.ApplyAsync(...)`. This route **is real** and exists on `origin/master`; it is simply the wrong one here. Its body, from `BulkObservationService.cs:14`, is `BulkObservationRequest(IReadOnlyList<Guid> ProdottoAssistenzaIds, IReadOnlyList<Guid>? TemplateControlIds, bool? BoolValue, string? AppendNote, IReadOnlyList<Guid>? ControlLineageIds = null)` — "apply these template controls to every selected asset, setting one bool and appending a note". An asset-level apply-to-all over materialised checklist instances: **no per-control typed values at all**, so it cannot carry a resolved answer even in principle. (`AppendNote` is documented as "never an answer", and the bulk SET path is restricted to boolean-type controls.) The snapshot's `BulkObservationRequest` properties are `[appendNote, boolValue, controlLineageIds, prodottoAssistenzaIds, templateControlIds]`, which is the same statement in the other medium.

   **The three observation shapes are identical, `note` included.** This is worth stating flatly because it is the kind of "one field off" that gets assumed rather than checked, in both directions. On `origin/master`: `AiResolvedControl(Guid TicketControlId, string? StringValue, bool? BoolValue, DateTime? DateValue, decimal? NumberValue, string? Note)` (`AiConversationDtos.cs:86`), `UpsertReportControlObservationRequest` (`ReportDtos.cs:282`, `Note` at `:293`), and `SubmitReportControlloDto` (`SubmitReportRequest.cs:151`, `Note` at `:162`) all declare exactly `{ticketControlId, stringValue, boolValue, dateValue, numberValue, note}` — verified in the source and in `origin/master`'s snapshot, where all three schemas carry those six properties and no others. So no field is dropped anywhere on the way through, and there is nowhere for an implementer to go looking for one.

2. **The retry semantics, stated exactly — the crux the brief asked for.** Of the five writes, four are safe to repeat and one is not, and the unsafe one is data-dependent:

   - **Step 3 is not retry-safe, and it is the only destructive one.** `ReportMaterialeController.Create` → `ReportService.AddMaterialeAsync` mints a fresh `ReportMateriale.Id` and calls `RecordScaricoFromReportMaterialeAsync` **inside the same transaction**. `StockMovementService` inserts a new `MovimentoMagazzino` with no dedupe on any natural key. So a retried `POST .../materiali` writes a second report-material row and a second scarico: **stock is depleted twice, silently, and the second depletion is permanent.** The danger is not uniform, which makes it worse than a plain non-idempotent endpoint: `RecordScaricoFromReportMaterialeAsync` only moves stock when `MaterialeId` **and** `MagazzinoId` are both set and `Quantity > 0`, so a free-text-only line retries harmlessly while a catalogue line from a magazzino does not. A queue that retried this call would be correct for some rows and quietly wrong for others.
   - **Step 3 cannot be repaired client-side.** The client cannot detect the double-depletion (both calls return 200 and the report is identical) and cannot prevent it (the material row id is server-minted, so the client has nothing to key a "did I already send this line?" check on). The repair is a server-side idempotency key on this route, or a client-supplied material line id the server upserts by — the same mechanism step 5 already has. Neither exists today.
   - **Steps 1, 2 and 4 carry no `Idempotency-Key` either**, and are safe for different reasons: 2 and 4 are natural upserts, 1 is a create whose retry is *always* a duplicate (so any client sequence must treat step 1 as "never retry blind", which means persisting the created id before anything else, which is precisely the state machine the brief asked me to design).
   - **Step 5 is safe because the server short-circuits before the transaction.** `ReportSubmitService.SubmitAsync` reads the idempotency record and returns the stored result **before** `ExecuteInTransactionAsync`, i.e. before the material loop that calls `RecordScaricoFromReportMaterialeAsync` — so a replayed submit does not double-deplete. There is a second path for a key claimed but never completed (process death after commit, response lost): it re-reads the report and returns it if `InviatoAt` is set and the caller owns it, rather than re-running the state machine and answering "già in stato Inviato" forever.
   - **And the offline hazard the brief asked about does not exist on mobile.** "Offline between step 1 and step 3" requires mobile to have performed step 1. It never does: after this plan the confirm path's writes are all to Drift, and the only network call in the submission lifetime is step 5, which is atomic, idempotent and replayed from a persisted key. Mobile can be offline for the entire interval between the technician's words and a successful submit without ever holding a half-written server object.

   **Consequence, recorded as a Global Constraint rather than as work:** do not route this path through steps 1–4. If a future change must, the material write needs a server-side idempotency key first; a client-side state machine over step 3 ships the double-depletion and hides it, because both attempts succeed.

3. **Two field-name traps confirmed, and a third the brief did not name.** From `origin/master`'s snapshot, `AiConversationConfirmResponse` requires `{title, details, materialiNotRequired, customerSignoffText, ticketId, cantiereId, locationId, staff, materials, controlli, warnings}`. So: the arrays are **`materials`** and **`controlli`** (not `materiali`, not `observations`) — confirmed; and there is **no `isAiAssisted`** in the response — confirmed, the client owns it (`CreateReportRequest` and `SubmitReportRequest` both take it; `ConfirmResponseBuilder` never sets it). The trap the brief did not mention is that the **draft** shape and the **resolved** shape are two different DTOs with similar names, and the resolved one is not the draft one with fields filled in:
   - `AiDraftMaterialUsage` (already in the client) reads `materialId`, `name`, `quantity`, `state`.
   - `AiResolvedMaterial` reads `materialeId`, `freeTextName`, `quantity`, `unitOfMeasure`, `notes` — no `state`, no `name`, and `materialId` is now `materialeId`.
   - `AiDraftControlAnswer` reads `{ticketControlId, stringValue, boolValue, numberValue, state}`; `AiResolvedControl` reads the same four plus `dateValue` and `note`, and drops `state`.
   Reusing `AiDraftMaterialUsage` to parse the confirm response compiles, analyzes clean, and yields an empty list of materials — the same class of silence the `controlId`/`ticketControlId` bug had. The replacement DTO is new and separate (Task B1), and `state` is replaced by `warnings[]`, which is the server's own statement of what it could not resolve.

4. **The snapshot re-sync is a merge, not a copy, and the repo's own documented refresh command is currently wrong.** `test/contract/openapi_contract_test.dart`'s header says to refresh with `cp ../docs/api/openapi.snapshot.json test/contract/openapi.snapshot.json`. That path resolves to the **root repo's working tree**, which is on `feat/i2-confirm-resolves` and carries a stale 298-schema generation, and it does not contain the confirm schema at all. Following the documented command would **delete 40 schemas** the app's own gate asserts — including every `Sync*Dto` the inbound half checks — and **add 2** (`CatalogueFieldDto`, `FieldRefDto`), for a net file-size difference of 38 schemas that hides both movements. (Measured, not inferred: `|mobile| = 336`, working tree `= 298`, `|mobile − worktree| = 40`, `|worktree − mobile| = 2`. The two set differences are printed by Task A1 Step 1, so the script and this prose cannot drift apart.) The correct source is `origin/master`'s snapshot, and even that is not a fast-forward in either direction:

   - **Mobile is 4 behind:** `AiConversationConfirmResponse`, `AiResolvedControl`, `AiResolvedMaterial`, `AiResolvedStaff`.
   - **Mobile is 4 ahead:** `SyncAgentDto`, `SyncCommessaDto`, `SyncContractDto`, `SyncProdottoAssistenzaDto` — produced by backend commit `1950b3d7 feat(sync): ship the reference entities a ticket is made of`, which exists only on local branch `feat/offline-reference-sync` and is on no origin ref (`git branch -r --contains 1950b3d7` is empty; `origin/master`'s `MobileUserSyncResult` has none of those properties). If that branch is never pushed or landed, a naive `cp` regresses the gate to a contract the shipped app depends on.
   - **`MobileUserSyncResult` is also ahead by 4 properties** (`agents`, `commesse`, `contracts`, `prodottiAssistenza`), and `UpsertReportMaterialeRequest` differs inside its properties without differing in any key: `quantity.maximum` is `100000000` on mobile and `9999999.999` on `origin/master`, and `unitPrice.maximum` is `100000000` against `99999999.99`. A constraint change, invisible to a key-based gate — the merge keeps mobile's values and records them here rather than silently adopting master's, because narrowing a bound no assertion exercises is a change nothing would catch.

   Task A1 merges both sides and lets the gate prove it: the mobile inbound gate compares `wireKeys` against the snapshot **in both directions**, so it fails loudly on either a regression or a stale merge. That check is the verification, and it is mechanical.

## Revision note (2026-10-12, second pass — after an independent review)

Six corrections. The first two are defects that would have shipped broken code, and they are the reason this pass exists rather than being folded in quietly.

1. **`applyConfirmedDraft` now writes `isAiAssisted` itself, and the plan's earlier claim that no notifier touches are needed was exactly backwards.** The first pass had Task B3 call `ReportEditorNotifier.markAiAssisted()` after the apply, justified by "`reportEditorProvider` is `autoDispose`, so writing the rows before navigating is sufficient — nothing needs to be pushed into a live notifier." That reasoning is sound for *reads* and wrong for *writes*: `markAiAssisted` autosaves the entire header out of `state`, and a just-constructed provider's `state` is a blank placeholder until the async `_hydrate()` resolves. Calling it would have flushed blanks over the draft that had just been written — silent, no exception, and precisely the failure the notifier's own comment at `:525` records having already happened once. The flag now rides in `applyConfirmedDraft`'s own `saveDraft` companion (Task B2), B3 no longer touches that file at all, and the `markAiAssisted` constraint (Global Constraints, sixth bullet) states the trap for anyone who reaches for the obvious writer later. The tell that this was real rather than theoretical: B4's own happy-path assertion `find.text('Pompa bloccata')` would have failed under the first-pass design.

2. **The `validateDraft` change was unbuildable.** `DraftValidationResult` exposes only `issues`, `isValid`, `isReadyToSubmit` and `italianMessages` — there is no `field` member — and `DraftValidationIssue` has six members and no `missingLocation`. The first pass asserted `result.field == 'locationId'` and deferred the check itself to "the same failure shape the title check uses", which is a shape that does not exist: the title check is `issues.add(...)`, a statement, not a return. Task B3 now adds the enum member, its Italian string, and an additive `issues.add`, and asserts the member by name.

3. **The Phase-B safety test was vacuous.** It captured Dio request paths while driving the screen through `_FakeAiApiClient`, a class that `extends AiApiClient` and overrides the methods — so no request ever reached Dio and the captured list was empty no matter what the app did. It passed on a right design and would have passed on the wrong one. Rebuilt (B4 Step 5) on a real `AiApiClient` over a recording `HttpClientAdapter`, the harness `ai_api_client_test.dart` already uses, and given a **positive control**: it also asserts the confirm call *is* observed, so a mis-wired adapter fails loudly instead of producing three empty lists and a tick.

4. **The snapshot numbers were the net difference, not the movement.** The root working tree is 40 schemas behind the mobile copy and 2 ahead of it; only the file sizes differ by 38. Stated as 40-and-2 throughout, and Task A1 Step 1's script now prints both sets so the prose cannot drift from the measurement again. `unitPrice.maximum` (`100000000` vs `99999999.99`) is recorded alongside `quantity.maximum`, since a key-based gate can see neither.

5. **Four identifiers in the first pass did not exist.** `_seedInternalUser`, `_widgetRefStub`, `_clientServing`, and `DraftValidationResult.field` were invented while writing test sketches. Each would have been a compile error, or — worse, in the case of the harness helpers — a plausible-looking test that never touched the code it named. All four are gone: B2's test harness is now copied from `create_draft_test.dart`'s real `UncontrolledProviderScope` + `Consumer` shape, and B1's second test uses the real Dio `_Adapter` pattern. `controlRowId` is cited at `:42`, not `:43`, and `SubmitReportRequest.LocationId` at `Submit/SubmitReportRequest.cs:23`, not `ReportDtos.cs:23`.

6. **Two things the reviewer asked for and this pass did not do, deliberately.** `fallbackTitle` was removed from `applyConfirmedDraft`'s signature rather than documented, because an empty title is a legitimate outcome (B2) and an optional substitute is the invention that function exists to avoid. And the label change's blast radius is now named explicitly — `ai_copilot_screen_test.dart:233`, `:254` and the shared `confirmFlow` helper at `:265` (called from `:287`, `:334`, `:353`, `:384`) — because a copy edit that breaks four call sites reads in CI as a vanished button, not as a renamed string.

## Global Constraints

- **One working tree.** Everything in this plan happens in `/mnt/d/AEA/Sviluppi/TaskTap/mobile` (a **nested git repo**, branch `main`). No backend change; I2 is already on `origin/master` as PR #61.
- **Do not route this path through the five-call write sequence.** Mobile applies the resolved draft to its own local report and submits once. See Revision note point 1 for the authority and point 2 for why step 3 cannot be made retry-safe from the client. A future reviewer adding a server-side "create on confirm" path here is re-introducing a double-depletion, not making the design more robust.
- **`importServerReport` is NOT deleted.** Spec §5.5 says it is deleted "**only after** confirming it has no other consumers or required side effects". It has one: `rapportini_list_screen.dart:362` opens a server-side **Bozza** that arrived as a header-only sync row, and needs the full children fetched before the editor opens or the editor's submit would replace the server's data with an empty set. That consumer is unaffected by I2 and keeps its call. Only the copilot's call site is retired (Task B4).
- **`locationId` is nullable on the confirm response and must never be defaulted.** The schema types it `["null","string"]` and says so: "may be null when nothing resolved — never Guid Guid.Empty, this codebase's 'never resolved' sentinel, which a client that persisted it would pin a report to with nothing downstream to reject it." `SubmitReportRequest.LocationId` is a non-nullable `Guid` (`src/TaskTapAPI.Application/Services/Reports/Submit/SubmitReportRequest.cs:23`, **not** `ReportDtos.cs` — the submit DTOs live in their own file) and `ReportSubmitService` validates it with `EnsureExistsAsync<Location>(...)`. Drift's `DraftReports.locationId` is non-nullable text defaulting to `''`. So an AI-resolved draft with a null location passes everything on the phone and is rejected by the server at submit — see Task B3.
- **`isAiAssisted` is the client's to set, and it is set by `applyConfirmedDraft`, in Drift, in the same write as the draft.** Nothing on the wire carries it: `ConfirmResponseBuilder` never sets it and `SubmitReportRequest` takes the client's own value. **The value is `true`, and it is ratified rather than incidental** — ADR-0016 §2 makes the flag coarse provenance ("sticky and set late. Set where generated text enters the draft, never cleared"), and Confirm is where the AI-drafted text enters the record. The web plan's sibling constant (`AI_DRAFT_IS_AI_ASSISTED`, `frontend/src/features/rapportini/api.ts`) was flipped from `false` to `true` on 2026-10-12 to agree with this side; do not harmonise this one the other way. Today `ReportEditorNotifier.markAiAssisted()` is the only writer and only the single-shot `ai_draft_action.dart` path calls it — **but that method must not be used on this path**, and the reason is a data-loss trap, not a style preference. See the constraint immediately below.
- **Never call `markAiAssisted()` on a freshly-constructed `reportEditorProvider`.** `markAiAssisted` sets `state.copyWith(isAiAssisted: true)` and then awaits `_autosave()`, whose `_buildHeaderCompanion()` writes `title`, `ticketId`, `cantiereId`, `details`, `locationId`, `materialiNotRequired` and more **straight from `state`** (`lib/presentation/providers/report_editor_providers.dart:881-885` and `:1126-1150`). The provider's `state` begins as a blank placeholder and is only corrected by `_hydrate()`, which is asynchronous and merely assigned to `ready` in the constructor (`:504`). `reportEditorProvider` is `autoDispose`, so `ref.read(reportEditorProvider(localId).notifier)` in the copilot constructs it that very instant. The result: `markAiAssisted()` flushes a **blank header over the draft `applyConfirmedDraft` just wrote** — silently, with no error, exactly the failure the file's own comment at `:525` documents as having already happened once. The fix is structural, not a `await ready` patch at the call site: **provenance is written by `applyConfirmedDraft`'s own `saveDraft` companion** (Task B2), so the flag lands in the same Drift write as the data it describes and no notifier is ever touched on this path. The `ai_draft_action.dart` precedent does not transfer — there the editor is already on screen and hydrated.
- **Schema version does not change.** Every column the apply path writes already exists in `draft_reports`, `report_staff`, `report_materiali`, `report_controlli`. No migration, no `build_runner` regeneration needed for the schema. If a task finds itself wanting a new column, that is a signal the task is wrong, not that the schema is.
- **Never `sed -i`, `perl -i`, or in-place Python on `/mnt/d`** — it silently deletes files on this mount. Use the Edit tool, or read-and-write.
- **Git:** explicit-path `git add` only, never `git add -A`. Commit trailers: `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- **`flutter test` must run in the FOREGROUND under an explicit timeout** — e.g. `timeout 900 flutter test`. A backgrounded run dies silently on this mount and reports nothing, which reads exactly like a pass. Never launch it with `&`, `nohup`, `run_in_background`, or from a monitor; never run it concurrently with another suite. The same applies to `flutter analyze`.
- Copy is Italian and matches the existing tone. No English strings in mobile UI.
- **Recorded, not fixed here:** `SubmissionQueue._buildRequest` builds `SubmitReportControlloDto` without `note`, so a checklist answer's note is written to Drift by the editor and dropped at submit. Verified: `SubmissionQueue` omits it; `ReportEditorNotifier._controlloToCompanion` writes it (`report_editor_providers.dart:1243`); the backend's `SubmitReportControlloDto` accepts it; the mobile snapshot already declares it. It is **not** part of this plan because I2 cannot produce a control note — `ControlValueMapper.Map` never sets `Note` on a resolved control, and `ConfirmPlanBuilder` sets the "Da verificare" note on *materials*, not controls. It is a one-line fix with its own test, and it belongs in its own change so its absence here is visible rather than assumed.
- **Out of scope, explicitly:** any `POST /api/Reports` create-on-open for mobile; a client-side multi-step submission state machine; new `DraftSubmissionState` values; the web client's own cut-over (separate repo, separate plan); offline confirm (the confirm call needs the network once — after it, everything is local, which is the whole point).

## Review Focus

The five inputs most likely to bite a real technician. Each line names the task whose tests pin it.

1. **A confirm whose response is parsed by the wrong DTO.** `AiResolvedMaterial` and `AiDraftMaterialUsage` share no field for the material's identity, so the plausible reuse compiles and silently yields nothing — the technician confirms, the editor opens empty, and every check is green. → Task B1, where the shape is pinned against the snapshot by a test that reads the schema, not the class.
2. **An AI draft the server resolved without a location.** The response says `null` where `SubmitReportRequest` needs a real `Guid`; Drift will happily hold `''`; the editor will show a plausible form; the submit is rejected with a message about a location the technician never typed. → Task B3.
3. **A rapportino that is genuinely AI-assisted and does not say so — or, worse, says so at the cost of the draft it was applied to.** The provenance flag is the client's alone, and a path that forgets it produces a report the office cannot distinguish from one typed by hand, permanently. The obvious way to set it — `ReportEditorNotifier.markAiAssisted()` — is the trap: it autosaves the whole header from a `state` that is still blank while `_hydrate()` resolves, silently blanking the draft. → Task B2 (which writes the flag itself) and the `markAiAssisted` constraint (Global Constraints, sixth bullet).
4. **A confirmed draft the technician believes is filed and which is only in Drift.** After this change Conferma no longer creates anything server-side, so the state the technician lands in is "a local Bozza, not yet sent" — and the copy, the button and the toast must all say that, or the AI path becomes the one place in the app where a rapportino looks sent and is not. → Task B4.
5. **A test suite that keeps passing because it still asserts the old contract — or because it asserts nothing at all.** Four widget tests in `ai_copilot_screen_test.dart` are built on the import path and on `AiConversationConfirmResult(reportId: 'rpt-1')`; if they are adapted by making the fake return whatever the new code wants, the suite proves nothing about the endpoint. The same failure in a subtler form is a negative test over a method-overriding fake: an empty list of observed calls looks identical whether the code made none or the harness never connected. → Task B4 Steps 2, 4 and 5, where the fake is rebuilt and the negative test carries a positive control.

---

# Phase A — the contract, pinned

Phase A is independently shippable and has no dependency on Phase B: it corrects the snapshot the CI gate reads and the DTO the app parses. It is first because B1's test asserts against the snapshot, and a stale snapshot would let B1's assertions pass against the wrong schema.

**Working directory for every task in this phase:** `/mnt/d/AEA/Sviluppi/TaskTap/mobile`.

---

### Task A1: re-sync the contract snapshot by merge, and let the gate prove both directions

**Files:**
- Modify: `test/contract/openapi.snapshot.json` (merged, not copied)
- Modify: `test/contract/openapi_contract_test.dart` (the header's refresh command, which presently points at a stale file)

**Interfaces:**
- Consumes: `git show origin/master:docs/api/openapi.snapshot.json` from `/mnt/d/AEA/Sviluppi/TaskTap`.
- Produces: nothing new. The snapshot gains 4 schemas (`AiConversationConfirmResponse`, `AiResolvedControl`, `AiResolvedMaterial`, `AiResolvedStaff`) and keeps the 4 it is already ahead on plus the 4 `MobileUserSyncResult` properties. `AiResolvedMaterial` is what Task B1's DTO is written against.

**Why:** the brief's snapshot claim is correct in its two headline facts and understates the trap. Mobile is 4 schemas behind and 4 ahead; it is also ahead by 4 properties inside a schema that exists on both sides, and the file the repo's header tells you to copy from is 40 schemas behind — and 2 ahead — of this file, and does not contain the schema this plan exists to consume. A `cp` in either of the two documented-looking directions breaks the gate; the merge is the only version that passes, and the gate is what proves it rather than a reading of a diff.

- [ ] **Step 1: Read the real difference, from `origin/master`, and write it down**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap
git fetch origin
python3 - <<'PY'
import json, subprocess
def sch(s): return json.loads(s)['components']['schemas']
mob = sch(open('mobile/test/contract/openapi.snapshot.json').read())
mas = sch(subprocess.run(['git','show','origin/master:docs/api/openapi.snapshot.json'],
                         capture_output=True, text=True).stdout)
print('mobile', len(mob), 'origin/master', len(mas))
print('MOBILE AHEAD :', sorted(set(mob)-set(mas)))
print('MOBILE BEHIND:', sorted(set(mas)-set(mob)))
for n in sorted(set(mob) & set(mas)):
    if json.dumps(mob[n], sort_keys=True) != json.dumps(mas[n], sort_keys=True):
        print('SHAPED DIFFERENTLY:', n)
PY
```

Expect exactly: ahead `SyncAgentDto, SyncCommessaDto, SyncContractDto, SyncProdottoAssistenzaDto`; behind `AiConversationConfirmResponse, AiResolvedControl, AiResolvedMaterial, AiResolvedStaff`; shaped-differently `MobileUserSyncResult` and `UpsertReportMaterialeRequest`. If the numbers differ, the backend moved again — stop and report the new sets rather than proceeding on these notes.

Also confirm the trap, so the header change in Step 4 is justified by evidence rather than by a guess:

```bash
python3 -I -c "
import json
w=json.load(open('/mnt/d/AEA/Sviluppi/TaskTap/docs/api/openapi.snapshot.json'))['components']['schemas']
m=json.load(open('/mnt/d/AEA/Sviluppi/TaskTap/mobile/test/contract/openapi.snapshot.json'))['components']['schemas']
print('root working tree:', len(w), 'has confirm schema:', 'AiConversationConfirmResponse' in w)
print('a naive copy would DELETE', len(set(m)-set(w)), 'schemas mobile depends on')
print('and ADD', len(set(w)-set(m)), sorted(set(w)-set(m)))
"
```

Expect `DELETE 40`, `ADD 2 ['CatalogueFieldDto', 'FieldRefDto']`. That pair of numbers is the whole argument for the merge: a copy moves in **both** directions at once, and the file sizes differ by 38, which is exactly the wrong number to reason from.

- [ ] **Step 2: Merge, keeping both sides — do not `cp`**

Write the merged file with a script, so the merge is a recorded transformation and not a hand edit:

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap
python3 - <<'PY'
import json, subprocess, collections
path = 'mobile/test/contract/openapi.snapshot.json'
mobile = json.load(open(path), object_pairs_hook=collections.OrderedDict)
master = json.loads(subprocess.run(['git','show','origin/master:docs/api/openapi.snapshot.json'],
                                   capture_output=True, text=True).stdout,
                    object_pairs_hook=collections.OrderedDict)

mob_s = mobile['components']['schemas']
mas_s = master['components']['schemas']

# The four AI schemas come from master; everything else mobile already holds is kept verbatim.
ADDED = ['AiConversationConfirmResponse','AiResolvedControl','AiResolvedMaterial','AiResolvedStaff']
for n in ADDED:
    assert n in mas_s, n
    mob_s[n] = mas_s[n]

# MobileUserSyncResult: keep mobile's four extra properties, take master's shape for the rest.
import copy
merged = copy.deepcopy(mas_s['MobileUserSyncResult'])
mob_props  = mob_s['MobileUserSyncResult']['properties']
mob_req    = list(mob_s['MobileUserSyncResult'].get('required', []))
for k, v in mob_props.items():
    if k not in merged['properties']:
        merged['properties'][k] = v
        if k in mob_req:
            merged.setdefault('required', []).append(k)
mob_s['MobileUserSyncResult'] = merged

json.dump(mobile, open(path, 'w'), indent=2, ensure_ascii=False)
print('wrote', path, len(mob_s), 'schemas')
PY
```

Two things this deliberately does **not** do: it does not take master's `UpsertReportMaterialeRequest` (a `quantity.maximum` constraint difference with no key difference — adopting it changes no assertion in any gate, and taking it would silently narrow a limit the app's own editor may rely on; record it instead), and it does not re-sort the file (a whole-file reorder makes the next real diff unreadable).

- [ ] **Step 3: Prove the merge with the gate, in the foreground**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
timeout 900 flutter test test/contract/
```

Expect PASS. This is the verification, and it is not decorative — the inbound half (`sync_inbound_contract_test.dart`) compares each DTO's `wireKeys` with the snapshot's properties **in both directions** and asserts `MobileUserSyncResult` declares every member the app reads, so a merge that dropped the 4 `Sync*Dto` schemas or the 4 reference properties fails here by name. If it passes with fewer schemas than Step 1 reported, the file was truncated — check `len(schemas)` before believing a green run.

Record the outcome in the commit message: the two schema counts before and after, and which four schemas came from `origin/master`.

- [ ] **Step 4: Correct the refresh command in the header, and say why**

In `test/contract/openapi_contract_test.dart`, replace the header line

```dart
/// **Refreshing:** `cp ../docs/api/openapi.snapshot.json test/contract/openapi.snapshot.json`.
```

with the procedure that is actually safe on this repo, including the reason:

```dart
/// **Refreshing:** the copy in the root repo's WORKING TREE is not the source of truth — on
/// `feat/i2-confirm-resolves` it is a 298-schema generation that does not contain
/// `AiConversationConfirmResponse` at all, and copying it would DELETE 40 schemas this file's gate
/// asserts while ADDING 2 (`CatalogueFieldDto`, `FieldRefDto`). Copy from the pushed branch instead:
///     cd ../ && git show origin/master:docs/api/openapi.snapshot.json > /tmp/openapi.master.json
/// and MERGE it, never overwrite: this file is ahead of `origin/master` on the four `Sync*Dto`
/// reference schemas (backend `1950b3d7`, on no origin ref yet) and on four `MobileUserSyncResult`
/// properties. The inbound half below fails by name in either direction, which is the point:
/// run `timeout 900 flutter test test/contract/` and let it tell you whether the merge held.
```

- [ ] **Step 5: Leave the `Sync*Dto` debt where it can be seen**

The four `Sync*Dto` schemas in this file are the only record of a backend contract that exists on one unpushed local branch. Add a short comment at the top of the snapshot's own consumer — `test/contract/sync_inbound_contract_test.dart`, above the `readKeys` map — stating: these four are ahead of `origin/master`, produced by backend commit `1950b3d7` on branch `feat/offline-reference-sync`, which is on no origin ref; when that branch lands, this file's copy becomes a plain fast-forward and the merge procedure in `openapi_contract_test.dart` can go back to a copy. One paragraph, no task. (This is a note left in the repo, not a file written by this plan.)

- [ ] **Step 6: Commit**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
git add test/contract/openapi.snapshot.json test/contract/openapi_contract_test.dart \
        test/contract/sync_inbound_contract_test.dart
git commit -m "chore(contract): merge the I2 confirm schemas in, and stop copying a stale snapshot

Mobile was 4 schemas behind origin/master (the four Ai*Resolve* / confirm schemas) and
4 ahead (the reference Sync*Dto family, from a backend commit on no origin ref), plus
4 ahead inside MobileUserSyncResult. The header's refresh command pointed at the root
repo's working tree, which is a 298-schema generation that does not contain
AiConversationConfirmResponse at all — following it would have deleted 40 schemas this
repo's own gate asserts and added 2, a net movement of 38 that hides both.

Also records that UpsertReportMaterialeRequest's numeric bounds differ from origin/master
independent of any key change: quantity.maximum 100000000 vs 9999999.999, unitPrice.maximum
100000000 vs 99999999.99. A key-based gate cannot see a constraint, so it is written down
rather than silently adopted or silently dropped.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Phase A gate

Run: `timeout 900 flutter test test/contract/` — expected PASS, `flutter analyze` clean.

Then confirm the two facts Phase B depends on, directly from the merged file:

```bash
python3 -c "
import json
s=json.load(open('test/contract/openapi.snapshot.json'))['components']['schemas']
c=s['AiConversationConfirmResponse']
print('required :', c['required'])
print('locationId:', c['properties']['locationId']['type'])
print('material  :', sorted(s['AiResolvedMaterial']['properties']))
print('control   :', sorted(s['AiResolvedControl']['properties']))
print('staff     :', sorted(s['AiResolvedStaff']['properties']))
print('isAiAssisted present:', 'isAiAssisted' in c['properties'])
"
```

Expect `locationId` typed `["null","string"]`, `isAiAssisted` absent, and the three resolved shapes exactly as Revision note point 3 records them. Task B1 is written against this output; if it differs, B1 is written against the wrong thing.

---

# Phase B — the cut-over

Phase B is the feature. It replaces the confirm result with the shape the endpoint returns, applies it to a local draft, and retires the copilot's import. Every write is to Drift; the only network call in the whole lifetime of such a rapportino is the submit the queue already makes.

**Working directory for every task in this phase:** `/mnt/d/AEA/Sviluppi/TaskTap/mobile`.

---

### Task B1: `AiConversationConfirmResult` becomes the shape the endpoint actually returns

**Files:**
- Modify: `lib/data/ai/ai_api_client.dart` (`AiConversationConfirmResult` replaced by `AiConversationConfirmResponse` + three resolved shapes)
- Modify: `test/data/ai/ai_api_client_test.dart` (the two confirm tests)
- Modify: `test/contract/sync_inbound_contract_test.dart` (add the confirm DTOs to the inbound `readKeys` gate)

**Interfaces:**
- Consumes: the snapshot schema `AiConversationConfirmResponse` and its three child schemas (Task A1). `asDouble` / `asDoubleOr0`, already in the file, for numeric fields the server may send as strings (the schema types `quantity`, `hoursWorked`, `kmTraveled` and `numberValue` as `["number","string"]` with a decimal pattern).
- Produces:
  - `class AiResolvedStaff { String userId; double? hoursWorked; double kmTraveled; String? vehicle; }`
  - `class AiResolvedMaterial { String? materialeId; String? freeTextName; double quantity; String? unitOfMeasure; String? notes; }`
  - `class AiResolvedControl { String ticketControlId; String? stringValue; bool? boolValue; DateTime? dateValue; double? numberValue; String? note; }`
  - `class AiConversationConfirmResponse { String title; String? details; bool materialiNotRequired; String? customerSignoffText; String? ticketId; String? cantiereId; String? locationId; List<AiResolvedStaff> staff; List<AiResolvedMaterial> materials; List<AiResolvedControl> controlli; List<String> warnings; }`
  - `Future<AiConversationConfirmResponse> AiApiClient.confirmConversation(String sessionId, {required String idempotencyKey})`
  - Consumed by Task B2's apply function and Task B4's screen.

**Why:** the class the app parses today, `AiConversationConfirmResult({reportId, replayed})`, describes a server that creates a report. After I2 the endpoint's response has no `reportId` and no `replayed`; every field it reads is absent from the wire, so `reportId` parses to `''` and `context.go(AppRoutes.rapportiniEditor(''))` is a route that matches nothing. The replacement is written field-by-field from `ConfirmResponseBuilder.Build`, which is the whole of the projection:

- `title` ← `plan.Title` (from `ReportHeaderDeriver`, which can return `string.Empty` when there is no ticket title, no `numero`, no cantiere name and no operator activity — Task B2 handles the empty case).
- `details` ← `plan.Details`
- `materialiNotRequired` ← `plan.MaterialiNotRequired` — the **corrected** value ("true only when the draft said so *and* no material survived resolution"), not the draft's raw flag, so do not recompute it from `AiCopilotDraftDto.materialiNotRequired`.
- `customerSignoffText` ← `state.CurrentDraft.CustomerSignoffText`
- `ticketId`, `cantiereId` ← the session's binding, echoed so the caller can seed the header.
- `locationId` ← normalised to **null** by `ConfirmResponseBuilder` when the resolution is `Guid.Empty`. Never a sentinel, never a fallback — Task B3.
- `staff` ← `AiResolvedStaff` per `plan.Staff`, deliberately narrower than the staff write model: no `costPerKm`, no `startTime`/`endTime`/`pauseMinutes`, because `ConfirmPlanBuilder` never sets them and a field that is always default is a contract a client will one day depend on and never receive.
- `materials` ← `AiResolvedMaterial` per `plan.Materials`; `notes` carries the `"Da verificare: materiale non trovato a catalogo."` marker on the free-text path.
- `controlli` ← `AiResolvedControl` per `plan.Observations`; the field name is `controlli` and the child is `AiResolvedControl`, not `observations`.
- `warnings` ← `plan.Warnings`, operator-facing, empty when everything resolved. This replaces the draft's per-item `AiResolutionState`, which does not exist on this response.

- [ ] **Step 1: Read the two shapes side by side before writing anything**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
sed -n '195,246p' lib/data/ai/ai_api_client.dart    # AiDraftMaterialUsage / AiDraftControlAnswer
sed -n '266,320p' lib/data/ai/ai_api_client.dart    # AiCopilotDraftDto
sed -n '322,350p' lib/data/ai/ai_api_client.dart    # the class being replaced
sed -n '430,470p' lib/data/ai/ai_api_client.dart    # the call
```

Note the two traps in the left column: `materialId` (draft) vs `materialeId` (resolved), `name` (draft) vs `freeTextName` (resolved), `state` (draft only) vs `dateValue`/`note` (resolved only). Do not reuse either draft class.

- [ ] **Step 2: Write the failing test first**

In `test/data/ai/ai_api_client_test.dart`, replace the existing `'confirmConversation sends the Idempotency-Key header'` body so it serves the **real** response shape and asserts the fields the app now depends on:

```dart
test('confirmConversation parses the resolved draft, not a created report', () async {
  RequestOptions? captured;
  final dio = Dio();
  dio.httpClientAdapter = _Adapter((options) async {
    captured = options;
    return ResponseBody.fromString(
      jsonEncode({
        'title': 'Sostituzione valvola',
        'details': 'Valvola bloccata',
        'materialiNotRequired': false,
        'customerSignoffText': 'accettato',
        'ticketId': '00000000-0000-0000-0000-000000000003',
        'cantiereId': null,
        'locationId': null,               // null is legal on a 200 and must stay null
        'staff': [
          {'userId': '00000000-0000-0000-0000-000000000008',
           'hoursWorked': '6.5', 'kmTraveled': '12', 'vehicle': 'Fiat Panda'},
        ],
        'materials': [
          {'materialeId': null, 'freeTextName': 'Guarnizione',
           'quantity': '2', 'unitOfMeasure': 'pz',
           'notes': 'Da verificare: materiale non trovato a catalogo.'},
        ],
        'controlli': [
          {'ticketControlId': '00000000-0000-0000-0000-000000000009',
           'stringValue': null, 'boolValue': true, 'dateValue': null,
           'numberValue': null, 'note': null},
        ],
        'warnings': ['Un controllo della checklist non è stato registrato.'],
      }),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  });
  final client = AiApiClient(dio);

  final r = await client.confirmConversation('sess-1', idempotencyKey: 'key-1');

  expect(r.title, 'Sostituzione valvola');
  expect(r.ticketId, '00000000-0000-0000-0000-000000000003');
  expect(r.locationId, isNull, reason: 'the wire says null; nothing may invent a value for it');
  expect(r.staff.single.hoursWorked, 6.5, reason: 'numbers may arrive as strings');
  expect(r.materials.single.materialeId, isNull);
  expect(r.materials.single.freeTextName, 'Guarnizione');
  expect(r.materials.single.notes, contains('Da verificare'));
  expect(r.controlli.single.ticketControlId, '00000000-0000-0000-0000-000000000009');
  expect(r.warnings, hasLength(1));
  expect(captured!.headers['Idempotency-Key'], 'key-1');
});
```

Add a second test that pins the trap in the direction that matters — the old field names must not parse into anything:

```dart
test('the draft shapes do not describe the confirm response', () async {
  // Same Dio + _Adapter harness as the test above (see _Adapter at the top of this file).
  final dio = Dio();
  dio.httpClientAdapter = _Adapter((options) async => ResponseBody.fromString(
        jsonEncode({
          'reportId': 'rpt-1', 'replayed': false, 'materiali': [], 'observations': [],
        }),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      ));
  final client = AiApiClient(dio);

  final r = await client.confirmConversation('sess-1', idempotencyKey: 'k');
  // The pre-I2 body parses without throwing — every field is simply absent.
  expect(r.title, isEmpty);
  expect(r.materials, isEmpty);
  expect(r.controlli, isEmpty);
});
```

The point of this one is that it does **not** throw: a missing field on a JSON DTO is silent, which is why the contract test in Step 4 exists.

- [ ] **Step 3: Replace the DTO and the call's return type**

```dart
/// One resolved technician line. Mirror of backend `AiResolvedStaff`.
///
/// Deliberately narrower than `SubmitReportStaffDto`: the server builds these from a plan that
/// never carries `costPerKm`, `startTime`, `endTime` or `pauseMinutes`, so those are left at their
/// column defaults rather than round-tripped as nulls.
class AiResolvedStaff {
  const AiResolvedStaff({
    required this.userId,
    this.hoursWorked,
    this.kmTraveled = 0,
    this.vehicle,
  });

  final String userId;
  final double? hoursWorked;
  final double kmTraveled;
  final String? vehicle;

  factory AiResolvedStaff.fromJson(Map<String, dynamic> json) => AiResolvedStaff(
    userId: json['userId'] as String? ?? '',
    hoursWorked: asDouble(json['hoursWorked']),
    kmTraveled: asDoubleOr0(json['kmTraveled']),
    vehicle: json['vehicle'] as String?,
  );
}

/// One resolved material line. Mirror of backend `AiResolvedMaterial`.
///
/// NOT `AiDraftMaterialUsage`: that reads `materialId` and `name`, this reads `materialeId` and
/// `freeTextName`. Exactly one of [materialeId] / [freeTextName] is meaningful — a catalogue id, or
/// a name the operator dictated that no catalogue lookup matched. [notes] carries the
/// "Da verificare" marker on the free-text path, which is the server telling the technician, on the
/// row itself, that the line needs checking.
class AiResolvedMaterial {
  const AiResolvedMaterial({
    this.materialeId,
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.notes,
  });

  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final String? notes;

  factory AiResolvedMaterial.fromJson(Map<String, dynamic> json) => AiResolvedMaterial(
    materialeId: json['materialeId'] as String?,
    freeTextName: json['freeTextName'] as String?,
    quantity: asDoubleOr0(json['quantity']),
    unitOfMeasure: json['unitOfMeasure'] as String?,
    notes: json['notes'] as String?,
  );
}

/// One resolved checklist answer. Mirror of backend `AiResolvedControl`.
///
/// [ticketControlId] is the **TicketControl** — this job's copy of a checklist item — not the
/// template control it came from. The server validates ownership on submit, so a mismatched id
/// fails the whole submission rather than quietly recording nothing.
class AiResolvedControl {
  const AiResolvedControl({
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.dateValue,
    this.numberValue,
    this.note,
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;
  final String? note;

  factory AiResolvedControl.fromJson(Map<String, dynamic> json) => AiResolvedControl(
    ticketControlId: json['ticketControlId'] as String? ?? '',
    stringValue: json['stringValue'] as String?,
    boolValue: json['boolValue'] as bool?,
    dateValue: json['dateValue'] != null
        ? DateTime.tryParse(json['dateValue'] as String)
        : null,
    numberValue: asDouble(json['numberValue']),
    note: json['note'] as String?,
  );
}

/// What `POST /api/ai/conversations/{id}/confirm` returns: the draft resolved against real tenant
/// data, and nothing written (spec §5.4). Mirror of backend `AiConversationConfirmResponse`.
///
/// It is NOT a created report: there is no `reportId` and no `replayed`, because confirming twice
/// returns the same draft. The client owns the write that follows, and owns [materialiNotRequired]
/// and the provenance flag (`isAiAssisted`), which the response deliberately does not carry.
///
/// [locationId] may be null: the server normalises its own `Guid.Empty` "never resolved" sentinel
/// to null rather than hand back an id nothing downstream would reject. Never substitute a value
/// for it — see the submit path's nullable handling in the editor screen.
///
/// [warnings] is operator-facing and empty when everything resolved; it replaces the per-item
/// `AiResolutionState` the draft summary uses, because resolution is what produced this response.
class AiConversationConfirmResponse {
  const AiConversationConfirmResponse({
    required this.title,
    this.details,
    this.materialiNotRequired = false,
    this.customerSignoffText,
    this.ticketId,
    this.cantiereId,
    this.locationId,
    this.staff = const [],
    this.materials = const [],
    this.controlli = const [],
    this.warnings = const [],
  });

  final String title;
  final String? details;
  final bool materialiNotRequired;
  final String? customerSignoffText;
  final String? ticketId;
  final String? cantiereId;
  final String? locationId;
  final List<AiResolvedStaff> staff;
  final List<AiResolvedMaterial> materials;
  final List<AiResolvedControl> controlli;
  final List<String> warnings;

  factory AiConversationConfirmResponse.fromJson(Map<String, dynamic> json) =>
      AiConversationConfirmResponse(
        title: json['title'] as String? ?? '',
        details: json['details'] as String?,
        materialiNotRequired: json['materialiNotRequired'] as bool? ?? false,
        customerSignoffText: json['customerSignoffText'] as String?,
        ticketId: json['ticketId'] as String?,
        cantiereId: json['cantiereId'] as String?,
        locationId: json['locationId'] as String?,
        staff: ((json['staff'] as List<dynamic>?) ?? [])
            .map((s) => AiResolvedStaff.fromJson(s as Map<String, dynamic>))
            .toList(),
        materials: ((json['materials'] as List<dynamic>?) ?? [])
            .map((m) => AiResolvedMaterial.fromJson(m as Map<String, dynamic>))
            .toList(),
        controlli: ((json['controlli'] as List<dynamic>?) ?? [])
            .map((c) => AiResolvedControl.fromJson(c as Map<String, dynamic>))
            .toList(),
        warnings: ((json['warnings'] as List<dynamic>?) ?? [])
            .map((w) => w.toString())
            .toList(),
      );
}
```

Delete `class AiConversationConfirmResult` outright — nothing else references it except the copilot screen (Task B4) and the widget test's fake (also Task B4). Update `confirmConversation`'s signature and its `AiConversationConfirmResult.fromJson(data)` to `AiConversationConfirmResponse.fromJson(data)`. Leave the `Idempotency-Key` header exactly as it is: `AiConversationsController.Confirm(Guid id, CancellationToken)` takes no header parameter, so the server ignores it — which is harmless, and `request_body_contract_test.dart`'s `unguarded` map already documents that the request carries nothing else. Do not "clean up" a call the contract tests describe.

- [ ] **Step 4: Put the confirm response behind the inbound gate**

A DTO that parses is not a DTO that matches. Add the four new shapes to `test/contract/sync_inbound_contract_test.dart`'s `readKeys` map, which compares a DTO's declared read keys with the snapshot's properties **in both directions**:

```dart
  final readKeys = <String, Set<String>>{
    // ... existing entries ...
    // The I2 confirm response. The draft and resolved shapes are different DTOs, so these are
    // pinned here rather than inferred from the draft summary's classes.
    'AiConversationConfirmResponse': AiConversationConfirmResponse.wireKeys,
    'AiResolvedStaff': AiResolvedStaff.wireKeys,
    'AiResolvedMaterial': AiResolvedMaterial.wireKeys,
    'AiResolvedControl': AiResolvedControl.wireKeys,
  };
```

`wireKeys` does not exist on these yet: add a `static const Set<String> wireKeys = {...}` to each, listing exactly the keys its `fromJson` reads, in the same style as the existing sync DTOs. This is the test that would have caught the original `controlId`/`ticketControlId` break on the inbound side, and it is the reason the rename in this task cannot be invisible: a server-side rename of `materialeId` compiles, analyzes clean, and fails here by name.

Also add the inverse assertion the brief's two field-name traps deserve, so they are pinned rather than remembered:

```dart
test('the confirm response uses the array names the server declares', () {
  final declared = props('AiConversationConfirmResponse');
  expect(declared, containsAll(['materials', 'controlli']));
  expect(declared, isNot(contains('materiali')));
  expect(declared, isNot(contains('observations')));
  expect(
    declared,
    isNot(contains('isAiAssisted')),
    reason: 'the client owns provenance; a server field that is always absent is a trap',
  );
});
```

- [ ] **Step 5: Run the two files, in the foreground**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
timeout 900 flutter test test/data/ai/ai_api_client_test.dart test/contract/
```

Both must pass. `test/features/rapportino/ai_copilot_screen_test.dart` will **not** compile yet — its fake implements the deleted type — and that is expected until Task B4; do not "fix" it here by widening the fake's return type.

- [ ] **Step 6: Commit**

```bash
git add lib/data/ai/ai_api_client.dart test/data/ai/ai_api_client_test.dart \
        test/contract/sync_inbound_contract_test.dart
git commit -m "feat(ai): parse the confirm response the endpoint actually returns

Confirm resolves, it does not create (spec §5.4). The response has no reportId and no
replayed; it has a resolved draft — materials and controlli, not materiali and
observations — and a warnings list. The old class read every one of those fields as
absent, so reportId parsed to '' and the editor route matched nothing.

The resolved shapes are separate DTOs from the draft summary's: materialeId/freeTextName
against materialId/name. Reusing the draft classes compiles and yields an empty list.
Both are now pinned against the snapshot by the inbound contract gate, which compares in
both directions and so cannot be satisfied by a DTO that reads nothing.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B2: applying a confirm response to the editor's own draft

**Files:**
- Create: `lib/features/rapportino/apply_confirmed_draft.dart`
- Test: `test/features/rapportino/apply_confirmed_draft_test.dart`

**Interfaces:**
- Consumes: `createLocalDraft(ref, title:, locationId:, ticketId:, cantiereId:, ...)` (`create_draft.dart`), `DraftReportRepository` (`upsertStaff`, `upsertMateriale`, `upsertControlli`, `saveDraft`), `controlRowId(reportId, ticketControlId)` (`import_server_report.dart`), and the Task B1 DTOs.
- Produces:
  - `Future<String?> applyConfirmedDraft(WidgetRef ref, {required AiConversationConfirmResponse response, String? ticketId, String? cantiereId})` — returns the new local report id, or `null` when creation is refused (no signed-in internal user id, same refusal as `createLocalDraft`). There is no `fallbackTitle` parameter: an empty title is a legitimate outcome (see below), so a caller-supplied substitute would be the invention this function exists to avoid.
  - Consumed by Task B4 (the screen). Nothing else calls it.

**Why:** this is the whole of "mobile applies the draft". It is modelled on the two functions that already do exactly this job — `createLocalDraft` (a header, nothing else) and `createReworkDraft` (a header plus a loop over staff/materiali/controlli) — and it adds no new abstraction because those two already establish the shape, the companions and the refusal semantics. Four details are load-bearing:

- **The row id for a control answer is `controlRowId(reportId, ticketControlId)`**, the same `'ctrl-$reportId-$ticketControlId'` the Controlli step's `_rowId` produces. Any other scheme makes the technician's next tap on that control insert a *second* row for the same `TicketControl`, because `ReportEditorNotifier.upsertControllo` looks rows up by `id` — and the server then sees two answers for one control.
- **The title can be empty.** `ReportHeaderDeriver` returns `string.Empty` when there is no ticket title, no ticket `numero`, no cantiere name, no cantiere `numero` and no operator activity — reachable for a session where the technician only answered the checklist. `validateDraft` requires a non-empty title, so the correct outcome is a draft the editor opens on with an empty Titolo the technician fills in, not an invented string.
- **`details` is what the operator said**, verbatim, from the resolved activities. It is the report's body; do not summarise it into the title.
- **The provenance flag is written here, in this function's own `saveDraft`, and never through `ReportEditorNotifier.markAiAssisted()`.** That method autosaves the whole header from `state`, and `state` for a just-constructed `autoDispose` provider is a blank placeholder because `_hydrate()` is asynchronous — calling it here would flush blanks over everything written above. Writing `isAiAssisted: Value(true)` into the same companion as the data makes the flag and the draft it describes land together, and keeps `reportEditorProvider` entirely out of the apply path.

- [ ] **Step 1: Read the two precedents and the row-id helper**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
sed -n '48,124p' lib/features/rapportino/create_draft.dart    # createLocalDraft
sed -n '159,260p' lib/features/rapportino/create_draft.dart   # createReworkDraft — the loop shape
sed -n '41,46p'  lib/data/reports/import_server_report.dart   # controlRowId, at :42
sed -n '881,890p' lib/presentation/providers/report_editor_providers.dart  # markAiAssisted — do NOT call this
sed -n '1126,1152p' lib/presentation/providers/report_editor_providers.dart # _buildHeaderCompanion — why not
sed -n '504,530p' lib/presentation/providers/report_editor_providers.dart   # ready = _hydrate() — why not
grep -n "_hydrateBody\|_controlloToCompanion" lib/presentation/providers/report_editor_providers.dart
```

`_hydrateBody` reads staff/materiali/controlli straight from Drift, and `reportEditorProvider` is `autoDispose` — so a **later** screen that mounts the editor hydrates from what this function wrote, and the apply path is a data write rather than a screen API. That is *not* the same claim as "nothing needs to be pushed into a live notifier, so touching one is free": constructing the notifier and calling a setter on it before `_hydrate()` resolves is precisely what corrupts the row (the `markAiAssisted` constraint (Global Constraints, sixth bullet)). Do not construct it here at all.

- [ ] **Step 2: Write the failing test first**

`applyConfirmedDraft` takes a `WidgetRef`, so the test needs a **real** one. There is no `_widgetRefStub` and no `_seedInternalUser`: `create_draft_test.dart` obtains its ref by pumping `UncontrolledProviderScope` + `Consumer` and calling the function from a button callback (`_callCreateLocalDraft` at `:117`, overrides including `internalUserIdProvider.overrideWith((ref) async => _testInternalUserId)` at `:237`). Copy that shape — it is the only harness in the repo that produces a genuine `WidgetRef`, and a hand-rolled fake would not exercise the provider reads that matter.

```dart
// test/features/rapportino/apply_confirmed_draft_test.dart
//
// Harness mirrored from create_draft_test.dart: a ProviderContainer whose internalUserIdProvider
// resolves to a fixed id, pumped through UncontrolledProviderScope + Consumer so the function under
// test receives a real WidgetRef from a real widget callback.
Future<String?> _callApply(
  WidgetTester tester,
  ProviderContainer container,
  AiConversationConfirmResponse response,
) async {
  String? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () async {
              result = await applyConfirmedDraft(
                ref,
                response: response,
                ticketId: 'tkt-1',
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('writes the resolved draft as the phone\'s own local rapportino', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      internalUserIdProvider.overrideWith((ref) async => 'internal-guid-2'),
    ]);
    addTearDown(container.dispose);

    final id = await _callApply(
      tester,
      container,
      const AiConversationConfirmResponse(
        title: 'Sostituzione valvola',
        details: 'Valvola bloccata',
        ticketId: 'tkt-1',
        locationId: null,
        staff: [AiResolvedStaff(userId: 'u-1', hoursWorked: 6.5, kmTraveled: 12)],
        materials: [AiResolvedMaterial(freeTextName: 'Guarnizione', quantity: 2,
                                       notes: 'Da verificare: materiale non trovato a catalogo.')],
        controlli: [AiResolvedControl(ticketControlId: 'tc-1', boolValue: true)],
      ),
    );

    expect(id, isNotNull);
    final row = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();
    expect(row.title, 'Sostituzione valvola');
    expect(row.ticketId, 'tkt-1');
    expect(row.locationId, '', reason: 'a null location stays empty — never a sentinel');
    expect(row.stato, 'Bozza');
    expect(row.isLocalOnly, isTrue, reason: 'it is the phone\'s draft until the queue sends it');
    expect(row.isAiAssisted, isTrue,
        reason: 'provenance lands in this same write; nothing else sets it on this path');

    final staff = await db.select(db.reportStaffTable).get();
    expect(staff.single.userId, 'u-1');
    expect(staff.single.hoursWorked, 6.5);

    final mat = await db.select(db.reportMateriali).getSingle();
    expect(mat.freeTextName, 'Guarnizione');
    expect(mat.quantity, 2);
    expect(mat.magazzinoId, isNull, reason: 'nothing resolved a magazzino — no stock leaves by itself');

    final ctrl = await db.select(db.reportControlli).getSingle();
    expect(ctrl.controlId, 'tc-1');
    expect(ctrl.boolValue, isTrue);
    expect(ctrl.id, controlRowId(id!, 'tc-1'),
        reason: 'the Controlli step looks rows up by this id; any other scheme inserts a second row');
  });

  testWidgets('the header this writes survives a later editor mount unharmed', (tester) async {
    // The regression this guards: mount reportEditorProvider(localId) AFTER applyConfirmedDraft
    // and await its `ready`, then assert title/ticketId/locationId are still the applied values.
    // If someone reintroduces a notifier call before hydration, this fails with blanks.
  });

  testWidgets('a response with no title leaves one for the technician rather than inventing one',
      (tester) async {
    // AiConversationConfirmResponse(title: '') — reachable via ReportHeaderDeriver's last branch.
    // Expect the draft to be written with an empty title and no substitute text.
  });
}
```

- [ ] **Step 3: Write the function**

```dart
// lib/features/rapportino/apply_confirmed_draft.dart

/// Applies a confirmed AI draft to the phone's own rapportino.
///
/// This is the mobile half of spec §5.5: the server resolves the draft against real tenant data
/// and persists nothing (§5.4), so the write belongs here, into the same Drift draft the wizard
/// fills by hand. Everything after this — review, signatures, the queue, the submit — is the path
/// that already exists, unchanged. The only network call this rapportino will ever make is the
/// submit, and it is atomic and idempotent by key.
///
/// Models `createReworkDraft`: a header, then one loop per child table. No new abstraction, because
/// the two functions that already do this (`createLocalDraft`, `createReworkDraft`) established the
/// companions, the ordering and the refusal semantics.
///
/// Returns the new local report id, or null when the device cannot attribute a draft to anybody
/// (no signed-in internal user id) — the same refusal `createLocalDraft` makes, for the same reason.
///
/// What the response does NOT carry and this function therefore does not write: any signature, and
/// any location fallback. A null `locationId` is written as an empty string, which reads as
/// "unknown" and is what the editor's own validation is being taught to reject at submit time.
///
/// The one thing the response does not carry that this function DOES write is provenance —
/// `isAiAssisted`, in the final `saveDraft` below, in the same companion as the data. It must not be
/// left to `ReportEditorNotifier.markAiAssisted()`: that setter autosaves the whole header from
/// `state`, and a just-constructed `reportEditorProvider` still holds the blank placeholder while
/// `_hydrate()` resolves, so calling it here would overwrite everything this function just wrote.
Future<String?> applyConfirmedDraft(
  WidgetRef ref, {
  required AiConversationConfirmResponse response,
  String? ticketId,
  String? cantiereId,
}) async {
  final id = await createLocalDraft(
    ref,
    title: response.title,
    locationId: response.locationId ?? '',
    ticketId: response.ticketId ?? ticketId,
    cantiereId: response.cantiereId ?? cantiereId,
  );
  if (id == null) return null;

  final repo = ref.read(draftReportRepositoryProvider);
  final draft = await repo.getDraft(id);
  if (draft == null) return null;
  final tenantId = draft.tenantId;
  final now = DateTime.now().toUtc();

  for (final s in response.staff) {
    await repo.upsertStaff(ReportStaffTableCompanion.insert(
      id: const Uuid().v4(),
      tenantId: tenantId,
      createdAt: now,
      reportId: id,
      userId: s.userId,
      hoursWorked: Value(s.hoursWorked),
      kmTraveled: Value(s.kmTraveled),
      vehicle: Value(s.vehicle),
    ));
  }

  for (final m in response.materials) {
    // The free-text path's "Da verificare" marker rides in `notes` and is shown on the row:
    // the technician has to see that a line was dictated rather than looked up.
    await repo.upsertMateriale(ReportMaterialiCompanion.insert(
      id: const Uuid().v4(),
      tenantId: tenantId,
      createdAt: now,
      reportId: id,
      materialeId: Value(m.materialeId),
      freeTextName: Value(m.freeTextName),
      quantity: m.quantity,
      unitOfMeasure: Value(m.unitOfMeasure),
      notes: Value(m.notes),
      // magazzinoId intentionally absent: nothing resolved a warehouse, and a magazzino is what
      // turns a material line into a stock scarico. Guessing one would move stock nobody asked for.
    ));
  }

  if (response.controlli.isNotEmpty) {
    await repo.upsertControlli([
      for (final c in response.controlli)
        ReportControlliCompanion.insert(
          // The Controlli step's own row id, so its next edit UPDATES this row instead of
          // inserting a second answer for the same TicketControl.
          id: controlRowId(id, c.ticketControlId),
          tenantId: tenantId,
          createdAt: now,
          reportId: id,
          controlId: c.ticketControlId,
          stringValue: Value(c.stringValue),
          boolValue: Value(c.boolValue),
          dateValue: Value(c.dateValue),
          numberValue: Value(c.numberValue),
          note: Value(c.note),
        ),
    ]);
  }

  // materialiNotRequired and customerSignoffText are header fields the confirm response corrects
  // for us; carry them or the editor shows a report that contradicts what the server resolved.
  //
  // isAiAssisted rides here rather than through ReportEditorNotifier.markAiAssisted(): that setter
  // autosaves the entire header from `state`, and a provider constructed this instant still holds
  // the blank placeholder until its async _hydrate() resolves, so it would write blanks over
  // everything above. Same companion as the data, no notifier, no race.
  await repo.saveDraft(DraftReportsCompanion(
    id: Value(id),
    materialiNotRequired: Value(response.materialiNotRequired),
    customerSignoffText: Value(response.customerSignoffText),
    details: Value(response.details),
    isAiAssisted: const Value(true),
    updatedAt: Value(now),
  ));

  return id;
}
```

- [ ] **Step 4: Run it, in the foreground**

```bash
timeout 900 flutter test test/features/rapportino/apply_confirmed_draft_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/rapportino/apply_confirmed_draft.dart \
        test/features/rapportino/apply_confirmed_draft_test.dart
git commit -m "feat(rapportino): apply a confirmed AI draft to the phone's own rapportino

Spec §5.5: mobile applies the returned draft to its own model and reuses the existing
save/submit path. Modelled on createReworkDraft — header, then a loop per child table —
because that function already establishes the companions and the refusal semantics.

Provenance is written here, in the same companion as the draft, deliberately NOT through
ReportEditorNotifier.markAiAssisted(): that setter autosaves the whole header from `state`,
and a just-constructed autoDispose provider still holds the blank placeholder while its
async _hydrate() resolves — calling it would silently blank the row this function just
wrote, which is the failure the notifier's own comment records having already happened once.

The control rows use the Controlli step's own controlRowId, so its next edit updates the
applied answer rather than inserting a second one for the same TicketControl.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B3: the location the apply path must not leave at its default

**Files:**
- Modify: `lib/domain/reports/draft_validation.dart` (`DraftValidationIssue`, `DraftValidationResult.italianMessages`, `validateDraft`)
- Test: `test/domain/reports/draft_validation_test.dart` (the helper gains a `locationId` parameter)

**Interfaces:**
- Consumes: `validateDraft({draft, staffCount, materialiCount, customerFreeText})` returning a `DraftValidationResult`.
- Produces: a new enum member `DraftValidationIssue.missingLocation` and its Italian string; `validateDraft` appends it for a blank `locationId`. `validateDraft`'s signature is unchanged.
- **Does not touch `report_editor_providers.dart`.** Provenance is written by `applyConfirmedDraft` (Task B2); `markAiAssisted` is not called on this path at all, and its doc comment is left as it is.

**Why:** the confirm response deliberately leaves the location to the client, and the resulting failure mode is invisible on the phone and only appears at the server. `AiConversationConfirmResponse.locationId` is `["null","string"]` and the server goes out of its way to normalise `Guid.Empty` to null rather than let a sentinel reach a client ("a client that persisted it would pin a report to with nothing downstream to reject it"). But `DraftReports.locationId` is non-nullable text defaulting to `''`, and `validateDraft` today checks the title, the customer, the staff, the materials and the signatures — **not** the location. So a draft resolved with no location passes client validation, gets submitted, and `SubmitReportService` rejects it at `EnsureExistsAsync<Location>(request.LocationId, ct)`. The technician sees a failure about a field the form never asked them for. Verified: `validateDraft` has no location check, and `SubmitReportRequest.LocationId` is a non-nullable `Guid` (`src/TaskTapAPI.Application/Services/Reports/Submit/SubmitReportRequest.cs:23`).

The provenance half of this task is gone, and moved into Task B2 rather than deferred: `applyConfirmedDraft` now writes `isAiAssisted: Value(true)` in its own `saveDraft`, so the flag lands with the draft in one write and no notifier is involved. That is the only correct place for it — see the `markAiAssisted` constraint (Global Constraints, sixth bullet) for what calling `markAiAssisted()` in its place actually does.

- [ ] **Step 1: Read the validator, its callers, and the test helper**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cat lib/domain/reports/draft_validation.dart
grep -rn "validateDraft(" lib/ test/
sed -n '24,52p' test/domain/reports/draft_validation_test.dart   # the _insertDraft helper
```

Note how the existing checks fail: `if (title.isEmpty) { issues.add(DraftValidationIssue.missingTitle); }` — they **append to `issues` and continue**, they do not return, and `DraftValidationResult` exposes only `issues`, `isValid`, `isReadyToSubmit` and `italianMessages`. There is no `field`, and `italianMessages` is a flat index-aligned list with no per-field association. So the new check is a new enum member, not a new result shape.

Every fixture in `draft_validation_test.dart` goes through `_insertDraft` (`:24`), which hardcodes `locationId: 'loc-1'` (`:46`) with no parameter for it. Extend the helper with `String locationId = 'loc-1'` rather than hand-building a draft in the new test — and note that because the default is already a real location, this check **cannot** break any existing test in the file; the only fixtures it affects are ones that opt in.

- [ ] **Step 2: Write the failing test**

First extend the helper's signature and pass it through:

```dart
Future<DraftReport> _insertDraft(
  AppDatabase db, {
  String id = 'r-1',
  String title = 'Test rapportino',
  String locationId = 'loc-1',   // new; every existing caller keeps the old behaviour
  // ... unchanged ...
}) async {
```

Then the test:

```dart
test('a draft with no location is rejected', () async {
  final db = _makeDb();
  addTearDown(db.close);
  final draft = await _insertDraft(db, locationId: '');   // as applyConfirmedDraft writes a null one

  final result = validateDraft(
    draft: draft,
    staffCount: 1,
    materialiCount: 1,
    customerFreeText: '',
  );

  expect(result.isValid, isFalse);
  expect(result.issues, contains(DraftValidationIssue.missingLocation));
  expect(
    result.italianMessages,
    contains('Sede non specificata'),
    reason: 'the Riepilogo step renders italianMessages verbatim; a missing string here is a '
        'blank line in front of the technician',
  );
});
```

A second test pins that it is additive rather than exclusive, matching how the other checks behave:

```dart
test('a blank location does not hide the other problems', () async {
  // locationId: '' AND title: '' AND staffCount: 0 — expect all three issues, not just the first.
});
```

- [ ] **Step 3: Add the issue and the check**

Three edits in `lib/domain/reports/draft_validation.dart`, following the existing pattern exactly:

```dart
enum DraftValidationIssue {
  missingTitle,
  missingLocation,   // new
  missingCustomer,
  // ... unchanged ...
}
```

```dart
        case DraftValidationIssue.missingLocation:
          return 'Sede non specificata';
```

```dart
  // The location is required by `SubmitReportRequest.LocationId` (a non-nullable Guid) and the
  // server rejects an unknown one at `EnsureExistsAsync<Location>`. `AiConversationConfirmResponse
  // .locationId` is explicitly nullable — "best-effort and may be null when nothing resolved" — and
  // a cantiere-bound session can resolve to a tenant-default location unrelated to that cantiere.
  // So the phone must say "this needs a location" before the technician signs and sends, instead of
  // letting the server answer with a field the form never asked for.
  if (draft.locationId.trim().isEmpty) {
    issues.add(DraftValidationIssue.missingLocation);
  }
```

- [ ] **Step 4: Run, in the foreground**

```bash
timeout 900 flutter test test/domain/reports/
```

- [ ] **Step 5: Commit**

```bash
git add lib/domain/reports/draft_validation.dart \
        test/domain/reports/draft_validation_test.dart
git commit -m "fix(rapportino): require a location before submit

The confirm response's locationId is nullable by contract, the Drift column defaults to
'', and validateDraft never checked it — so an AI-resolved draft with no location passed
every client check and was rejected server-side by EnsureExistsAsync<Location>, on a field
the form never asked for.

The issue is additive, like every other check in this function: it appends and continues,
so a blank location cannot mask a missing title or an empty team.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B4: the copilot stops importing; the session is released after the draft is persisted

**Files:**
- Modify: `lib/features/rapportino/ai_copilot_screen.dart` (`_confirm`, `_importAndOpen`, `_abandon`, the button block, and the copy)
- Test: `test/features/rapportino/ai_copilot_screen_test.dart` (the fake, and four widget tests built on the import path)
- Modify: `lib/features/rapportino/import_server_report_action.dart` (doc comment only — the function keeps its other caller)

**Interfaces:**
- Consumes: `applyConfirmedDraft` (B2, which also writes the provenance flag), `validateDraft` (B3), `AiConversationConfirmResponse` (B1), `abandonConversation` (unchanged).
- Produces: no new API. `importServerReportForEditing` keeps its signature and its consumer at `rapportini_list_screen.dart:362`.
- **Does not touch** `lib/data/sync/submission_queue.dart`, `lib/data/reports/import_server_report.dart`, or `report_editor_providers.dart`.
- **Does not call `markAiAssisted`.** Provenance is B2's write; see the `markAiAssisted` constraint (Global Constraints, sixth bullet).

**Why:** this is where the cut-over becomes visible to a technician, and where the copy has to be honest about what changed. Two things happen in `_confirm` after this task: the response is applied to a local draft, and the report is opened in the editor. Nothing is created on the server, so:

- **`_confirmedReportId`, `_importAndOpen`, `_importError` and `_importNotEditable` all disappear**, and with them the "Riprova" branch of the button block and the `ServerReportNotEditableException` handling. There is no server object to fail to download and no server state that can move on underneath the technician. If the apply fails (only reachable when there is no signed-in internal user id), the screen stays on the conversation and the same Conferma button retries — one state, not two.
- **The server session is released only after the draft is on the phone**, per the controller's own rule: "The session is released by `Abandon` instead, once the caller has actually persisted the draft." Then set `_sessionId = null` so the `dispose`/back path does not fire a second `abandonConversation` for an id the server has already forgotten — the call is best-effort and swallows a 404, but a redundant DELETE that *should* fail is a bad thing to leave in a path whose whole point is that failures are meaningful.
- **The copy changes**, because the old copy becomes false in the direction that matters. The button reads "Conferma e crea rapportino" and the toast says "Rapportino creato" — both described a server report. After this change the technician gets a **local Bozza**, not yet sent: exactly the state the Rapportini list already renders for an unsent draft, with the queue's own "Riprova"/pending affordance. The button becomes **"Conferma e apri il rapportino"** and the success toast goes away entirely (navigating to the editor is the feedback; a toast that says "creato" would be the one place in the app where a rapportino looks filed and is not — see Review Focus 4). **The label is load-bearing for the tests**: `'Conferma e crea rapportino'` is asserted or tapped at `ai_copilot_screen_test.dart:233`, `:254` and in the shared `confirmFlow` helper at `:265`, which is itself called from `:287`, `:334`, `:353` and `:384`. Change the label in the screen and update all four call sites in the same commit, or the suite fails on a `findsNothing` that looks like the button vanished rather than like a copy edit.

- [ ] **Step 1: Read the screen's confirm path and the four tests that pin it**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
sed -n '177,252p' lib/features/rapportino/ai_copilot_screen.dart   # _confirm / _importAndOpen / _abandon
sed -n '336,360p' lib/features/rapportino/ai_copilot_screen.dart   # the button block
sed -n '30,100p'  test/features/rapportino/ai_copilot_screen_test.dart  # the fake + _FakeServerReportApi
sed -n '274,400p' test/features/rapportino/ai_copilot_screen_test.dart  # the four confirm tests
```

The four tests and what happens to each:

| Test | Fate |
|---|---|
| `Confirm imports the server report into Drift before opening the editor` | Rewritten: applies the response's own values, asserts Drift contents, asserts the editor route carries the **local** id |
| `a cantiere-bound copilot keeps its cantiereId on the imported report` | Rewritten for the applied draft; still asserts `cantiereId` is carried |
| `a failed import keeps the session, shows an error and does NOT open the editor` | Replaced: there is no import to fail. New test — a confirm that throws leaves the conversation, the technician's words and the session intact |
| `a report no longer Bozza shows the not-editable message with Chiudi, no retry loop` | Deleted: the state cannot occur. Replaced by the null-location case (below) |

- [ ] **Step 2: Rewrite the fake, and delete what is now unused**

In `_FakeAiApiClient`: `AiConversationConfirmResult? confirmResult` → `AiConversationConfirmResponse? confirmResult`, the `confirmConversation` override's return type likewise, and the default becomes a realistic response rather than `reportId: 'rpt-1'`. Record whether `abandonConversation` was called (`final abandoned = <String>[];`) so the release-after-persist order is assertable.

`_FakeServerReportApi` and the `import '../../data/reports/server_report_dto_test.dart' show backendFixture;` that feeds it become unreachable once no test imports a server report. Delete both — an unused import is an `analyze` failure on this repo's CI, so leaving them is not a neutral choice. Check `grep -n "serverApi\|_FakeServerReportApi\|serverReportApiClientProvider" test/features/rapportino/ai_copilot_screen_test.dart` afterwards and remove the provider override from `_wrap` too. **`import_server_report_action.dart` itself stays** — it is still the list screen's path.

- [ ] **Step 3: Replace `_confirm` and delete `_importAndOpen`**

```dart
  Future<void> _confirm() async {
    final sessionId = _sessionId;
    if (sessionId == null || _confirming) return;

    _confirmKey ??= const Uuid().v4();
    setState(() => _confirming = true);

    try {
      final response = await ref
          .read(aiApiClientProvider)
          .confirmConversation(sessionId, idempotencyKey: _confirmKey!);
      if (!mounted) return;

      // Spec §5.5: mobile applies the resolved draft to its own report and then uses the existing
      // save/submit path. Nothing is created server-side — Confirm resolves, it does not create
      // (§5.4) — so there is no server object to download, no import to retry, and no state that
      // can move on underneath us between the two calls.
      final localId = await applyConfirmedDraft(
        ref,
        response: response,
        ticketId: widget.ticketId,
        cantiereId: widget.cantiereId,
      );
      if (!mounted) return;

      if (localId == null) {
        // The same refusal createLocalDraft makes: no signed-in internal user id, so there is
        // nobody to attribute a rapportino to. Retrying the same button is the whole recovery.
        setState(() => _confirming = false);
        showAppToast(
          context,
          message: 'Non riesco a creare il rapportino su questo telefono. Riprova.',
          tone: ToastTone.error,
        );
        return;
      }

      // The draft is in Drift, provenance included — applyConfirmedDraft wrote isAiAssisted in the
      // same companion. The session has now done its job and is released (the controller's own
      // rule). Clearing _sessionId first keeps dispose()/_abandon from firing a second DELETE at an
      // id the server has already forgotten.
      //
      // Do NOT call reportEditorProvider(localId).notifier.markAiAssisted() here. That provider has
      // just been constructed, its `state` is still the blank placeholder, and _hydrate() has not
      // resolved — its autosave would write blanks over everything applyConfirmedDraft just saved.
      // the `markAiAssisted` constraint (Global Constraints, sixth bullet); the flag is already set.
      _sessionId = null;
      unawaited(ref.read(aiApiClientProvider).abandonConversation(sessionId));

      if (!mounted) return;
      context.go(AppRoutes.rapportiniEditor(localId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        // A stale-version 409 means the draft moved on since this key was minted — the next
        // attempt must not replay it.
        if (e is AiConversationException && e.isStaleVersionConflict) _confirmKey = null;
      });
      showAppToast(context, message: e.toString(), tone: ToastTone.error);
    }
  }
```

Then: delete `_importAndOpen`, `_confirmedReportId`, `_importError`, `_importNotEditable`; drop `_confirmedReportId != null` from `_send`'s guard (line 147) and from the button block (line 344), leaving the single Conferma button; change its label to `'Conferma e apri il rapportino'` and its busy label from `'Creazione…'` to `'Preparo il rapportino…'`; drop the `Rapportino creato` toast. Add a `warnings` surface: `response.warnings` is operator-facing and non-empty when something did not resolve, and it belongs on screen before the technician leaves the conversation — a single `showAppToast(context, message: response.warnings.join('\n'), tone: ToastTone.warning)` when it is non-empty is enough, and it is the only place those sentences are visible.

Leave the `Idempotency-Key` on the call and leave `isStaleVersionConflict`'s handling alone.

- [ ] **Step 4: Rewrite the four tests**

The rewritten happy-path test must assert the properties the plan exists for:

```dart
  testWidgets('Confirm applies the resolved draft to a local rapportino and opens it', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final client = _FakeAiApiClient(
      turnResult: emptyDraft,
      confirmResult: const AiConversationConfirmResponse(
        title: 'Pompa bloccata',
        details: 'Sostituita pompa; verificata tenuta',
        ticketId: 'tkt-1',
        locationId: null,
        staff: [AiResolvedStaff(userId: 'u-1', hoursWorked: 6.5, kmTraveled: 12)],
        materials: [
          AiResolvedMaterial(freeTextName: 'Guarnizione', quantity: 2,
                             notes: 'Da verificare: materiale non trovato a catalogo.'),
        ],
        controlli: [AiResolvedControl(ticketControlId: 'tc-1', boolValue: true)],
      ),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1', db: db));
    await tester.pumpAndSettle();
    await confirmFlow(tester);

    // The editor opened on a LOCAL id, not a server one — nothing was created server-side.
    final row = await db.select(db.draftReports).getSingle();
    expect(find.text('editor:${row.id}'), findsOneWidget);
    expect(row.isLocalOnly, isTrue);
    expect(row.stato, 'Bozza');
    expect(row.isAiAssisted, isTrue, reason: 'provenance is the client\'s to set');
    expect(row.locationId, '', reason: 'the null location stayed empty and is the editor\'s to fill');
    expect(find.text('Sostituita pompa; verificata tenuta'), findsOneWidget);
    expect(find.text('Pompa bloccata'), findsOneWidget);
    expect(await db.select(db.reportStaffTable).get(), hasLength(1));
    expect(await db.select(db.reportMateriali).get(), hasLength(1));
    expect(await db.select(db.reportControlli).get(), hasLength(1));
    expect(client.abandoned, ['sess-1'], reason: 'the session is released after the draft is persisted');
    await _unmount(tester);
  });
```

And add the one that replaces the deleted non-editable test — the failure the apply path actually has:

```dart
  testWidgets('a resolved draft with no location opens the editor with a field to fix', (tester) async {
    // locationId: null. The draft is written; the editor opens; the Riepilogo step refuses to
    // submit until a location is picked. No server call, no invented location.
  });
```

- [ ] **Step 5: Pin the flow against ever adopting the multi-step sequence**

The guard has to be built on a **real** `AiApiClient` over a recording `HttpClientAdapter`, not on the existing `_FakeAiApiClient`. That fake `extends AiApiClient` and overrides the methods outright (`ai_copilot_screen_test.dart:32`), so nothing it does ever reaches Dio — a path list captured by an adapter installed elsewhere would be empty for reasons that have nothing to do with the behaviour being asserted, and `expect(paths, isEmpty)` would pass whether the app made zero calls or a hundred. That is a vacuous test wearing a passing grade.

Build it the way `test/data/ai/ai_api_client_test.dart` does — `_Adapter implements HttpClientAdapter` at `:5`, `dio.httpClientAdapter = _Adapter((options) { … })` at `:132` — and route the copilot through the resulting real client by overriding `aiApiClientProvider`:

```dart
  testWidgets('confirming never writes to the server — the report is the phone\'s until submit', (
    tester,
  ) async {
    final paths = <RequestOptions>[];
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) async {
      paths.add(options);
      // Real wire shapes: a session start, a turn, and the confirm response. Nothing else exists
      // on this path, so anything else appearing here is the regression this test exists for.
      return _responseFor(options);
    });
    // The copilot must reach the network through THIS client, not through a method-overriding fake.
    // Overriding aiApiClientProvider with `AiApiClient(dio)` is what makes `paths` mean anything.
    ...
    await confirmFlow(tester);

    expect(
      paths.map((o) => '${o.method} ${o.path}').where((p) => p.startsWith('POST /api/Reports')),
      isEmpty,
      reason: 'mobile does not create a report on confirm (spec §5.5). Routing this through '
          'POST /api/Reports + children would also make a retried material write deplete stock '
          'twice, which no client-side state machine can detect.',
    );
    expect(
      paths.where((o) => o.path.contains('/staff') || o.path.contains('/materiali') ||
                        o.path.contains('/observations')),
      isEmpty,
    );
    // The positive half — the test must be able to fail on a wrong design, not only on a right one:
    expect(
      paths.map((o) => o.path),
      contains('/api/ai/conversations/$sessionId/confirm'),
      reason: 'if this is empty the adapter is not wired to the copilot and every other '
          'assertion here is vacuous',
    );
  });
```

That last assertion is the one that catches the original defect: without it, a mis-wired adapter produces three empty lists and a green tick. A negative test needs a positive control.

This is the mechanical guard for the five-call prohibition (Global Constraints, second bullet) and for Review Focus 5 — the one place in the suite where the reasoning behind this plan is executable rather than prose.

- [ ] **Step 6: Run the file, in the foreground, then the whole suite**

```bash
timeout 900 flutter test test/features/rapportino/ai_copilot_screen_test.dart
timeout 1800 flutter test
timeout 900 flutter analyze
```

The whole suite last, alone, in the foreground. The `ai_copilot_screen_test.dart` file also imports `import_server_report_test.dart`-adjacent fixtures in places — if removing `_FakeServerReportApi` breaks a *different* test file, that file has the same import to clean up; do not restore the fake to avoid the edit.

- [ ] **Step 7: Commit**

```bash
git add lib/features/rapportino/ai_copilot_screen.dart \
        lib/features/rapportino/import_server_report_action.dart \
        test/features/rapportino/ai_copilot_screen_test.dart
git commit -m "feat(copilot): Conferma applies the draft instead of creating a report

Confirm resolves and persists nothing (spec §5.4), so the copilot now applies the
response to the phone's own draft and opens the editor on it. The server object, the
import that fetched it, and the retry-import state all go: there is nothing server-side
to fail to download, and nothing that can move on underneath the technician.

The copy follows, because the old copy was the problem: the button and the toast
described a created report, and what the technician gets is a local Bozza not yet sent.
A rapportino that looks filed and is not is the one outcome this path must not produce.

The session is released with Abandon only after the draft is in Drift, and _sessionId is
cleared first so dispose does not fire a second DELETE at a forgotten id.

importServerReportForEditing keeps its other caller: the list screen still needs the full
children of a server-side Bozza that arrived as a header-only sync row.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Phase B gate

Run, each in the FOREGROUND under an explicit timeout, one at a time:

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
timeout 1800 flutter test      # whole suite — expected PASS
timeout 900  flutter analyze   # expected clean
```

A backgrounded `flutter test` on this mount dies silently and reads exactly like a pass, so a run whose output you did not see is not a run. If a suite is slow, raise the `timeout` — do not move it off the foreground.

Then the device test, on the user's own hardware and against a real backend, because every assertion above is about Drift contents and route targets and none of them is about whether the server accepts the result:

1. Open the copilot from a ticket, talk through a job, and tap **Conferma e apri il rapportino**. Confirm the editor opens on the technician's own words — the title from the ticket, the details from what they dictated, the materials, the checklist answers — and that the Rapportini list shows the row as a **local Bozza**, not as sent.
2. Sign, and submit. Confirm the rapportino arrives on the office side with its materials, its checklist answers and `isAiAssisted` set.
3. Fly the phone after the confirm but before the submit. Confirm the draft is intact, the queue shows it pending, and that reconnecting lands it — the whole point of applying rather than creating.
4. Confirm a conversation started from a **cantiere** rather than a ticket, and confirm in the office that its location is a real one (the server's resolution is best-effort and may fall back to a tenant default) — this is the field Task B3 blocks on, and the one place where "it opened fine" is not the same as "it is correct".
5. Confirm a draft whose response carried warnings, and confirm the technician saw them before leaving the conversation.

Only then: tag `v*`, per the standing release rule. Branch `main`; the change ships on a tag, not on a merge.

---

## Self-review

**Spec coverage.** §5.4 (confirm resolves, persists nothing): B1 reads the response the endpoint actually returns, and its `wireKeys` entries are the contract. §5.5's client split: **mobile applies** — B2 writes the draft, B4 wires it and retires the copilot's import — and **web creates** — explicitly out of scope, a different repo and a different plan. §5.5's conditional, "`importServerReport` is deleted only after confirming it has no other consumers or required side effects", is honoured by *not* deleting it: the list screen's consumer is named in the Global Constraints and in B4's Interfaces. §9's I2 acceptance, "mobile's editor shows the applied draft", is the assertion in B4 Step 4. The hand-off's two non-schema facts — the client owns `isAiAssisted`, and `locationId` may be null and must never fall back to `Guid.Empty` — are B2 and B3 respectively, each with the server-side rejection (or, for the flag, the silent local data loss) it would otherwise cause. The brief's `submission_queue.dart` question is answered as a recorded decision rather than as code: the five-call prohibition (Global Constraints, second bullet) states the prohibition and why, B4 Step 5 makes it executable, and Revision note point 2 carries the five-call retry analysis with the exact source of each verdict. The one item with no task is the queue-drop of a checklist `note`, recorded in the Global Constraints with its cause (I2 cannot produce one) and its separate one-line fix.

**Placeholder scan.** No elisions remain. The `return /* the same failure shape the title check uses */;` that stood in B3 Step 3 is gone: the real check was read (`if (title.isEmpty) { issues.add(DraftValidationIssue.missingTitle); }` — append, never return) and the step now writes the enum member, the Italian string and the `issues.add` call in full. Two test bodies in B2 and B4 Step 4 are marked with a trailing comment rather than a `{ ... }` and state the case they restate; no step is an unstated one. Every identifier the plan names was read from source in this session — after an earlier draft invented four (`_seedInternalUser`, `_widgetRefStub`, `_clientServing`, `DraftValidationResult.field`) that would each have been a compile error or, worse, a passing test that proved nothing.

**Type consistency.** `AiConversationConfirmResponse` is the class in B1, the parameter type in B2's `applyConfirmedDraft`, and the fake's field type in B4. `AiResolvedStaff` / `AiResolvedMaterial` / `AiResolvedControl` are spelled identically in B1's DTO and B2's loops and tests. `applyConfirmedDraft(ref, response:, ticketId:, cantiereId:)` is B2's signature and B4's call — three parameters, no `fallbackTitle`. `controlRowId` is `import_server_report.dart`'s function at `:42`, used once, in B2. `DraftValidationIssue.missingLocation` is added and asserted by name in B3; `DraftValidationResult.issues` is what B3 asserts against — there is no `field` member and no per-field result shape. `markAiAssisted` is **not called anywhere on this path**: B2 writes `isAiAssisted: Value(true)` in its own `saveDraft`, and B4's `_confirm` says in a comment why it must not call the notifier. `wireKeys` is the existing convention in `sync_inbound_contract_test.dart` and B1 adds four entries in it. `materials` / `controlli` are the wire names in B1's DTO, in B1's `fromJson`, in the B1 contract test's `containsAll`, and in B2's loops — `materiali` appears only where the existing Drift/repository names require it (`ReportMaterialiCompanion`, `repo.upsertMateriali`) and `observations` appears only in B4 Step 5's negative assertion and the Revision note's correction. No `reportId` survives on the confirm path except B1's own test that the pre-I2 body parses to nothing.

**Review Focus.** All five have an owner. 1 → B1 Steps 2 and 4, where the wrong-DTO parse is both a test and a gate entry. 2 → B3, whose test asserts the issue member and the Italian string. 3 → B2 (the flag's only writer) and the `markAiAssisted` constraint (Global Constraints, sixth bullet) (why the obvious writer is the wrong one). 4 → B4 Step 3's copy decisions and Step 4's `isLocalOnly` / `stato` assertions. 5 → B4 Steps 2, 4 and 5, which rewrite the fake, the four tests and the negative guard rather than widening any of them.

**Read before writing, seven places, all checked against source:** the two precedent functions in `create_draft.dart` and the `controlRowId` helper (B2 Step 1); `ReportEditorNotifier._hydrateBody` and `_controlloToCompanion`, to know that a Drift write is sufficient and that the row id is `id`-keyed (B2 Step 1); `markAiAssisted` and `_buildHeaderCompanion`, to know that the notifier autosaves the whole header and must not be constructed here (the `markAiAssisted` constraint (Global Constraints, sixth bullet)); `validateDraft`, its callers, and the `_insertDraft` test helper (B3 Step 1); the copilot screen's confirm path and the four tests tied to it, including the shared `confirmFlow` helper the label change touches (B4 Step 1); the controller and `ConfirmResponseBuilder.Build` in the root repo, which are the only description of what the response contains (B1, and Task A1's gate prints it); and `AiConversationsController.Confirm`'s own answer on when a session may be released, which is what orders B4's `abandonConversation` after the Drift write.

## Unverified

Two things this plan cannot settle from source, stated so a reviewer does not read silence as assurance. Everything else in this document was read out of the referenced file at the referenced line, and the route and DTO facts were read from `origin/master` rather than from a working tree.

1. **Whether the four `Sync*Dto` schemas will still be in the snapshot when this lands.** They are in the mobile copy today, produced by backend commit `1950b3d7` on branch `feat/offline-reference-sync`, which is on **no origin ref** — `git branch -r --contains 1950b3d7` is empty and `origin/master`'s `MobileUserSyncResult` has none of the four properties. Task A1's merge is written to preserve them, and the inbound gate fails loudly if they are dropped, but nothing in this plan can make the backend branch land. If it is abandoned, the mobile app is shipping against a contract that exists only on one developer's machine, and that is a decision to take deliberately, not to discover from a red CI run.

2. **Every device test outcome.** The Phase B gate's five manual steps — the editor showing the applied draft, office-side arrival with `isAiAssisted` set, surviving a flight between confirm and submit, a cantiere-bound location resolving to something real rather than a tenant default, and warnings being seen — are assertions about a real server and a real device. No test in this plan covers them, by construction: the widget tests assert Drift contents and route targets. Step 4 in particular is the one where "it opened fine" is not the same as "it is correct", and only the office side can tell you which one you got.

A third item is *recorded rather than unverified* — the `SubmissionQueue` dropping a control `note` at submit (Global Constraints). It is visible in source, confirmed, and deliberately out of scope; it is called out here only so that its absence from the task list is not mistaken for an oversight.
