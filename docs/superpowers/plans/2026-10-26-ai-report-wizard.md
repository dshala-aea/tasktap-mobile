# AI report wizard — Descrivi / Controlla / Firma

Source of truth for behaviour and copy: the client pack `tasktap-rapporto-ai/SPEC.md`
(ClickUp 12493t4rvhn). This plan records how it maps onto what the app already has, and the
decisions taken before building.

## Decisions already made (owner, 2026-10-26)

| Question | Decision |
|---|---|
| Terminology | "Rapporto di intervento" app-wide, mobile + web; "AI Copilot" → "Assistente AI" |
| Chat copilot | Replaced by the wizard (no second entry point) |
| Customer cannot sign | Built, with backend support (reason + note), not deferred |
| Mic on "Descrivi" | Audio upload only — recording → `POST /api/ai/voice-captures` → turn with `audioRef` (ADR-0023 unchanged). No editable transcript; the draft is read on "Controlla". |

Consequence of the last row: SPEC §3's "DESCRIZIONE" card (live transcript) is **not** built. The
technician sees the outcome on step 2 instead. This is the one deliberate deviation from the design.

## What already exists (do not rebuild)

`lib/features/rapportino/ai_copilot_screen.dart` (1 992 lines) is a chat presentation over a complete
engine: session start/resume per ticket, durable server draft, voice capture + upload + idempotent
turn retry, pending recording store, edit-sync (`AiDraftFeed` / `AiEditSyncer`), provenance badges,
quota gating, offline handling, confirm → `applyConfirmedDraft` → local Drift report.

The wizard is a **presentation change**, not a new pipeline. Extract nothing: keep the state
machine, replace the body.

## Files

New under `lib/features/rapportino/ai_report/`:

1. `ai_describe_step.dart` — step 1. Red header (`RAPPORTO DI INTERVENTO`, subtitle
   `{numero} · {cliente}`), intro card, mic card (120 px button, halos, status label
   `● IN ASCOLTO · mm:ss` / `TOCCA PER INIZIARE` / `TOCCA PER CONTINUARE`), "Preferisci scrivere?"
   toggle, error card, footer `Genera il rapporto`.
   States map onto existing flags: `_recording`, `_sending`, `_failed`, `_micBlockedMessage`,
   `_voiceDisabled`.
2. `ai_review_step.dart` — step 2. AI band `✦ Compilato dall'assistente AI · controlla e conferma`,
   cards LAVORO SVOLTO / MATERIALI / ORE / CONTROLLI / STRUMENTI / NOTE, dashed `Da completare` on
   `OpenItems` and unresolved lines, edit mode wired to the existing `_runEdits` / `_accept`,
   footer `Modifica` + `Conferma`.
3. `ai_sign_step.dart` — step 3, **own route**, tied to the local report id Confirm creates.
   Riepilogo, signature pad (reuse `Signature` + the capture/clear/prefill logic from
   `steps/step_riepilogo.dart`), e-mail copy toggle, `Il cliente non può firmare` → reason sheet
   (Assente / Rifiuta / Altro + nota), footer `Firma e invia all'ufficio` → `SubmissionQueue`.

Changed:

4. `ai_copilot_screen.dart` — keep all methods; replace `_buildChat`, `_buildDraftSummary`,
   `_buildInputRow`, header and footer with a `_step` switch (`describe` / `review`); Confirm now
   navigates to the sign route instead of the editor.
5. `lib/core/router/app_router.dart` — `rapportiniCopilot` becomes `rapportiniAi`
   (`/altro/rapportini/ai`); add `/altro/rapportini/ai/firma/:reportId`.
6. `lib/features/ticket/ticket_detail_screen.dart` — the `AI Copilot` button becomes
   `Compila il rapporto`, with `Assistente AI` as the visible qualifier.
7. Drift: `DraftReports.customerSignatureAbsenceReason` (enum index) and
   `customerSignatureAbsenceNote` (text, nullable) + migration step + schema version bump;
   `submission_queue.dart` sends them; `draft_validation.dart` accepts `signature OR reason`.
8. Tests: `test/features/rapportino/ai_report_wizard_test.dart` (step transitions, review gates,
   sign disabled until signed or reasoned), migration test, contract test for the submit payload.

## Backend dependency (tasktap-api, branch `feat/report-signature-absence`)

`Report.CustomerSignatureAbsenceReason` (`Assente|Rifiuta|Altro`) + `CustomerSignatureAbsenceNote`,
accepted by submit/update, exposed in the detail DTO and the PDF, with validation rejecting
signature + reason together. The server already permits an unsigned customer report
(`ReportStateMachine.CanInvia`), so no state-machine change.

## Order

1. Backend field (independent; verify with tests + snapshot).
2. Sign step + Drift columns + submit payload + validation fix (closes the client's "cannot sign").
3. Describe and Review steps, routing, entry button.
4. Delete the chat widgets and their tests; add wizard tests.
5. Terminology rename (separate branch, mechanical).

## Verification

CI is the only trustworthy runner for Flutter here. Locally: `fvm flutter analyze` on touched
files only; never `dart format`. Backend: `dotnet test` with the Postgres env var, and read the
skipped count before calling it green.
