# Handoff — ticket fabbisogno source magazzino

**To:** backend (and office web) agent working the TaskTap backend repo
**From:** mobile
**Date:** 2026-11-11
**ClickUp:** [Fabbisogno picker parity](https://app.clickup.com/t/12493t4vyb7),
[Carico/Scarico mobile](https://app.clickup.com/t/12493t4vz00)

## Why

Mobile is unifying its material picker so the report and the ticket fabbisogno use the same
search + qty modal, and so the source warehouse is the article's real giacenza instead of an
assumed furgone. Report lines already support this end to end (`SubmitReportMaterialeDto.magazzinoId`
books the scarico). Ticket fabbisogno does not: `CreateTicketMaterialeRequest`, `TicketMaterialeDto`
and `TicketMateriale` have no `magazzinoId` (confirmed in
`mobile/test/contract/openapi.snapshot.json`). The mobile request-body contract test also forbids
sending undeclared keys, so mobile cannot ship that field ahead of the schema.

## What mobile ships now (no backend change)

- Shared material picker with catalog/free-text/barcode search and a numeric-pad decimal qty.
- Report material source chosen from the article's giacenze (single → auto; multiple → picker;
  none → null, no scarico). The chosen `magazzinoId` is sent on submit.
- New carico/scarico/trasferimento flow on `/altro/magazzino` using the existing
  `POST /api/magazzino/{id}/carico|scarico|trasferimento` endpoints.

## Requested changes

1. **Entity** — add nullable `MagazzinoId` to `TicketMateriale` (FK to `Magazzino`,
   tenant-scoped). Null = no source, no scarico.
2. **Write contract** — add nullable `magazzinoId` to `CreateTicketMaterialeRequest` (and any
   update/replace request) and validate it exists in the caller's tenant. Keep the existing
   `materialeId`/`freeTextName` mutual-exclusion and quantity rules.
3. **Read contract** — add `magazzinoId` (and ideally `magazzinoNome`) to `TicketMaterialeDto` so
   the office/mobile can show and preserve the choice.
4. **Mobile sync** — include `magazzinoId` in `MobileUserSyncResult.TicketMateriali` /
   `SyncTicketMaterialeDto` (the device already parses ticket materials). A missing member must not
   throw; null is valid.
5. **Office web** — expose the source magazzino picker in the office `TicketMaterialiEditor`
   (from the article's giacenze), including the "multiple giacenze" and "no giacenza" states.
6. **Docs/contract** — update `openapi.snapshot.json`. Mobile will then add the optional field to
   `TicketMaterialeDto`/`TicketMaterialeWriteRow` and enable the source picker in the mobile
   ticket Fabbisogno.

## Semantics to keep

- Fabbisogno is **planning**: it must not consume stock. Stock leaves a warehouse only on an
  explicit movement or on report submit (existing `StockMovementService` behavior).
- Null `magazzinoId` = no scarico; do not guess a furgone.
- A material may have zero, one or many giacenze; the office should be able to choose among them
  and must handle "none" without inventing a warehouse.
- A furgone is a `Magazzino`; the office workflow is transfer stock to the furgone (or another
  magazzino), then the report consumes from that source.

## Future (not this handoff)

Reading a DDT/bolla and performing the carico automatically is roadmap; it needs an
import/parse surface (document upload + line matching) and is out of scope for the current mobile
picker/movement work.
