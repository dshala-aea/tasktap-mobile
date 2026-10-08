# Offline architecture re-analysis — mobile, from first principles

Date: 2026-10-08
Status: **ARCHITECTURE DECIDED — Option E (§5), scope D-1 = (a) "own tickets only" (§10).
Ready for implementation planning. D-2/D-3/D-4 remain open with stated defaults.**

**2026-10-08 — RECON CORRECTIONS APPLIED (§2.6, §2.7, §6.4, §8, §9, §10).** Implementation recon
against `master` falsified three facts this document originally asserted, and surfaced one new
defect. **Option E and D-1(a) are unchanged**; the fact base and the resulting task list are not.
Read §2.6–§2.7 before the plan.
Scope: `tasktap_mobile` (Flutter/Drift) and the backend surface it talks to. Read-only analysis of the
repository as it exists today (mobile branch `feat/mobile-asset-checklists`, backend
`docs/api/openapi.snapshot.json` @ `master`).

This document deliberately reopens a question that was previously treated as settled. The prior
offline spec (`2026-09-04-offline-realtime-engine-design.md`) declared "coverage expansion — RULED
CLOSED". The evidence below shows that ruling was about **offline write safety**, and that
**offline read availability** — which is what a field technician actually needs to fill a ticket —
was never specified at all. Those are two different problems and this document keeps them apart.

---

## 1. Current architecture — facts vs assumptions

### 1.1 Facts (verified in code / contract snapshot)

**F — Mobile persistence.** Drift schema v36, `mobile/lib/data/local/app_database.dart`. 32+ tables.
There is **no** `Contracts`, `Commesse`, `ProdottiAssistenza`, `Contacts`, or `Users` table. The
tables that exist and are read by pickers are: `customers`, `locations`, `tickets`, `schedules`,
`draftReports`, `ticketStatuses`, `ticketTypes`, `materiali`, `ticketMateriali`,
`materialeBarcodes`, `cantieri`, `colleagues`, `scheduleAssignees`, plus the checklist/strumenti
tables added in the current feature branch.

**F — Mobile sync is one endpoint.** `mobile/lib/data/sync/sync_service.dart:37` —
`sync()` → `GET /api/sync/mobile?since=<lastSync>` → `SyncResultDto` → one Drift transaction that
upserts `customers`, `locations`, `tickets`, `schedules`, `draftReports`, `submittedReports`,
`ticketStatuses`, `ticketTypes`, `materiali`, `ticketMateriali`, `materialeBarcodes`, `cantieri`,
`colleagues` (wholesale replace), checklist batch; then `setLastSync(payload.syncedAt)`.
No other endpoint feeds a local cache table.

**F — The sync contract carries no reference master data for ticket parity.**
`GET /api/Sync/mobile` → `MobileUserSyncResult` (verified against
`docs/api/openapi.snapshot.json` @ `master`). Members: `syncedAt`, `since`, `schedules`,
`draftReports`, `submittedReports`, `customers`, `locations`, `tickets`, `ticketMateriali`,
`materiali`, `cantieri`, `ticketStatuses`, `colleagues`, `ticketTypes`, `controlGroups`,
`ticketControls`, `ticketAssets`, `assets`, `strumenti`, `reportStrumenti`, `checklistTruncated`,
`checklistOmittedTicketIds`.
It carries **no** `contracts`, **no** `commesse`, **no** `prodottiAssistenza`, **no** contacts,
**no** users/technicians.

**F — Cursor model.** Single-row `SyncMeta` keyed `default:<syncCursorGeneration>`, generation
currently `v9` (`app_database.dart`). Bumping the generation discards the delta cursor and forces
one full sync. `wipeAllData()` clears every table on sign-out.

**F — Server-side cursor mechanics (verified in `MobileUserSyncService`).** The cursor is
client-supplied (`since` query param) and client-stored — there is **no server-side cursor table**.
The server compares `since` against `COALESCE(UpdatedAt, CreatedAt)`; `UpdatedAt` is stamped **only
on update** (`Repository.UpdateAsync`), never on insert, which is why the COALESCE exists. `since ==
null` *is* the full sync — there is no separate bootstrap method.

**F — Exact scope of the technician payload.**
`schedules` = my assignment rows (direct or my squadre), `ActivityDate ∈ [today−7d, today+7d]`;
`tickets` = tickets on those schedules **or** `AssignedUserId == me && ClosedAt == null` (the
technician branch is deliberately **not** delta-filtered); `locations` = `schedule.LocationId ∪
ticket.LocationId`; `customers` = `ticket.CustomerId ∪ location.CustomerId`. Office/Admin get
`fullScope` (all tenant rows + delta). `materiali` (active), `cantieri` (assigned, else active),
`ticketStatuses`, `ticketTypes`, `colleagues` are **tenant-wide** regardless of role.
This is the scope that makes the customer picker thin — and it is not a stated product rule.

**F — No tombstones, anywhere.** The payload has no deletion list and no soft-delete flag. Hard
deletes simply vanish from a delta; deactivation is invisible (the server filters `IsActive` /
`Status`); the one soft-deleted entity, `Customer`, is hidden by the global query filter. So the
device cannot distinguish "deleted server-side" from "not changed since my last sync" — a deleted
customer or a deactivated user lingers in the local cache until a full resync.

**F — The sync endpoint is unpaginated.** The whole payload returns in one response; volume is
bounded only by the scope windows above. Any reference-data addition grows this single response.

**F — Ticket-create FK failures are HTTP 404, not 400.** `ReferentialIntegrityService` throws
`NotFoundException` for every missing/stale/cross-tenant FK (`Customer`, `Location`, `User`,
`Contract`, `ProdottoAssistenza`, `Agent`, `Commessa`, `Cantiere`, `Materiale`) and for
`TicketStatus`/`TicketType`; a foreign-tenant id is deliberately indistinguishable from a
non-existent one. The only paths that produce **400** are: malformed model binding (no
FluentValidation validator is registered, so this is binding only), an **omitted** `TypeId`
(`ticket_type_required`), an omitted `StatusId` on a tenant with no default status
(`no_default_ticket_status`), a non-visible `MaintenanceTemplateId`, and a missing ambient tenant
context. Mobile always sends `typeId` and `statusId` and a well-formed body, so none of the 400
paths describe its request — see §2.4.

**F — Idempotency is server-side and ordered before the guards.** `POST /api/tickets` with a
`clientId` that already exists returns the existing ticket (200) **before** any FK guard runs; a
concurrent duplicate is caught and resolved to the winner (201). So the `clientId` retry contract
the mobile queue relies on is real.

**F — `Ticket.ProdottoAssistenzaIds` is `[NotMapped]` and always ships `[]`.** The sync therefore
never delivers a ticket's covered-asset ids, so even a perfectly cached ticket cannot repopulate
that field offline. `ContractId`, `CommessaId`, `CantiereId` *are* mapped and *are* carried on the
ticket body.

**F — Ticket create on mobile is a subset of web.** `mobile/lib/features/ticket/ticket_api_client.dart:36`
POSTs `/api/tickets` with exactly: `title`, `description?`, `customerId`, `locationId`,
`assignedUserId?`, `statusId`, `typeId`, `priorita`, `clientId?`, `dueDate?`, `technicianNotes?`,
`agentId?`, `tags?`. `POST /api/Tickets` accepts all of those **plus** `internalNotes`,
`contractId`, `prodottoAssistenzaIds` (array), `commessaId`, `maintenanceTemplateId`, `cantiereId`,
`materiali` — none of which mobile sends. So mobile cannot express a ticket the office can.

**F — Ticket create is local-first with a dedup key.** `mobile/lib/data/tickets/ticket_creation_queue.dart`.
`create()` persists the row (uuid v4 id) then attempts if online; every attempt sends
`clientId: <local uuid>`. Resend is idempotent server-side. `processAll()` **auto-retries both**
`pendingSync` **and** `failed` rows (on reconnect and app start). The wizard's own docstring at
`new_ticket_form_screen.dart:122-125` still claims the opposite ("no client-supplied dedup key …
never auto-retried") — stale comment, contradicts the queue.

**F — Ticket edit on mobile is NOT queued.** `edit_ticket_screen.dart` does a direct
`PUT /api/tickets/{id}` via `adminApiClientProvider`, mirrors locally only on success, and handles
409 by resync+reseed. So the *create* path survives offline and the *edit* path does not. The
rapportino path (`SubmissionQueue`) is the local-first precedent for edits; tickets do not use it.

**F — Pickers split into three inconsistent behaviours.**

| Picker | Source | Offline behaviour |
|---|---|---|
| Ticket wizard, Cliente | Drift `allCustomersProvider` | empty if not cached; **no search, no free-text** |
| Ticket wizard, Sede | Drift; "new sede" needs a live call gated by `ensureOnlineOrWarn` | dead offline |
| Ticket wizard, Tecnico | **live** `fetchTechnicians()` → `GET /api/users?role=Technician` | error state offline ("Impossibile caricare i tecnici") |
| Rapportino, Cliente/Sede | Drift **with free-text fallback** | degraded but usable ("scrivi il nome, verrà collegato dopo") |
| Magazzino / admin writes | live only, `ensureOnlineOrWarn` | deliberate "a wrong queue is worse than an honest error" |

**F — No server-search client exists on mobile.** Grep of `lib/**/*.dart`: nothing calls
`/api/Contracts`, `/api/Commesse`, `/api/ProdottoAssistenza`; the only `/api/customers` caller is
`admin_api_client.dart` (admin CRUD), not a picker. The "local first, server search on demand"
picker decision is **not implemented anywhere**.

**F — Server search already exists.** `GET /api/Customers`, `/api/Contracts`, `/api/Commesse`,
`/api/ProdottoAssistenza`, `/api/Materiali` all accept `Q` (free-text) plus scoping filters
(`customerId`, `locationId`, `librettoId`, `isActive`, `categoria`, `stato`) and a paged envelope.
No new search API is required to support on-demand lookup.

**F — Offline write safety is already correct and deliberate.** `ensureOnlineOrWarn` gates every
admin/magazzino write. Local-first is reserved for the technician's own work (tickets create,
rapportini, timbra). This distinction is sound and this document does not propose changing it.

### 1.2 Assumptions (were treated as fact; now labelled)

**A1.** "The sync scope is the right scope for what a technician may see." — **CHALLENGED.** The
schedules are bounded to ±7 days and the technicians' customers/locations are derived from those
schedules and tickets (`MobileUserSyncService`); that limit is a *consequence* of `GetDeltaAsync`'s
scoping, not a stated product rule. It keeps confidentiality by accident: a technician cannot
browse customers they have no recent ticket for. If we widen the sync to fix the parity gap, we
silently widen that exposure unless the scope is made explicit (see §10, D-1).

**A2.** "The offline spec is closed." — **CHALLENGED.** That spec closed *write* coverage; it says
nothing about the reference data needed to *fill* a ticket, and explicitly deferred the topic.

**A3.** "Ticket create failing is a sync problem." — **PARTIALLY CHALLENGED.** Offline, the create
is queued and never errors. The user-visible failure happens **online**, on the immediate attempt
or on a later auto-retry, which is a different mechanism (see §2.4).

**A4.** "Reference data is optional because the technician mostly reads their own tickets." —
**CHALLENGED.** Creating a ticket *is* the core technician action, and it currently requires
reference data that is either thin (customers), stale-scoped (locations), or absent entirely
(technicians, contracts, commesse, prodotti).

---

## 2. Root causes

### 2.1 Customer sync is forward-only and scoped by tickets — CONFIRMED

`MobileUserSyncService.GetDeltaAsync` scopes the payload: schedules assigned to me **within
±7 days** → their locations → their tickets → those customers (tickets assigned to me and still
open are also included, un-delta'd). A customer the technician has no recent ticket for is simply
never sent. Combined with a wizard that reads `allCustomersProvider` and offers no
fallback, the visible symptom is an **empty customer picker** for any customer not already on one
of the technician's tickets. This is the root cause of "empty customer pickers / dead wizard".

It also **is** the (accidental) confidentiality control: it is what stops a technician from
enumerating the customer book. Removing it to "fix" the picker would create a confidentiality
regression. **The fix is to make the scope explicit and role-aware, not to widen it blindly.**

### 2.2 The reference cache is thin and stops short of what a ticket needs —

Confirmed by the contract: the payload has no contracts, commesse, prodotti assistenza, contacts
or users. The ticket wizard therefore cannot offer, offline, any of the FK-backed fields web
offers. This is not a bug in the sync *mechanism*; it is a gap in the sync *contract*.

### 2.3 Ticket parity gap has two distinct halves —

(a) **Missing fields** on the create/edit path (`contractId`, `prodottoAssistenzaIds`,
`commessaId`, `cantiereId`, `maintenanceTemplateId`, `internalNotes`, `materiali`) — the mobile API
client does not send them. For `prodottoAssistenzaIds` the original claim in this paragraph was
**wrong** and is corrected in §2.6: the covered-asset path is already built end-to-end and needs
nothing new.
(b) **Missing reference data** to populate those fields — the sync does not deliver the entities,
and there is no local table to hold them.
Fixing (a) without (b) yields empty dropdowns; fixing (b) without (a) yields cached data no field
can use. They must be designed together, which is exactly why this document exists.

### 2.4 The "submitting a ticket returns an error" path — mechanism confirmed (404-class, not 400)

The offline branch of `_onSubmit` never errors (it queues). The online branch calls
`queue.create(isOnline: true)` → `_attempt` → `_apiClient.createTicket(...)`; on any thrown error
it stores `humanErrorMessage(e, azione: 'creare il ticket')` and the user sees *"l'invio non è
riuscito (…)"*. `processAll()` auto-retries `failed` rows on reconnect and app start, so a
transient failure can also surface later, off-screen — which matches "probably due to sync issues
offline-online".

Verified against the backend code, the failure is a **404 from a stale FK, not a 400**:

- Every FK guard on create (`Customer`, `Location`, `User`, `Contract`, `ProdottoAssistenza`,
  `Agent`, `Commessa`, `Cantiere`, `Materiale`) and on `StatusId`/`TypeId` throws
  `NotFoundException` → **404**.
- The 400 paths are: malformed binding, **omitted** `TypeId`, **omitted** `StatusId` with no default
  status, non-visible `MaintenanceTemplateId`, missing tenant context. Mobile always sends `typeId`
  and `statusId` and a well-formed body, so **none of these describe the mobile request**.
- The request is also not a `clientId` problem (uuid v4 = 36 chars, cap 100; replay is handled
  server-side before the guards) and not a `priorita` problem (mobile sends `Media`).

So the mechanism is a **stale FK in a cached or queued row**: a `customerId`/`locationId`/`statusId`/
`typeId`/`assignedUserId` that was valid when the ticket was drafted (or when the picker list was
cached) and is no longer valid when the send lands — because the referenced row was deleted,
deactivated, or belongs to another tenant. This is precisely the failure mode §6.6 exists to
repair. The one thing only a runtime repro can add is the exact entity named in the 404 body; the
code-level path is settled and is why the fix below is a *repair* flow, not a retry.

**CORRECTED (see §2.6):** this paragraph originally read *"`Ticket.ProdottoAssistenzaIds` is
`[NotMapped]`, so the sync ships it as `[]` and even a fully-cached ticket cannot repopulate its
covered-asset ids."* That is false on `master`: the property is excluded by Fluent
`entity.Ignore(...)`, **not** by an attribute, and the deployed sync fills it.

### 2.5 The premise to challenge — write safety was solved, read availability was not

The prior spec's "closed" ruling is true for writes and silent for reads. A technician offline can
*record* work but cannot *fill* a ticket, because the vocabulary of a ticket — which customer,
which contract, which product, which commessa — is not on the device. This is the single
correction this document is built on: **treat read availability as its own design axis, distinct
from write safety, with its own scope, freshness and confidentiality rules.**

### 2.6 CORRECTION — the covered-asset path already exists end-to-end

Recon against `master` (deployed) falsifies §2.3(a)'s `[NotMapped]` claim.

- `Ticket.ProdottoAssistenzaIds` (`Ticket.cs:198-205`) is excluded from persistence by Fluent
  `entity.Ignore(e => e.ProdottoAssistenzaIds)` (`TicketConfiguration.cs:93`), **not** by a
  `[NotMapped]` attribute. The join table `TicketProdottoAssistenza` is the source of truth.
- The deployed sync **already fills it**: `MobileUserSyncService.cs:147-162` runs one set-based query
  over `TicketProdottoAssistenza` for the synced tickets and assigns `ProdottoAssistenzaIds` per
  ticket — additive on the wire, since the property is already part of the serialised ticket. Pinned
  by `tests/.../Sync/MobileUserSyncTicketAssetsTests.cs` (a `master`-only test, including
  `Wire_name_is_prodottoAssistenzaIds`).
- The mobile branch already consumes it: `TicketAssets` / `ticket_assets` (plan 5b, Tasks 1–4).

**Consequence: the ticket↔product relation needs no new server mapping, no new Drift join table,
and no migration column.** §8 and §9 are amended accordingly, and the plan loses a task.

### 2.7 NEW HIGH FINDING — "Riferimento" sends a User id into an Agent FK → deterministic 404

Found while verifying §2.4. This is a *deterministic* failure, not a staleness one, and a stronger
candidate for the reported "submitting a ticket returns an error" than §2.4's stale row.

- `CreateTicketCommand.AgentId` is guarded by `EnsureExistsAsync<Agent>(request.AgentId)` and then
  assigned to `Ticket.AgentId` (`TicketCommandService.cs:97,131`; same guard on update at `:300,326`).
- **Both clients populate that field from the Users list, not from `Agent`.** Web:
  `TicketCreatePanel.tsx:500-513` binds "Riferimento" to `loadUserOptions`, which calls `GET /users`
  (`picker-loaders.ts:198-213`). Mobile: `step_dettagli_ticket.dart:236-272` binds it to
  `techniciansProvider` (`GET /api/users?role=Technician…`).
- A real `Agent` aggregate exists and is separately served (`AgentsController`, `GET /api/agents`,
  `ClientiAgentRead`). The web app never calls it.

A `User` id and an `Agent` id are independent `Guid`s, so the guard cannot pass: any ticket created
**or edited** with "Riferimento" set is rejected **404** — on both clients. Not yet reproduced at
runtime; the plan pins it with a test before changing anything.

---

## 3. Offline capability matrix

Twelve questions asked of each entity. Legend: **Y** yes / **N** no / **~** partial / **—** n/a.
Columns: 1 needed-offline-for-the-job · 2 needed-to-create-a-ticket · 3 needed-to-edit-a-ticket ·
4 needed-to-validate-a-queued-ticket · 5 in sync today · 6 local table today · 7 read by a picker
today · 8 role/tenant-gated server-side · 9 delta-capable (`UpdatedAt`) · 10 server search (`Q`)
exists · 11 soft-delete/tombstone · 12 authority if changed while offline.

| Entity | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Customer | Y | Y | ~ | Y | ~ scoped | Y | Y | Y | Y | Y | ~ | server |
| Location | Y | Y | ~ | Y | ~ scoped | Y | Y | Y | Y | — (by-customer) | ~ | server |
| Contact | ~ | N | N | N | N | N | N | Y | Y | N | ~ | server |
| Contract | Y | Y | Y | Y | N | N | N | Y | Y | Y | ~ | server |
| Commessa | Y | ~ | ~ | Y | N | N | N | Y | Y | Y | ~ | server |
| ProdottoAssistenza (+libretti/matricole) | Y | Y | Y | Y | N | N | N | Y | Y | Y | ~ | server |
| Materiale (+barcodes) | Y | ~ | ~ | Y | Y | Y | Y | Y | Y | Y | ~ | server |
| TicketStatus | Y | Y | N | Y | Y | Y | Y | Y | Y | — | ~ | server |
| TicketType | ~ | Y | N | Y | Y | Y | Y | Y | Y | — | ~ | server |
| User (technician) | Y | Y | Y | Y | ~ colleagues only | ~ colleagues | Y | Y | Y | — | Y | server |
| Agent | ~ | ~ | ~ | Y | N | N | N | Y | Y | — | ~ | server |
| Cantiere | Y | ~ | ~ | Y | Y | Y | Y | Y | Y | — | ~ | server |
| Schedule | Y | — | — | — | Y | Y | Y | Y | Y | — | ~ | local+server |
| Colleague | Y | Y | ~ | N | Y | Y | Y | Y | Y | — | — | server |
| Checklist / Controls | Y | N | Y | Y | Y | Y | Y | Y | Y | — | — | local (rapportino) |
| Ticket (self) | Y | — | Y | Y | Y | Y | Y | Y | Y | — | ~ | server |
| TicketMateriale | Y | N | Y | Y | Y | Y | Y | Y | Y | — | — | server |
| Report (draft/submitted) | Y | N | Y | — | Y | Y | Y | Y | Y | — | — | local while editing |

Reading the matrix: the entities a ticket needs and the device does not have are **Contract,
Commessa, ProdottoAssistenza, Contact, Agent** (rows 4–6, 11) plus a **full technician list**.
Those five are the actual scope of the read-availability gap. Everything else is already present,
scoped, or deliberately online-only.

Two clarifications the matrix forces:

- **Column 1 vs column 2.** "Needed offline for the job" is not the same as "needed to create a
  ticket". Contacts and agents are barely needed for the job but are ticket fields; a full
  technician list is needed for assignment but a technician rarely picks a *different* technician
  than themselves. This distinction is what lets §4 pick the smallest adequate option.
- **Column 12 (authority).** Only two entities are locally authoritative while offline: the
  rapportino checklist answers and the ticket/report the technician is actively editing. Everything
  else is a read-only mirror and must never let a local edit win.

---

## 4. Architecture options

**Option A — Current (forward-only work sync).** Keep the sync as-is; accept that offline ticket
creation is limited to the technician's existing customers/locations and that contracts, commesse,
prodotti and technicians are online-only. Cheapest; leaves the reported defect unfixed.

**Option B — Local-first reference cache (full tenant).** Sync every reference entity for the whole
tenant to every device. Simple to reason about; **breaks the confidentiality decision** (a
technician could enumerate the whole customer/product book) and grows the DB unbounded with tenant
size. Rejected on the repo's own stated decision.

**Option C — Hybrid (local mirror + live fallback per field).** Add local tables for the gap
entities but keep every picker also able to go live. Closest to the rapportino precedent but
does not define *which* rows are mirrored, so it inherits B's confidentiality problem whenever the
mirror is populated eagerly.

**Option D — Tenant-user snapshot.** One scoped snapshot per (tenant, user) covering the entities
that user may legitimately see, refreshed by delta. Correct confidentiality by construction (the
snapshot is computed server-side under the same authority rules as the ticket list). Heavier on the
server (a per-user snapshot computation) and needs a precise scope predicate, but reuses the
existing delta + Drift mechanism wholesale.

**Option E — Local-first reference cache + server search on demand.** Mirror the gap entities
**scoped to the technician's legitimate set** (own tickets' customers, their contracts/commesse,
their products, the tenant's technician roster), and for anything outside that set use the
**existing** `Q` search endpoints on demand, gated by `ensureOnlineOrWarn`. This is the picker
decision the repo already recorded, extended to the entities it was not yet applied to. Reuses
Drift, delta, and the existing search API; adds no new mechanism.

### Comparison

| | Confidentiality | Offline create works | Server cost | New mechanisms | Repo fit |
|---|---|---|---|---|---|
| A Current | accidental | no | none | none | — |
| B Full cache | broken | yes | low | none | violates stated decision |
| C Hybrid | unclear | yes | low | none | ambiguous scope |
| D User snapshot | by construction | yes | high (per-user compute) | snapshot builder | new concept |
| E Local-first + search | explicit | yes (for the scoped set) | low (search only on demand) | none | matches picker decision |

---

## 5. Recommended architecture — Option E

**Recommendation: Option E — a scoped local-first reference cache, with server search on demand
for anything outside the scope.**

Why this is the smallest adequate option:

1. **It matches the decision the repo already made.** "Picker: local first, server search on
   demand" is recorded; the gap is that it was applied to zero entities. E makes it a rule for all
   of them and defines the local scope explicitly, replacing the accidental forward-window.
2. **It reuses every existing mechanism.** Drift tables, the one `/api/sync/mobile` delta, the
   `syncCursorGeneration` cursor, `ensureOnlineOrWarn`, and the five `Q` search endpoints that
   already exist. No CRDTs, no event sourcing, no per-user snapshot service.
3. **It keeps confidentiality by construction, and D-1 (§10) has fixed the scope to (a).** The
   local scope is a *named predicate* on the server — the technician's own work scope — so widening
   the mirror is a deliberate, reviewable act, not a side effect of a sync change. A technician's
   device holds their tickets' customers and their contracts/products, not the customer book.
   Online search may still reach anything the server authorizes and materialize the pick locally
   (§7.4), which is why (a) does not limit what a technician can *create*, only what they *mirror*.
4. **It respects the two axes.** Write safety is untouched (admin/magazzino stay online-only;
   ticket create stays local-first + idempotent). Only *read availability* changes: pickers gain
   a local mirror for the scoped set and a live search path for everything else.

Explicitly rejected: full-tenant replication (B/C), per-user snapshot services (D), and any
offline-capable magazzino/admin write queue (§10 keeps that as an open product question, not a
technical default).

---

## 6. Sync design

**6.1 Bootstrap.** First sync after login (or after a `syncCursorGeneration` bump) sends no
`since`. To keep the first payload bounded, the reference cache is loaded **by scope, not by
tenant**: the server computes the technician's legitimate set and sends it. The sync endpoint is
unpaginated today (§1.1), so if the scoped set exceeds a cap it must be fetched through the existing
paged `Q` endpoints (or the sync endpoint must gain pagination) rather than growing the single
response without bound.

**6.2 Incremental.** Extend `MobileUserSyncResult` with the five gap entities
(`contracts`, `commesse`, `prodottiAssistenza`, `contacts`, `agents`/`users`), each delta-keyed on
`UpdatedAt` where the entity carries it (all five are `BaseEntity`-derived, so the existing
`COALESCE(UpdatedAt, CreatedAt)` `since` delta applies unchanged). The mobile `SyncService` adds one
upsert helper per entity (§8), mirroring the existing `_upsert*` pattern.

**6.3 Reference vs work data — two different cursors.** Reference data changes rarely and is
shared; work data (tickets, rapportini) changes with the technician's day. Keep them in one
payload for now (simpler, already the case) but make the freshness expectations differ in the
UI contract (§7): a stale picker entry is acceptable; a stale *ticket* is not. If reference volume
later forces it, split into two cursors (`referenceCursor`, `workCursor`) — **not now**.

**6.4 Deletions — the one place the server must change beyond "send more".** Today there are **no
tombstones anywhere** (§1.1): hard deletes vanish from a delta and deactivation is filtered
server-side, so the device cannot tell "deleted" from "unchanged". For the existing scoped entities
this is mostly hidden by the short window, but for a *reference* cache it is a correctness bug —
a picker would offer a deleted contract forever.

**CORRECTED — no new columns are needed, and the original proposal would have made things worse.**
It suggested adopting `ISoftDeletable` on the gap entities. `DeletedAt` is honoured by a global query
filter (`ApplicationDbContext.cs:533-538`), so a soft-deleted row would vanish from the delta and the
device would still never learn — the same bug one migration later, plus an `IgnoreQueryFilters()` in
the sync, which is a tenant-isolation-sensitive call this work does not need to make. The gap
entities already carry a server-visible flag, and it is sufficient:

1. **Carry `IsActive`, do not filter on it, in the sync scope.** `Contract.IsActive`,
   `Commessa.IsActive`, `ProdottoAssistenza.IsActive` and `Agent.IsActive` all exist. The scope
   predicate stops excluding inactive rows and sends them with their flag; the picker filters
   `isActive == true`. A deactivation then reaches the device as an ordinary delta — the transition
   that is missing today.
2. **Prune on bootstrap.** On a payload with `since == null` (first login, or a
   `syncCursorGeneration` bump) the client deletes reference rows the payload does not contain. The
   bootstrap payload is the *complete* scoped set, so this is the honest answer for rows a hard
   `DELETE` removed, which no flag can describe. One rule, no per-row tombstones, self-healing.
   Known limitation, accepted: a row materialised by an online search pick (§7.4) but outside the
   scope is dropped at the next bootstrap and must be re-found online. Bootstrap runs once per
   cursor generation, i.e. roughly once per app upgrade.
3. For entities the server always sends completely per sync (`colleagues`), keep the existing
   wholesale-replace; it is the degenerate case of rule 2.
4. Do **not** build a tombstone table, a `DeletedAt` sweep service, or vector clocks. The scoped
   reference set is small, low-churn, and rebuildable from the server in one request.

**6.5 Cursors.** Reuse `syncCursorGeneration`. Bumping it forces a full resync of the extended
payload; do this **once** when the gap entities are added, so every device re-bootstraps the
reference cache atomically.

**6.6 Stale entities on queued work — the §2.4 failure.** Before any queued ticket is sent,
validate its FKs against the local cache and treat a miss as *unknown, not invalid* (the row may
simply not be cached). Policy: attempt the send; if the server rejects a specific FK, surface a
**repair step** ("il cliente/l'utente non esiste più — scegli un sostituto") that edits the queued
row in place and retries, rather than a bare failure toast. Nothing the technician typed is ever
lost (the queue already guarantees this).

**6.7 Retries.** Unchanged: `TicketCreationQueue` keeps `clientId` idempotency and auto-retry for
both `pendingSync` and `failed`; `SubmissionQueue` keeps its 5-attempt transient cap. The only new
rule is 6.6's repair-on-FK-rejection.

**6.8 Permissions.** Every gap entity's scope predicate runs under the same authority rules as the
ticket list (role + tenant + assignment). D-1 is now answered (§10): the predicate is **(a) the
technician's own work scope** — the entities reachable through their own tickets, exactly the
traversal `MobileUserSyncService` already performs for customers/locations, extended to
contracts/commesse/prodotti/contacts/agents. Nothing tenant-wide enters the mirror.

---

## 7. Offline UX contract

The contract states, per screen, what a technician can do with no network. It replaces the
implicit "it depends what happens to be cached".

**7.1 Creating a ticket offline (walkthrough, as the code stands).**
1. Wizard opens. Cliente step reads `allCustomersProvider` → shows the customers on the
   technician's tickets. If that set is empty (new technician, or all their tickets are old and
   pruned) the list is empty and there is **no search and no free-text** → the wizard is a dead end.
2. Sede step depends on the customer; "new sede" is blocked offline by `ensureOnlineOrWarn`.
3. Tecnico step calls the network live → offline it shows "Impossibile caricare i tecnici".
4. Dettagli step is local (title/type/priority/dates/notes) and fine offline.
5. Submit: queued locally, sent on reconnect, auto-retried.

**Required contract.** Offline, the technician must be able to (a) pick from a non-empty,
scoped customer set; (b) pick a location for that customer; (c) leave assignment unset or default
to self without a network call; (d) submit; and (e) *never* be blocked by a picker that could be
filled from cache or search. Where data genuinely cannot be local, the field is **optional** and
the UI says so, rather than presenting a dead control.

**7.2 The rapportino already meets this bar** (free-text fallback + `SubmissionQueue`). The ticket
path does not. Bringing the ticket path to the rapportino's standard is the concrete UX target.

**7.3 Degradation is labelled, never silent.** Every locally-mirrored picker shows a
"dati offline, aggiornati alle HH:MM" hint and offers pull-to-refresh when online; every
search-on-demand picker is disabled with an explicit offline note. No control is silently empty.

**7.4 Online search discovers, the pick materializes (D-1).** A picker shows the local scope first;
when online, typing also runs the `Q` search and can return anything the server authorizes. The
row the technician **selects** is written into the local cache immediately, so the customer/location
they just chose is present offline next time and the ticket they create from it validates. This is
what keeps D-1 a mirror boundary rather than a create boundary: the technician is never limited to
what they had cached at the moment they opened the wizard, and never sees the whole customer book
without a deliberate search.

---

## 8. Data / schema changes (minimum — no migrations yet)

**CORRECTED (see §2.6):** four tables, not five. `CustomerContact` is dropped — the create contract
has no contact field (`CreateTicketCommand` carries `AgentId`, not `ContactId`) and contacts are only
reachable per customer (`GET /api/customers/{id}/contacts`), so mirroring them buys nothing a ticket
can use. YAGNI.

New Drift tables (mirroring the existing `_upsert*` shape: id, tenantId, createdAt, updatedAt, the
DTO fields, `isActive`):
`Contracts`, `Commesse`, `ProdottiAssistenza`, `Agents`.

Changed: `tickets` already has `contractId`, `prodottoAssistenzaId`, `commessaId`, `cantiereId`
columns (written by `_upsertTickets`) — but the create path never sends them, so they are only
populated when the *server* sets them. The create form must send `contractId`/`commessaId`/
`cantiereId`. **Covered assets are already solved** (§2.6): the deployed sync fills
`Ticket.ProdottoAssistenzaIds` and the device mirrors it as `ticket_assets`. No join table is added
here, and `tickets.prodottoAssistenzaId` is not the coverage relation.

One `syncCursorGeneration` bump; one `from < N` migration step creating the five tables; indexes
on the FK columns each picker filters by (`customerId`, `contractId`, `locationId`, `isActive`).

**Out of scope by design:** no CRDT/vector-clock columns, no outbox for admin/magazzino, no
per-user snapshot table.

---

## 9. Backend / API changes (minimum — no implementation)

1. Extend `MobileUserSyncResult` with `contracts`, `commesse`, `prodottiAssistenza`, `agents` —
   **four, not five** (§8) — each delta-keyed on `UpdatedAt` and scoped by the §6.8 predicate. **No
   new soft-delete flags**: send `IsActive` as a carried field (§6.4). `TicketStatus` and
   `TicketType` are the only synced entities with **no** `UpdatedAt`; the gap entities are all
   `BaseEntity`-derived and do carry it, so the existing `COALESCE(UpdatedAt, CreatedAt)` delta
   applies unchanged.
2. **Already done on `master` — no work** (§2.6). The sync fills `Ticket.ProdottoAssistenzaIds` from
   `TicketProdottoAssistenza`; the client mirrors it as `ticket_assets`.
3. No new search API; reuse the existing list endpoints. **But two of the four silently ignore `q`
   today** — verified: `ContractsController.GetAll` and `ProdottoAssistenzaController.GetAll` bind
   `ListQuery` and never read `query.Q` (whereas `CommesseController.cs:69-70` does). Search-on-demand
   would be a lie for contracts and products, so wiring `q` into those two is part of this work, not
   optional polish.
4. Turn the create/update FK guards' 404 into a **structured, field-identifying error**
   (`{ field: "customerId", code: "not_found" }`) so the mobile repair step (§6.6) can name the
   offending FK instead of parsing an Italian message string. Keep the 404 status (it is
   deliberate that a cross-tenant id is indistinguishable from a missing one); add the field name,
   not a new code.

---

## 10. Open decisions (genuine product input required)

- **D-1 — RESOLVED (2026-10-08): (a) Own tickets only.** The mobile reference cache mirrors only the
  customers, locations, contracts, products/services, agents and related reference data (four gap
  entities — see §8) reachable through the technician's own ticket/work scope. This makes the current sync boundary
  **explicit** rather than expanding mobile visibility. Online `Q`/search remains the mechanism for
  references outside the local cache. No tenant-wide or cantiere/commesse-wide mirroring is
  introduced by this feature.

  **Critical reading of (a) — it is a *mirror* boundary, not a *create* boundary.** It does not mean
  "a technician can only create tickets for customers already in the local cache". It means:
  **offline**, pickers use the technician's locally-mirrored work scope; **online**, `Q`/search can
  discover anything the server authorizes, and the selected result is **materialized into the local
  cache as needed** (so the next time it is offline). Option E is exactly this shape, so the
  decision preserves the recommendation rather than narrowing it.
- **D-2.** *Offline assignment.* May a ticket created offline be assigned to another technician,
  or default to self? Default assumed: self-or-unset, no roster needed offline.
- **D-3.** *Reference freshness.* How stale may a mirrored customer/contract be before the UI must
  refuse to use it? Default assumed: soft — always usable, always labelled (§7.3).
- **D-4.** *Magazzino/admin writes offline.* Out of scope here (online-only is deliberate). Confirm
  it stays a product decision, not a technical gap to close in this work.

---

## 11. Migration strategy (without corrupting queued work)

1. Ship the backend payload extension first (additive; old clients ignore new members).
2. Bump `syncCursorGeneration` in the same mobile release that adds the tables, so the first sync
   after upgrade is a full re-bootstrap. A queued ticket is a row in `pendingTickets`, untouched by
   a sync-generation bump (only `wipeAllData()` clears it, and that is sign-out).
3. The five new tables are created by a single `from < N` step; existing tables and `pendingTickets`
   are not altered, so in-flight tickets survive the upgrade.
4. Rollback: reverting the app leaves the extra tables unknown-but-harmless; reverting the backend
   leaves the client with empty (not corrupt) reference tables.
5. Verify with a queued-ticket round-trip test: queue offline → upgrade schema → reconnect → ticket
   lands with its `clientId` unchanged.

---

## 12. Testing strategy

- **Sync contract tests** (existing pattern `sync_inbound_contract_test.dart`): assert the new
  payload members parse and that an older backend's absence of them does **not** look like "empty"
  (the `carries*` flag discipline already established).
- **Scoping tests** (backend): the reference payload for a technician contains exactly D-1's set —
  a technician must not receive an out-of-scope customer/contract. This is a security test, not a
  convenience test.
- **Picker tests:** every picker renders non-empty when its cache is populated, renders the
  labelled offline state when it is not, and never presents a dead control (the §7.1 contract).
- **Queue tests:** `clientId` stability across retries; FK-repair flow (§6.6) edits the queued row
  in place; nothing typed is lost on any failure path.
- **Migration tests:** the `from < N` step on a v(N-1) DB with a populated `pendingTickets`; the
  cursor-bump full resync; the rollback shapes of §11.
- **Regression:** the exact online-create failure of §2.4 reproduced as a test (queued row with a
  now-invalid FK → server rejection → repair path), so the reported defect is pinned, not just
  fixed.

---

## Evidence (files read for this analysis)

Mobile: `lib/data/sync/sync_service.dart`, `lib/data/local/app_database.dart`,
`lib/data/sync/sync_dto.dart`, `lib/data/tickets/ticket_creation_queue.dart`,
`lib/features/ticket/ticket_api_client.dart`, `lib/features/ticket/new_ticket_form_screen.dart`,
`lib/features/ticket/steps/*`, `lib/features/ticket/ticket_providers.dart`, `lib/features/rapportino/*`,
`lib/presentation/providers/schedule_providers.dart`, `lib/core/utils/offline_guard.dart`,
`docs/backlog-grill.md`, `docs/superpowers/specs/2026-09-04-offline-realtime-engine-design.md`.

Backend (code pass, plus `docs/api/openapi.snapshot.json` @ `master`):
`Services/Sync/MobileUserSyncService.cs` + `MobileUserSyncResult.cs` + `SyncScheduleDto.cs`,
`Api/Controllers/SyncController.cs`, `Api/Controllers/TicketsController.cs`,
`Application/.../TicketCommandService.cs`, `ReferentialIntegrityService.cs`,
`Infrastructure/.../Repository.cs`, `ApplicationDbContext.cs`, `Entities/Ticket.cs`,
`Entities/BaseEntity.cs`, the `ContractsController` / `CommesseController` /
`ProdottoAssistenzaController` / `CustomersController` / `UsersController` list endpoints.

## What this document is not

It is not a justification for more offline functionality. It concludes that the offline **write**
model is already correct and should not change, and that the real gap is a **read**-availability
gap of exactly five reference entities, fixable by extending the existing sync contract, existing
Drift, and existing search API — no new architecture. It is also not an implementation plan: the
decisions in §10 (starting with D-1) must be made explicit before any code is written.
