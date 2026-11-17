# Shared material picker + mobile carico/scarico — design

Status: **Draft, for review.**

ClickUp: [Fabbisogno picker parity](https://app.clickup.com/t/12493t4vyb7) and
[Carico/Scarico magazzino da mobile](https://app.clickup.com/t/12493t4vz00).

## Intent

The ticket Fabbisogno tab adds materials with an empty inline row, while the rapportino uses a
search + qty modal. Unify them on one picker, and make the picker resolve the material's real
source warehouse from its giacenze instead of defaulting to the technician's furgone. Fold in the
urgent mobile carico/scarico flow using the existing movement endpoints.

## What the codebase already gives us

- A furgone **is** a `Magazzino` (`tipo == 'Furgone'`); transfers move stock between any two
  magazzini (`POST /api/magazzino/{id}/trasferimento`).
- The catalogue article (`Materiale`) has **no** warehouse field. Stock/provenance lives in
  **giacenze** (`materialeId` + `magazzinoId` + qty).
- `GiacenzaDto` is online-only (`GET /api/app/magazzino/giacenze`, filterable by `magazzinoId`,
  `sottoScorta`, `q`, paged).
- Report material lines already carry `magazzinoId`; submit books the scarico, and the server
  silently no-ops when it is null.
- Ticket material write/read shapes (`CreateTicketMaterialeRequest`, `TicketMaterialeDto`) have
  **no** `magazzinoId`, so office fabbisogno persistence needs the backend handoff.
- Existing movement endpoints: `POST /api/magazzino/{id}/carico|scarico|trasferimento`.

## Goals

1. One shared `MaterialePickerDialog`: catalog search, free text, barcode scan, **numeric-pad qty
   with decimals** (plus the +/- buttons), unit, and source magazzino.
2. Source resolution from the selected article's giacenze:
   - 1 giacenza → select it automatically;
   - multiple → a picker, defaulting to the giacenza with the most stock;
   - none → no source, with a notice that no scarico will be recorded;
   - offline → giacenze unavailable; offer the mirrored magazzini list with a "stock non
     verificabile" notice, and allow no source.
3. Rapportino add-material uses the shared picker; the chosen source flows into the report line and
   the submit payload (scarico).
4. Ticket Fabbisogno "Aggiungi materiale" uses the same picker for search + qty + unit. It does not
   show a source control yet, because the contract cannot persist it (handoff).
5. New mobile **Carico / Scarico / Trasferisci** flow on `/altro/magazzino`: operation, magazzino(s),
   article search/barcode, numeric qty, note; calls the existing endpoints, online-only.
6. Existing behaviour stays: barcode lookup, fabbisogno suggestions in the rapportino, offline
   mirrors, ticket/fabbisogno save/cancel.

## Non-goals

- Backend changes. A handoff file states what the backend/web need for ticket-fabbisogno
  `magazzinoId`.
- Reading a DDT/bolla and auto-carico (roadmap; needs an import/parse surface).
- Changing stock arithmetic or the movement endpoints.
- Editing giacenze directly from the picker.

## Approaches

1. **Extract one picker and one movement dialog (chosen).** The rapportino modal moves to
   `lib/features/materiali/materiale_picker_dialog.dart`, returns a result value, and both call
   sites use it. The movement flow is a second dialog reusing the article lookup and qty control.
2. Make the rapportino dialog public and pass callbacks — couples ticket to the rapportino step.
3. Duplicate the dialog — rejected (the complaint is exactly this divergence).

## Decisions

- **No furgone default.** The source comes from the material's giacenze. The furgone is only one
  possible giacenza, not an assumed fallback.
- **Multiple giacenze:** show a dropdown of `magazzinoNome · qty unit`, defaulting to the largest
  available qty; the user can change it. Zero stock in every giacenza is still "multiple" and
  selectable (the server decides on scarico).
- **No giacenza:** the line/row is allowed with `magazzinoId == null`; the picker states that no
  scarico will be recorded. This matches the server's documented no-op.
- **Offline:** giacenze are online-only. Fall back to `magazziniProvider` (mirror) with a
  "Disponibilità non verificabile offline" notice and no preselection; the user may pick one or
  leave it empty.
- **Quantity control:** a decimal `TextField` (numeric keyboard, accepts `.` or `,`, max 2
  decimals) between the existing −/+ buttons; the buttons stay for quick adjustments. Empty/zero is
  invalid and disables "Aggiungi".
- **Ticket Fabbisogno:** shared search/qty/unit modal only. Source selection is **not** shown there
  until the backend contract exists (see handoff); showing a value that cannot be saved would lie.
- **Movement dialog:** a header action on `/altro/magazzino` (`LucideIcons.arrowLeftRight`, label
  "Carico/Scarico") opens it. Carico picks a destination magazzino; Scarico picks a source;
  Trasferisci picks source + destination. Article via search or barcode; qty numeric; optional note.
  Online-only, like the giacenze/movimenti reads; on success refresh giacenze/movimenti and toast.
- **Barcode:** the picker keeps the existing `BarcodeScanner` injection point so widget tests can
  simulate a scan without a camera.

## Files (expected)

- New: `lib/features/materiali/materiale_picker_dialog.dart` (picker + result + lookup field +
  fabbisogno chips + qty control).
- New: `lib/features/materiali/magazzino_movimento_dialog.dart` (carico/scarico/trasferisci).
- Modify: `lib/features/rapportino/steps/step_materiali_fold.dart` (call the shared picker, remove
  the moved private widgets, map the result to `MaterialeRow`).
- Modify: `lib/features/ticket/ticket_materiali_editor.dart` ("Aggiungi materiale" opens the shared
  picker; map the result to `MaterialeEditRow`).
- Modify: `lib/features/magazzino/magazzino_screen.dart` (header action + show the movement dialog;
  refresh giacenze/movimenti).
- Modify: `lib/data/magazzino/magazzino_api_client.dart` only if a small read helper is needed
  (giacenze-per-material via `q`); no new endpoints.
- New handoff: `docs/handoffs/2026-11-11-ticket-materiale-magazzino.md`.

## Testing

- Picker: single giacenza auto-selected; multiple shows a picker and defaults to the largest; none
  shows the notice and returns null; offline falls back to the mirror; decimal qty via text entry
  (e.g. `2,5`) and via +/-; barcode scan.
- Rapportino: adding a material with a source writes `magazzinoId` into the editor row and the
  submit payload; no source stays null.
- Ticket Fabbisogno: the modal replaces the empty inline row; a catalog pick and a free-text pick
  both create editable rows; save shape unchanged (`CreateTicketMaterialeRequest` keys only).
- Movement dialog: carico/scarico/trasferisci call the right endpoint with the chosen ids and qty;
  offline guard; success refreshes and toasts; insufficient-stock error surfaces the server text.
- Contract: the ticket material request body keys remain a subset of the OpenAPI schema (no
  `magazzinoId` is sent until the backend contract lands).
- Regression: existing rapportino step tests, ticket editor tests, magazzino screen tests.

## Handoff

`docs/handoffs/2026-11-11-ticket-materiale-magazzino.md` asks the backend/web agent to add nullable
`magazzinoId` to the ticket material entity, create/read DTOs, sync projection and office web
editor, with validation and null semantics (no scarico). The mobile ticket Fabbisogno source
control follows once that contract is available; the operator report path does not wait for it.

## Open questions

None.
