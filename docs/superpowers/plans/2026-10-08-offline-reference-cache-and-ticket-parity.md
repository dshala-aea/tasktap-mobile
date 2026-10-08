# Offline reference cache and ticket parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a technician the reference data a ticket is made of — contract, commessa, product, agent — so the create wizard works offline for the customers their own work already reaches, and reaches everything else through online search that materialises the pick.

**Architecture:** Option E from the spec. Extend the existing `/api/sync/mobile` payload with four scoped entity lists, mirror them in four Drift tables, and add one picker that shows the local mirror and searches the server on demand. No new sync mechanism, no new server tables, no permissions model: the scope is the technician's own work scope (D-1(a)), computed by the traversal `MobileUserSyncService` already performs.

**Tech Stack:** Backend — .NET 8, EF Core, xUnit + FluentAssertions + `UseInMemoryDatabase`. Mobile — Flutter/Dart, Drift (schema 36 → 37), Riverpod, dio, `flutter_test` + `mocktail`.

**Spec:** `mobile/docs/superpowers/specs/2026-10-08-offline-architecture-reanalysis-design.md` (Option E §5, sync design §6, UX contract §7, schema §8, backend §9, decisions §10). Read §2.6–§2.7 first — they correct facts the spec originally asserted, and §2.7 is a live defect this plan fixes.

## Revision note (2026-10-08, second pass)

Five corrections from plan review, each verified against `master` and the mobile tree before applying:

1. **The four reference queries carry NO delta filter.** The first draft applied `(UpdatedAt ?? CreatedAt) > cutoff`, which breaks whenever *scope* changes without the *row* changing — a contract created before the cutoff, whose customer first becomes reachable through a ticket that entered the delta this sync, would be withheld forever. `MobileUserSyncService` already states the governing rule ("reference entities are always full, no delta filter") and re-sends the technician's tickets whole. The new queries follow that rule: the scope, not a timestamp, decides what the phone gets.
2. **Pruning is scoped, not global, and does not depend on `since == null`.** The payload's customer set is recomputed each sync from open assigned work and the schedule window — it is not a snapshot, and the device accumulates. A "prune everything not in the payload" rule would delete an accumulated customer whose last ticket closed. Prune is keyed to the customers the payload actually carries, and never touches agents.
3. **The cursor generation is NOT bumped.** With no delta on the reference entities, a device receives them on its first sync after upgrading; a reset would cost every device a full re-download of all tickets and reports for nothing.
4. **`internalNotes` is dropped from the plan entirely.** `new_ticket_form_state.dart` records that it is office-only and *deliberately* not exposed on mobile. And the picker widget no longer runs the materialise step itself — see Task B4.
5. **Riferimento is confirmed broken, not merely questionable — and it is fixed here.** `step_dettagli_ticket.dart:233-245` fills `agentId` from `TicketApiClient.fetchTechnicians()`, i.e. from **Users** (`/api/users?role=Technician`). `TicketCommandService.cs:100` validates that same field with `EnsureExistsAsync<Agent>(request.AgentId, ct)`, and `Agent` is a separate entity (`Core/Entities/Agent.cs`, restored in W6a from the legacy "Agente") whose ids are not User ids. So any ticket created with a Riferimento **404s with `not_found`** — the same failure class the spec's §2.7 identified. Task B5 re-sources the field from the Agents mirror. The web client has the same defect ("same as web's own TicketCreatePanel", per that file's own comment) and is deliberately left to its own release — see Global Constraints.

## Revision note (2026-10-08, third pass — after B5 landed)

Written after verifying B5 against the code, because B6 as first drafted would have shipped a repair
screen that repairs nothing. Each point is a fact read out of the tree, not a preference.

1. **The repairable set must equal the fields the wizard can actually re-pick *and* write back.**
   B5 built the pickers, so the inventory is now a fact rather than a guess. Present:
   `customerId` and `locationId` (`step_cliente_sede.dart`), `contractId` and `commessaId` (same
   step, added by B5), `assignedUserId` (`step_assegnazione.dart`), `typeId` and `agentId` and
   `prodottoAssistenzaIds` (`step_dettagli_ticket.dart`). **Absent: `cantiereId`** — no wizard step
   contains a cantiere field at all (B5 recorded this; `grep -i cantiere lib/features/ticket/steps/`
   finds none) — and **absent: `statusId`**, which the technician never picks: it is defaulted from
   the default `TicketStatus` at `new_ticket_form_screen.dart:79-92`, so a repair would faithfully
   re-send the very id that was rejected, forever. Both leave `_repairableFields`. The table below
   is corrected accordingly.
2. **A repair is an UPDATE of the existing queue row — not a create, not a PUT.** The plan's Step 7
   said "in the same shape `edit_ticket_screen.dart` already preloads from a server ticket", and
   that shape is the wrong one twice over. `NewTicketFormScreen._onSubmit` calls `queue.create(...)`,
   which *inserts* a second pending row rather than fixing the first; and `EditTicketScreen._save`
   (`edit_ticket_screen.dart:150-166`) sends `title/description/customerId/locationId/typeId/
   priority/dueDate/technicianNotes/agentId/tags` — it carries **none** of `contractId`,
   `commessaId`, `cantiereId`, `prodottoAssistenzaIds`, and `admin_api_client.dart:631-658`
   `updateTicket` has no such parameters to carry them in. Repair therefore needs its own path:
   `TicketCreationQueue.repair(id, …)` writing all columns back to the same row — including
   `contractId`, `commessaId`, `cantiereId` and `prodottoAssistenzaIdsJson`, which B1 added and B5
   now writes — then clearing `repairableField`. No server call is made at repair time.
3. **The repair screen must not preload the blamed field's stale value.** Prefill the offending
   `agentId` and let the technician tap Salva, and the row is written back byte-identical: the flag
   clears, the row rejoins auto-retry, the same 404 lands, the flag is set again. A loop that
   repairs nothing and lies about it. Repair mode drops the blamed field and says why in place
   ("Il riferimento non è più valido: scegline un altro"); every other field preloads unchanged.
   Where the field is required (`customerId`, `locationId`, `typeId`) the wizard's own validation
   then blocks the save until it is re-picked, which is the desired behaviour, not a bug.
4. **Recorded, not fixed here: edit mode discards reference picks (B5 regression).** The same
   `edit_ticket_screen.dart` renders `StepClienteSede` (`:262`) and `StepDettagliTicket` (`:267`),
   which now draw Contratto, Commessa and Prodotti, while `_save` persists none of them — so a
   technician can pick, read "Ticket aggiornato", and have every pick dropped. The server is only
   partly to blame: `UpdateTicketRequest` (`TicketsController.cs:735`) *does* accept `CommessaId`
   (`:746`), `CantiereId` (`:749`) and `ProdottoAssistenzaIds` (`:766`); it does **not** accept
   `ContractId` (its only three occurrences are `:130`, `:227`, `:666`). Wiring the three the server
   takes is a task of its own — `TicketProdottiAssistenza` (`app_database.dart:1006`) is referenced
   nowhere in `lib/`, so there is no provider to seed coverage from, and sending `[]` would wipe a
   ticket's coverage rather than leave it. Sequence after B6; do not bolt it onto B6.

## Global Constraints

- **Two working trees, two branches.** Backend work runs in `/mnt/d/AEA/Sviluppi/TaskTap` (the API repo); mobile work runs in `/mnt/d/AEA/Sviluppi/TaskTap/mobile` (a **nested git repo**, separate history).
- **Backend branches from `master`, never from the current checkout.** The root working tree is on `feat/copilot-domain-correctness`, **51 commits behind `master`**, without the deployed checklist feature at all. Phase A's first step is `git checkout -b feat/offline-reference-sync master`. Read backend files with `git show master:<path>` until that branch exists.
- **Scope is D-1(a): the technician's own work scope.** No tenant-wide list enters the payload. Contracts/commesse/products are scoped to the customer ids the payload already carries; agents to the agent ids the payload's tickets already reference. This is a security property and is tested as one, per entity family.
- **Scope ≠ completeness.** The payload's customer set is *recomputed every sync*, not accumulated, and it is itself delta-filtered in the `fullScope` branch. Both the reference queries and the prune are keyed to the customers **present in this payload**; a customer absent from it is never read and never pruned.
- **The reference mirror is not exclusively passive.** Population has two sources, and comments where they meet must say so:
  - **Passive**: the sync payload, bounded by D-1(a).
  - **Explicit**: an online search the technician ran, whose selected rows are written locally by `ReferenceSearchClient`. This is outside the passive scope, authorised by the technician's own successful server query, and is why a row in these tables need not satisfy the D-1(a) predicate. A future reviewer must not "restore" the invariant by adding a scope filter to the search write path.
- **`IsActive` is carried, never filtered.** A scope predicate that hides inactive rows is the bug this work exists to fix.
- **Old clients ignore new members; new clients must not read a missing member as "empty".** Every new member is gated by a key-presence `carries*` flag, asserted in the contract tests.
- **Never `sed -i`, `perl -i`, or in-place Python on `/mnt/d`** — it silently deletes files on this mount.
- **Git:** explicit-path `git add` only, never `git add -A`. Commit trailers: `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- **Mobile ships on `v*` tags after the user device-tests.** Branch `feat/mobile-asset-checklists` stays unmerged.
- Copy is Italian and matches the existing tone. No English strings in mobile UI.
- **Out of scope, explicitly:** mobile `internalNotes`, `maintenanceTemplateId`, `externalId`, `source`, attachments, any offline write for admin/magazzino, CRDT/vector clocks/tombstone tables, and the web client's identical Riferimento bug (frontend repo, its own release).

## Review Focus

The five inputs most likely to bite a real technician. Each line names the task whose tests pin it.

1. **A reference row that becomes reachable only because the technician's *scope* changed.** A contract created last month, for a customer whose first ticket reaches the phone today: the contract never changed, so a delta filter would withhold it forever and the picker would open empty on a customer the technician can plainly see. → Task A2, the scope-expansion test.
2. **A search result the technician selects that is outside the mirrored scope.** It must exist in the local mirror before the ticket that references it is written, or the ticket fails on a row the technician just picked. → Task B4, where this is structural, not merely tested.
3. **A backend that predates the new members.** It sends none of the four keys; that must not read as "every reference row was deleted". → Tasks B2 and B3.
4. **A technician with no open work** (new hire, or between jobs). The payload carries no customers, so every picker is empty. It must render a labelled state with a way forward, never a dead control. → Task B4.
5. **A queued ticket whose reference row died after drafting.** The send is rejected; the technician must be told which field died and be able to pick a replacement without retyping the ticket — including when the app was not on that screen when the retry failed. → Task B6.

---

# Phase A — Backend

Phase A is independently shippable: the payload extension is additive, old clients ignore it, and A1–A3 ship one backend release before any mobile build consumes it.

**Working directory for every task in this phase:** `/mnt/d/AEA/Sviluppi/TaskTap`.
**Create the branch once, before Task A1:**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap
git fetch origin && git checkout -b feat/offline-reference-sync master
git log --oneline -1
```

---

### Task A1: `q` on the contracts, products and agents list endpoints

**Files:**
- Modify: `src/TaskTapAPI.Api/Controllers/ContractsController.cs` (`GetAll`)
- Modify: `src/TaskTapAPI.Api/Controllers/ProdottoAssistenzaController.cs` (`GetAll`)
- Modify: `src/TaskTapAPI.Api/Controllers/AgentsController.cs` (`GetAll`)
- Test: `tests/TaskTapAPI.Tests/Controllers/ReferenceListSearchTests.cs` (create)

**Interfaces:**
- Consumes: `ListQuery.Q`.
- Produces: nothing new. All three endpoints honour the `q` parameter they already accept.

**Why:** search-on-demand (spec §7.4) is the whole online half of the design. Verified on `master`:
`ContractsController.GetAll`, `ProdottoAssistenzaController.GetAll` and `AgentsController.GetAll` all
bind `ListQuery` and never read `query.Q` — the parameter is silently dropped, so the picker would
claim a search it never performed and show an unfiltered page for a term the technician typed.
`CommesseController` reads it (`:69-70`) and shows the shape to copy, which is also why commesse is
not in this list.

`AgentsController.GetAll` carries `[RequirePermission(PermissionCatalogue.ClientiAgentRead)]`. Leave it
exactly as it is: a technician without that permission gets a 403, the picker falls back to the
mirrored agents (which come from their own tickets and need no permission at all), and Riferimento is
never a required field. The permission gate is a fact for Task B4's comment, not something to relax.

- [ ] **Step 1: Read the three `GetAll` actions and the existing test factory**

```bash
git show master:src/TaskTapAPI.Api/Controllers/ContractsController.cs | sed -n '55,115p'
git show master:src/TaskTapAPI.Api/Controllers/ProdottoAssistenzaController.cs | sed -n '50,115p'
git show master:src/TaskTapAPI.Api/Controllers/AgentsController.cs | sed -n '44,68p'
git show master:src/TaskTapAPI.Api/Controllers/CommesseController.cs | sed -n '60,78p'
git show master:tests/TaskTapAPI.Tests/Controllers/ProdottoAssistenzaControllerTests.cs | sed -n '1,45p'
```

Note each controller's exact constructor argument list and copy the existing test file's SUT factory
verbatim into the new test. Do not reconstruct it from memory.

- [ ] **Step 2: Write the failing test**

```csharp
using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace TaskTapAPI.Tests.Controllers;

/// <summary>
/// The mobile picker's online half is these list endpoints with a `q`. An endpoint that binds
/// ListQuery and drops `query.Q` makes the picker claim a search it never ran, and shows the
/// technician an unfiltered page for a term they typed.
/// </summary>
public class ReferenceListSearchTests : IDisposable
{
    // ... fixture: the SUT factories copied from ProdottoAssistenzaControllerTests.cs, one tenant,
    //     and two contracts + two products on one customer:
    //       Contract "Manutenzione caldaie" / "Assistenza porte"
    //       ProdottoAssistenza "Caldaia Nord" / "Porta garage"
    //     Keep every created id in a field so the assertions can NAME it.

    [Fact]
    public async Task Contracts_list_filters_by_q()
    {
        var page = Unwrap(await ContractsSut().GetAll(new ListQuery { Q = "caldaie" }));

        page.Items.Select(c => c.Id).Should().Equal(_caldaieContractId);
    }

    [Fact]
    public async Task Products_list_filters_by_q()
    {
        var page = Unwrap(await ProductsSut().GetAll(new ListQuery { Q = "caldaia" }));

        page.Items.Select(p => p.Id).Should().Equal(_caldaiaNordId);
    }

    [Fact]
    public async Task Agents_list_filters_by_q()
    {
        var page = Unwrap(await AgentsSut().GetAll(new ListQuery { Q = "rossi" }));

        page.Items.Select(a => a.Id).Should().Equal(_rossiAgentId);
    }

    /// <summary>A whitespace-only term is not a search — it must not narrow the page to nothing,
    /// or clearing the box would empty the picker.</summary>
    [Fact]
    public async Task A_whitespace_q_does_not_filter()
    {
        var page = Unwrap(await ContractsSut().GetAll(new ListQuery { Q = "   " }));

        page.Items.Should().HaveCount(2);
    }
}
```

Assert by **id**, not by count or name — a count of one is also what a broken tenant filter produces.

- [ ] **Step 3: Run it and watch it fail**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~ReferenceListSearchTests`
Expected: FAIL — `Contracts_list_filters_by_q` receives both contracts.

- [ ] **Step 4: Add the filter to all three controllers**

In each `GetAll`, in exactly `CommesseController`'s position — after the existing `if` filters, before
the sort guard — and in its exact shape (`CommesseController.cs:69-70`, verified on `origin/master`):

```csharp
        if (!string.IsNullOrWhiteSpace(query.Q))
            q = q.Where(c => c.Name.Contains(query.Q));
```

Per controller, with the entity's own text columns:

- `ContractsController` → `c.Name` (add `|| (c.Numero != null && c.Numero.Contains(query.Q))` only if the
  file already treats `Numero` as display text; otherwise leave it to `Name` alone).
- `ProdottoAssistenzaController` → `p.Name`.
- `AgentsController` → `a.Nome`.

Three facts to keep in mind, all verified:

- **`Contains` is case-sensitive on Postgres** (`LIKE`), which is what commesse already does. Do not
  reach for `ILike`/`ToLower` here: matching the neighbour is the requirement, and the mobile search
  box sends what the technician typed.
- **In-memory provider is case-sensitive too**, so the test's term must match the fixture's casing
  exactly. `"caldaie"` matches "Manutenzione caldaie"; `"Caldaie"` would not.
- The filter goes **before** the sort guard, not after: `ApplySort` and `ToPaginatedResultAsync` both
  consume the queryable, and a filter applied after pagination would filter one page instead of the set.

- [ ] **Step 5: Run the tests**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~ReferenceListSearchTests`
Expected: PASS, 3/3.

- [ ] **Step 6: Run the neighbouring list suites**

Run: `dotnet test tests/TaskTapAPI.Tests --filter "FullyQualifiedName~ProdottoAssistenzaController|FullyQualifiedName~Pagination|FullyQualifiedName~ContractsController|FullyQualifiedName~AgentsController"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/TaskTapAPI.Api/Controllers/ContractsController.cs \
        src/TaskTapAPI.Api/Controllers/ProdottoAssistenzaController.cs \
        src/TaskTapAPI.Api/Controllers/AgentsController.cs \
        tests/TaskTapAPI.Tests/Controllers/ReferenceListSearchTests.cs
git commit -m "fix(api): honour q on the contracts, products and agents list endpoints

All three bound ListQuery and dropped query.Q, so the mobile picker's on-demand search
would have returned unfiltered pages for three of the four reference entities. Mirrors
the CommesseController filter, which already reads it.

The ClientiAgentRead gate on the agents endpoint is unchanged: a technician without it
falls back to the agents mirrored from their own tickets.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task A2: the four reference entities in the mobile sync payload

**Files:**
- Create: `src/TaskTapAPI.Application/Services/Sync/SyncReferenceDtos.cs`
- Modify: `src/TaskTapAPI.Application/Services/Sync/MobileUserSyncResult.cs`
- Modify: `src/TaskTapAPI.Application/Services/Sync/MobileUserSyncService.cs`
- Test: `tests/TaskTapAPI.Tests/Sync/MobileUserSyncReferenceTests.cs` (create)

**Interfaces:**
- Consumes: the already-materialised `tickets` and `customers` locals inside `GetDeltaAsync` (the `// ── 3. reference entities` block).
- Produces, for the mobile plan — member → wire name → DTO:
  - `Contracts` → `contracts` → `SyncContractDto`
  - `Commesse` → `commesse` → `SyncCommessaDto`
  - `ProdottiAssistenza` → `prodottiAssistenza` → `SyncProdottoAssistenzaDto`
  - `Agents` → `agents` → `SyncAgentDto`

**The rule — implement exactly this:**

- **No delta filter on any of the four.** A timestamp cannot decide this: when a customer first becomes reachable, every unchanged row hanging off them becomes newly reachable with it, and a `> cutoff` test withholds all of them. This matches the rule the file already states for reference entities.
- **Scope, both branches:** `CustomerId ∈ customers.Select(c => c.Id)` for contracts, commesse, prodotti (the payload's own customer list, whichever branch built it); `Id ∈ tickets.Where(t => t.AgentId.HasValue).Select(t => t.AgentId!.Value)` for agents.
- **`IsActive` is projected, never filtered.** Do not add `Where(c => c.IsActive)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/TaskTapAPI.Tests/Sync/MobileUserSyncReferenceTests.cs`. Build the service the way
`MobileUserSyncSubmittedReportsTests.cs` does — over a real `ScheduleAssignmentResolver`, never a
stub, or "this technician's work" is trivially empty and every scoping assertion passes vacuously.

```csharp
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using TaskTapAPI.Application.Services.Sync;
using TaskTapAPI.Core.Entities;
using TaskTapAPI.Infrastructure.Configuration;
using TaskTapAPI.Infrastructure.Context;
using TaskTapAPI.Infrastructure.Data;
using Xunit;

namespace TaskTapAPI.Tests.Sync;

public class MobileUserSyncReferenceTests : IDisposable
{
    private readonly ApplicationDbContext _db;
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _otherTenant = Guid.NewGuid();
    private readonly Guid _techId = Guid.NewGuid();
    private readonly Guid _inScopeCustomer = Guid.NewGuid();
    private readonly Guid _outOfScopeCustomer = Guid.NewGuid();
    private readonly Guid _inScopeLocation = Guid.NewGuid();
    private readonly Guid _outOfScopeLocation = Guid.NewGuid();
    private readonly Guid _inScopeTicket = Guid.NewGuid();
    private readonly Guid _agentId = Guid.NewGuid();
    private readonly Guid _unreferencedAgentId = Guid.NewGuid();
    private readonly Guid _inScopeContract = Guid.NewGuid();
    private readonly Guid _outOfScopeContract = Guid.NewGuid();
    private readonly Guid _foreignContract = Guid.NewGuid();
    private readonly Guid _inScopeCommessa = Guid.NewGuid();
    private readonly Guid _outOfScopeCommessa = Guid.NewGuid();
    private readonly Guid _foreignCommessa = Guid.NewGuid();
    private readonly Guid _inScopeProdotto = Guid.NewGuid();
    private readonly Guid _outOfScopeProdotto = Guid.NewGuid();
    private readonly Guid _foreignProdotto = Guid.NewGuid();

    public MobileUserSyncReferenceTests()
    {
        var tenantContext = new TenantContext();
        tenantContext.SetTenant(_tenantId);
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(
                Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options;
        _db = new ApplicationDbContext(options, tenantContext, new TenantOptions());
        Seed();
    }

    private void Seed()
    {
        var now = DateTime.UtcNow;
        // A year old and never edited. The scope-expansion case depends on these rows being OLD and
        // UNCHANGED — a fresh row would pass a cutoff test by accident and prove nothing.
        var far = now.AddYears(-1);

        _db.Customers.AddRange(
            new Customer { Id = _inScopeCustomer, TenantId = _tenantId, CompanyName = "In scope", CreatedAt = far },
            new Customer { Id = _outOfScopeCustomer, TenantId = _tenantId, CompanyName = "Out of scope", CreatedAt = far });
        _db.Locations.AddRange(
            new Location { Id = _inScopeLocation, TenantId = _tenantId, CustomerId = _inScopeCustomer,
                Name = "Sede", CreatedAt = far },
            new Location { Id = _outOfScopeLocation, TenantId = _tenantId, CustomerId = _outOfScopeCustomer,
                Name = "Altra sede", CreatedAt = far });

        // The ONLY edge that puts _inScopeCustomer on this technician's phone.
        _db.Tickets.Add(new Ticket
        {
            Id = _inScopeTicket, TenantId = _tenantId, CustomerId = _inScopeCustomer,
            LocationId = _inScopeLocation, AssignedUserId = _techId, AgentId = _agentId,
            Title = "Caldaia", StatusId = 1, TypeId = 1, CreatedAt = far,
        });
        _db.Set<Schedule>().Add(new Schedule
        {
            Id = Guid.NewGuid(), TenantId = _tenantId, UserId = _techId, LocationId = _inScopeLocation,
            TicketId = _inScopeTicket, ActivityDate = now.Date, TimeStart = TimeSpan.Zero,
            TimeEnd = TimeSpan.FromHours(1), StatusId = 1, Title = "Intervento", Description = "",
            CreatedAt = far,
        });

        _db.Contracts.AddRange(
            new Contract { Id = _inScopeContract, TenantId = _tenantId, CustomerId = _inScopeCustomer,
                Name = "Contratto in scope", StartDate = far, CreatedAt = far },
            new Contract { Id = _outOfScopeContract, TenantId = _tenantId, CustomerId = _outOfScopeCustomer,
                Name = "Contratto fuori scope", StartDate = far, CreatedAt = far },
            new Contract { Id = _foreignContract, TenantId = _otherTenant, CustomerId = _inScopeCustomer,
                Name = "Altro tenant", StartDate = far, CreatedAt = far });
        _db.Commesse.AddRange(
            new Commessa { Id = _inScopeCommessa, TenantId = _tenantId, CustomerId = _inScopeCustomer,
                Codice = "C-1", CreatedAt = far },
            new Commessa { Id = _outOfScopeCommessa, TenantId = _tenantId, CustomerId = _outOfScopeCustomer,
                Codice = "C-2", CreatedAt = far },
            new Commessa { Id = _foreignCommessa, TenantId = _otherTenant, CustomerId = _inScopeCustomer,
                Codice = "C-3", CreatedAt = far });
        _db.Set<ProdottoAssistenza>().AddRange(
            new ProdottoAssistenza { Id = _inScopeProdotto, TenantId = _tenantId,
                CustomerId = _inScopeCustomer, LocationId = _inScopeLocation, Name = "Caldaia Nord",
                CreatedAt = far },
            new ProdottoAssistenza { Id = _outOfScopeProdotto, TenantId = _tenantId,
                CustomerId = _outOfScopeCustomer, LocationId = _outOfScopeLocation, Name = "Porta",
                CreatedAt = far },
            new ProdottoAssistenza { Id = _foreignProdotto, TenantId = _otherTenant,
                CustomerId = _inScopeCustomer, LocationId = _inScopeLocation, Name = "Altro tenant",
                CreatedAt = far });
        _db.Set<Agent>().AddRange(
            new Agent { Id = _agentId, TenantId = _tenantId, Nome = "Rif. usato", CreatedAt = far },
            new Agent { Id = _unreferencedAgentId, TenantId = _tenantId, Nome = "Rif. mai usato", CreatedAt = far });
        _db.SaveChanges();
    }

    public void Dispose() => _db.Dispose();

    // ... CreateService(): the SUT factory, following MobileUserSyncSubmittedReportsTests.cs.

    [Fact]
    public async Task Each_reference_family_sends_exactly_the_in_scope_row()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Contracts.Select(x => x.Id).Should().Equal(_inScopeContract);
        r.Commesse.Select(x => x.Id).Should().Equal(_inScopeCommessa);
        r.ProdottiAssistenza.Select(x => x.Id).Should().Equal(_inScopeProdotto);
        r.Agents.Select(x => x.Id).Should().Equal(_agentId);
    }

    /// <summary>
    /// The regression the first draft of this plan would have shipped. Every row below is a year
    /// old and has never been edited, so it sits outside any plausible cutoff — but it is reachable
    /// for the first time in THIS sync, because the customer that owns it just entered scope. A
    /// `(UpdatedAt ?? CreatedAt) > cutoff` filter withholds it forever, and the picker opens empty
    /// on a customer the technician can plainly see.
    /// </summary>
    [Fact]
    public async Task An_unchanged_reference_row_arrives_when_its_customer_first_enters_scope()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: DateTime.UtcNow);

        r.Contracts.Select(x => x.Id).Should().Equal(_inScopeContract);
        r.Commesse.Select(x => x.Id).Should().Equal(_inScopeCommessa);
        r.ProdottiAssistenza.Select(x => x.Id).Should().Equal(_inScopeProdotto);
    }

    /// <summary>The same shape one level down: an agent is reachable because a ticket references
    /// it, so an old agent must arrive with the ticket that introduces it, not only when it is
    /// later edited.</summary>
    [Fact]
    public async Task An_unchanged_agent_arrives_with_the_ticket_that_references_it()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: DateTime.UtcNow);

        r.Agents.Select(x => x.Id).Should().Equal(_agentId);
    }

    [Fact]
    public async Task An_agent_no_ticket_references_is_never_sent()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Agents.Select(x => x.Id).Should().NotContain(_unreferencedAgentId);
    }

    [Fact]
    public async Task A_customer_absent_from_the_payload_contributes_no_reference_rows()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Contracts.Select(x => x.Id).Should().NotContain(_outOfScopeContract);
        r.Commesse.Select(x => x.Id).Should().NotContain(_outOfScopeCommessa);
        r.ProdottiAssistenza.Select(x => x.Id).Should().NotContain(_outOfScopeProdotto);
    }

    /// <summary>One cross-tenant case per family. Tenant isolation is not something to infer from
    /// EF's global filter when the row is one query away from a client's cache.</summary>
    [Fact]
    public async Task No_family_sends_another_tenants_row_for_the_same_customer_id()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Contracts.Select(x => x.Id).Should().NotContain(_foreignContract);
        r.Commesse.Select(x => x.Id).Should().NotContain(_foreignCommessa);
        r.ProdottiAssistenza.Select(x => x.Id).Should().NotContain(_foreignProdotto);
        r.Contracts.Select(x => x.TenantId).Should().OnlyContain(t => t == _tenantId);
    }

    [Fact]
    public async Task An_inactive_contract_is_still_sent_with_its_flag()
    {
        var id = Guid.NewGuid();
        _db.Contracts.Add(new Contract
        {
            Id = id, TenantId = _tenantId, CustomerId = _inScopeCustomer, Name = "Cessato",
            StartDate = DateTime.UtcNow.AddYears(-1), IsActive = false, CreatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync();

        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Contracts.Single(c => c.Id == id).IsActive.Should().BeFalse(
            "hiding it is what leaves a deactivated contract in the picker forever (spec 6.4)");
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~MobileUserSyncReferenceTests`
Expected: FAIL to compile — `MobileUserSyncResult` has no `Contracts`/`Commesse`/`ProdottiAssistenza`/`Agents`.

- [ ] **Step 3: Write the DTOs**

Create `src/TaskTapAPI.Application/Services/Sync/SyncReferenceDtos.cs`:

```csharp
namespace TaskTapAPI.Application.Services.Sync;

/// <summary>
/// The reference entities a ticket is made of, shipped to the phone so the create wizard can be
/// filled from the local mirror while offline (spec §6.2, §7.4).
///
/// Scoped, never tenant-wide: contracts, commesse and products are limited to the customers the
/// caller's own payload already carries, and agents to the agents that payload's tickets already
/// reference. Widening any of these is a confidentiality decision, not a sync change (spec §10).
///
/// <c>isActive</c> travels as data and the picker filters on it. A predicate that hides inactive
/// rows makes a deactivation invisible to a device that has already cached the row — the failure
/// spec §6.4 exists to fix. Hard deletes, which no flag can describe, are handled on the client by
/// pruning the customers a payload does carry.
/// </summary>
public sealed record SyncContractDto(
    Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt,
    string Name, Guid CustomerId, Guid? LocationId, DateTime StartDate, DateTime? EndDate,
    bool IsActive, string? Numero, string? Codice, int? Tipo, string? ExternalId);

public sealed record SyncCommessaDto(
    Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt,
    string Codice, string? Descrizione, Guid? CustomerId, bool IsActive,
    string? Stato, string? ExternalId);

public sealed record SyncProdottoAssistenzaDto(
    Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt,
    string Name, Guid CustomerId, Guid LocationId, bool IsActive,
    string? Codice, string? SerialNumber, string? Categoria, string? Marchio, string? ExternalId);

public sealed record SyncAgentDto(
    Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt,
    string Nome, string? Email, string? Cellulare, bool IsActive);
```

> `ProdottoAssistenza` carries `[JsonPropertyName("codice")]` / `("categoria")` / `("marchio")` on
> `Code` / `Category` / `Marca`; these DTO member names are what reach the wire, so the mobile field
> names are `categoria` and `marchio`. That is deliberate — the mobile plan mirrors them.

- [ ] **Step 4: Add the four members to `MobileUserSyncResult`**

After `TicketTypes`:

```csharp
    // ── reference entities (additive; older clients ignore these keys) ───────────────────────────

    /// <summary>Contracts of the customers this payload carries.</summary>
    public IReadOnlyList<SyncContractDto> Contracts { get; init; } = [];

    /// <summary>Commesse of the customers this payload carries.</summary>
    public IReadOnlyList<SyncCommessaDto> Commesse { get; init; } = [];

    /// <summary>Products of the customers this payload carries.</summary>
    public IReadOnlyList<SyncProdottoAssistenzaDto> ProdottiAssistenza { get; init; } = [];

    /// <summary>Agents referenced by this payload's tickets.</summary>
    public IReadOnlyList<SyncAgentDto> Agents { get; init; } = [];
```

- [ ] **Step 5: Load them in `GetDeltaAsync`**

Insert immediately before the final `return new MobileUserSyncResult { ... }`, so `tickets` and
`customers` are already materialised:

```csharp
        // ── 9. reference entities for the ticket wizard ─────────────────────
        //
        // NO delta filter on any of these, and that is the point. `customers` above is recomputed
        // every sync — "the customers behind work currently assigned to this technician", not an
        // accumulated set — so a customer can enter scope while every row hanging off them stays
        // unchanged. A `(UpdatedAt ?? CreatedAt) > cutoff` test would withhold those unchanged rows
        // forever, and the picker would open empty on a customer whose ticket is plainly on the
        // phone. Scoping is by the payload's own customer/ticket ids; timestamps are not consulted.
        //
        // The same reasoning as the tickets block above, which also re-sends its whole set every
        // sync. Size is bounded by the technician's own open work: a handful of customers, and the
        // contracts, commesse and products hanging off them.
        //
        // If any of these lists is ever capped, the client's prune must go with it: a truncated
        // list looks exactly like a deletion, and would delete rows that are merely off the page.
        var scopedCustomerIds = customers.Select(c => c.Id).ToList();
        var scopedAgentIds = tickets
            .Where(t => t.AgentId.HasValue)
            .Select(t => t.AgentId!.Value)
            .Distinct()
            .ToList();

        // IsActive is deliberately NOT filtered: see SyncReferenceDtos.cs.
        var contracts = scopedCustomerIds.Count == 0
            ? []
            : await _db.Contracts
                .Where(c => c.TenantId == tenantId && scopedCustomerIds.Contains(c.CustomerId))
                .ToListAsync();
        var commesse = scopedCustomerIds.Count == 0
            ? []
            : await _db.Commesse
                .Where(c => c.TenantId == tenantId && c.CustomerId.HasValue
                            && scopedCustomerIds.Contains(c.CustomerId.Value))
                .ToListAsync();
        var prodotti = scopedCustomerIds.Count == 0
            ? []
            : await _db.Set<ProdottoAssistenza>()
                .Where(p => p.TenantId == tenantId && scopedCustomerIds.Contains(p.CustomerId))
                .ToListAsync();
        var agents = scopedAgentIds.Count == 0
            ? []
            : await _db.Set<Agent>()
                .Where(a => a.TenantId == tenantId && scopedAgentIds.Contains(a.Id))
                .ToListAsync();
```

and add to the initializer:

```csharp
            Contracts  = [.. contracts.Select(x => new SyncContractDto(
                x.Id, x.TenantId, x.CreatedAt, x.UpdatedAt, x.Name, x.CustomerId, x.LocationId,
                x.StartDate, x.EndDate, x.IsActive, x.Numero, x.Codice,
                x.Tipo.HasValue ? (int)x.Tipo.Value : null, x.ExternalId))],
            Commesse   = [.. commesse.Select(x => new SyncCommessaDto(
                x.Id, x.TenantId, x.CreatedAt, x.UpdatedAt, x.Codice, x.Descrizione, x.CustomerId,
                x.IsActive, x.Stato, x.ExternalId))],
            ProdottiAssistenza = [.. prodotti.Select(x => new SyncProdottoAssistenzaDto(
                x.Id, x.TenantId, x.CreatedAt, x.UpdatedAt, x.Name, x.CustomerId, x.LocationId,
                x.IsActive, x.Code, x.SerialNumber, x.Category, x.Marca, x.ExternalId))],
            Agents     = [.. agents
                .Select(x => new SyncAgentDto(
                    x.Id, x.TenantId, x.CreatedAt, x.UpdatedAt, x.Nome, x.Email, x.Cellulare,
                    x.IsActive))
                .OrderBy(a => a.Nome, StringComparer.OrdinalIgnoreCase)],
```

> `Contract.Tipo` is an enum — cast it. `Contract.Stato` is derived and EF-ignored; do not project
> it.

- [ ] **Step 6: Run the tests**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~MobileUserSyncReferenceTests`
Expected: PASS, 7/7.

- [ ] **Step 7: Run the whole sync suite**

Run: `dotnet test tests/TaskTapAPI.Tests --filter "FullyQualifiedName~Sync|FullyQualifiedName~MobileSyncRoleScope"`
Expected: PASS. The role-scope suite is the HTTP-level tenant-leak gate; a new scoped member must not
open a hole there.

- [ ] **Step 8: Regenerate the committed OpenAPI snapshot**

Regenerate on this branch and report the diff in the hand-off; Task B2 consumes it.

```bash
dotnet build src/TaskTapAPI.Api -c Release
# Regenerate per the repo's existing procedure (see docs/api/), then:
git diff --stat docs/api/openapi.snapshot.json
```

- [ ] **Step 9: Commit**

```bash
git add src/TaskTapAPI.Application/Services/Sync/SyncReferenceDtos.cs \
        src/TaskTapAPI.Application/Services/Sync/MobileUserSyncResult.cs \
        src/TaskTapAPI.Application/Services/Sync/MobileUserSyncService.cs \
        docs/api/openapi.snapshot.json \
        tests/TaskTapAPI.Tests/Sync/MobileUserSyncReferenceTests.cs
git commit -m "feat(sync): ship the reference entities a ticket is made of

contracts, commesse, prodottiAssistenza and agents join the mobile payload, scoped
to the caller's own work: the customers their payload carries, and the agents their
tickets reference.

No delta filter on any of the four, deliberately. The customer set is recomputed
every sync, so a customer can enter scope while every row hanging off them stays
unchanged - a timestamp filter would withhold those rows forever and leave the
picker empty on a customer whose ticket is on the phone. Matches the rule the file
already states for reference entities.

isActive travels as data instead of being filtered, so a deactivation reaches a
device that already cached the row. Additive: older clients ignore the members.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task A3: name the field a rejected ticket FK refers to

**Files:**
- Modify: `src/TaskTapAPI.Core/Exceptions/DomainException.cs` (`NotFoundException`)
- Modify: `src/TaskTapAPI.Application/Services/ReferentialIntegrityService.cs` (interface + both generic guards + both lookup guards)
- Modify: `src/TaskTapAPI.Application/Services/TicketCommandService.cs` (guard call sites, create and update)
- Modify: `src/TaskTapAPI.Api/Middleware/ErrorHandlingMiddleware.cs` (`MapException`)
- Test: `tests/TaskTapAPI.Tests/Services/ReferentialIntegrityFieldTests.cs` (create)
- Test: `tests/TaskTapAPI.Tests/Middleware/` — extend the existing ProblemDetails suite

**Interfaces:**
- Consumes: `ReferentialIntegrityService.EnsureExistsAsync<TEntity>` / `EnsureAllExistAsync<TEntity>` / `EnsureTicketStatusExistsAsync` / `EnsureTicketTypeExistsAsync`.
- Produces, for Task B6: a 404 problem+json body carrying a **flat** `"field"` member — the request body's own camelCase spelling (`"customerId"`) — alongside the existing flat `"code"` (`"not_found"`).
  `ErrorResponse : ProblemDetails` stores extensions in `ProblemDetails.Extensions`, which is
  `[JsonExtensionData]`: on the wire they are members of the **root** object, not nested under an
  `extensions` key. There is no `body["extensions"]["field"]`. Client code reads `body["field"]`.

**Verified facts (from `master`), so do not re-derive them:**

- `NotFoundException` is `sealed`, lives in `src/TaskTapAPI.Core/Exceptions/DomainException.cs`, and takes only `(string message)`. `Status` is 404, `Code` is `"not_found"`.
- The response is built by `ErrorHandlingMiddleware.MapException`, a `switch` on exception type. `NotFoundException` currently falls into `case DomainException d:`.
- `ErrorResponse : ProblemDetails` stores extensions in `ProblemDetails.Extensions`, serialised via `[JsonExtensionData]`. **Extension keys are written literally** — the existing ones are `"correlationId"`, `"code"`, `"conflicts"`, `"missingRequiredControls"`, all camelCase literals. Write `Extensions["field"]`, lowercase.

**Keep the status 404 and keep the message unchanged.** A cross-tenant id must stay
indistinguishable from a missing one; only a machine-readable field name is added, and it goes in
extensions, never in `detail`.

- [ ] **Step 1: Write the failing test**

```csharp
using FluentAssertions;
using TaskTapAPI.Core.Entities;
using TaskTapAPI.Core.Exceptions;
using Xunit;

namespace TaskTapAPI.Tests.Services;

/// <summary>
/// The mobile repair flow needs to know WHICH reference died. It cannot parse the message, and it
/// must not be told anything about the row beyond the field it asked for: a cross-tenant id stays
/// indistinguishable from a missing one.
/// </summary>
public class ReferentialIntegrityFieldTests
{
    // ... fixture: copy the SUT factory from ReferentialIntegrityServiceTests.cs verbatim.

    [Fact]
    public async Task A_missing_customer_names_the_customerId_field()
    {
        var act = async () => await Sut().EnsureExistsAsync<Customer>(Guid.NewGuid(), field: "customerId");

        var ex = await act.Should().ThrowAsync<NotFoundException>();
        ex.Which.Field.Should().Be("customerId");
        ex.Which.Message.Should().Be("Customer not found",
            "the message is logged and asserted by existing tests; only extensions may change");
        ex.Which.Code.Should().Be("not_found");
        ex.Which.Status.Should().Be(System.Net.HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task A_null_id_still_does_not_throw()
    {
        await Sut().EnsureExistsAsync<Customer>(id: null, field: "customerId");
    }

    [Fact]
    public async Task An_unnamed_guard_leaves_the_field_empty()
    {
        var act = async () => await Sut().EnsureExistsAsync<Customer>(Guid.NewGuid());

        (await act.Should().ThrowAsync<NotFoundException>()).Which.Field.Should().BeNull();
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~ReferentialIntegrityFieldTests`
Expected: FAIL to compile — no `field` parameter; no `Field` property.

- [ ] **Step 3: Add the property and the parameters**

In `DomainException.cs`:

```csharp
public sealed class NotFoundException : DomainException
{
    public override HttpStatusCode Status => HttpStatusCode.NotFound;
    public override string Code => "not_found";

    /// <summary>
    /// The request field whose value failed to resolve, in the request body's own camelCase
    /// spelling ("customerId"), or null when the caller did not name one.
    /// <para>
    /// Deliberately not part of <see cref="Exception.Message"/>: the message is logged and asserted
    /// by existing tests, and the client that needs this is reading a machine field, not prose. It
    /// names a FIELD OF THE REQUEST, never anything about the row that was (or was not) found, so it
    /// cannot tell a caller whether some id exists in another tenant.
    /// </para>
    /// </summary>
    public string? Field { get; }

    public NotFoundException(string message, string? field = null) : base(message) => Field = field;
}
```

Then add `string? field = null` as the last parameter of all four interface methods and their
implementations, carrying it into each `throw new NotFoundException(..., field)`.

- [ ] **Step 4: Name the field at every ticket call site**

In `TicketCommandService`, both the create and the update guard block:

```csharp
        await _referentialIntegrity.EnsureExistsAsync<Customer>(request.CustomerId, ct, "customerId");
        await _referentialIntegrity.EnsureExistsAsync<Location>(request.LocationId, ct, "locationId");
        await _referentialIntegrity.EnsureExistsAsync<User>(request.AssignedUserId, ct, "assignedUserId");
        await _referentialIntegrity.EnsureExistsAsync<Contract>(request.ContractId, ct, "contractId");
        await _referentialIntegrity.EnsureAllExistAsync<ProdottoAssistenza>(
            request.ProdottoAssistenzaIds, ct, "prodottoAssistenzaIds");
        await _referentialIntegrity.EnsureExistsAsync<Agent>(request.AgentId, ct, "agentId");
        await _referentialIntegrity.EnsureExistsAsync<Commessa>(request.CommessaId, ct, "commessaId");
        await _referentialIntegrity.EnsureExistsAsync<Cantiere>(request.CantiereId, ct, "cantiereId");
        await _referentialIntegrity.EnsureTicketStatusExistsAsync(request.StatusId, tenantId, ct, "statusId");
        await _referentialIntegrity.EnsureTicketTypeExistsAsync(request.TypeId, tenantId, ct, "typeId");
```

The status and type guards are named too: they are repairable by re-picking, and leaving them
anonymous costs the technician the same retype.

- [ ] **Step 5: Surface it in the middleware**

Add a case **before** the generic `case DomainException d:` arm — a later arm is never reached:

```csharp
            // A rejected foreign key is a 404 like any other and stays indistinguishable from a
            // missing row — but the client that has to repair a queued ticket needs to know which
            // of its fields died, and cannot read the message. Field lives in extensions so it
            // never reaches `detail`.
            case NotFoundException nf:
            {
                var response = new ErrorResponse
                {
                    Type = $"urn:tasktap:error:{nf.Code}",
                    Title = ((HttpStatusCode)(int)nf.Status).ToString(), Status = (int)nf.Status,
                    Detail = nf.Message, Code = nf.Code, CorrelationId = correlationId,
                };
                if (nf.Field is { } field) response.Extensions["field"] = field;
                return ((int)nf.Status, response);
            }
```

Match the file's existing qualification style (it currently fully-qualifies these types).

- [ ] **Step 6: Run the tests**

Run: `dotnet test tests/TaskTapAPI.Tests --filter "FullyQualifiedName~ReferentialIntegrity|FullyQualifiedName~ProblemDetails|FullyQualifiedName~TicketCommandService"`
Expected: PASS. `ProblemDetailsTests` / `StructuredProblemMappingTests` pin the 404 body shape and must
stay green; if one asserts an exact extension set, extend it rather than loosening it.

- [ ] **Step 7: Commit**

```bash
git add src/TaskTapAPI.Core/Exceptions/DomainException.cs \
        src/TaskTapAPI.Application/Services/ReferentialIntegrityService.cs \
        src/TaskTapAPI.Application/Services/TicketCommandService.cs \
        src/TaskTapAPI.Api/Middleware/ErrorHandlingMiddleware.cs \
        tests/TaskTapAPI.Tests/Services/ReferentialIntegrityFieldTests.cs \
        tests/TaskTapAPI.Tests/Middleware/
git commit -m "feat(api): name the offending field on a rejected ticket foreign key

A rejected FK stays a 404 indistinguishable from a missing row - status and message
are unchanged, and existing tests pin them - but the body now carries the request
field that failed to resolve, in extensions. A phone repairing a queued ticket
cannot parse a message and must not be told anything about the row it asked for.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Phase A gate

Run the whole backend suite and record the totals in the ledger:

```bash
dotnet test tests/TaskTapAPI.Tests
```

Then review the phase as one unit: the payload contract, the scope predicate, and the problem+json
shape are the interfaces the mobile plan is written against, and a mistake in any of them is
expensive to find from the far end.

---

# Phase B — Mobile

**Working directory for every task in this phase:** `/mnt/d/AEA/Sviluppi/TaskTap/mobile`.
Every path below is relative to it. `mobile/` is a nested repo: commit there, never from the root.

---

### Task B1: Drift schema 37 — four reference tables and the queue columns the wizard needs

**Files:**
- Modify: `lib/data/local/app_database.dart` (tables, `@DriftDatabase` list, `schemaVersion`, `onCreate`, `onUpgrade`)
- Create: `test/data/local/migration_v37_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: four Drift tables — `contracts`, `commesse`, `prodotti_assistenza`, `agents` — and five new
  columns on `pending_tickets`: `contractId`, `commessaId`, `cantiereId`, `prodottoAssistenzaIdsJson`,
  `repairableField`.

**No cursor bump.** `syncCursorGeneration` stays `'v9'`, and the existing assertion in
`test/data/sync/sync_service_checklist_test.dart` stays exactly as it is. The reference queries carry
no delta filter (Task A2), so a device receives them on its first ordinary sync after upgrading; a
generation reset would cost every device a full re-download of all tickets and reports and buy
nothing. The `pending_tickets` columns are client-authored, like every other column on that table
(see the schema-33 step's own comment). Leave the `v9` expectation in place — it is now the guard
that this release deliberately does not reset every device.

- [ ] **Step 1: Write the failing migration test**

Mirror `test/data/local/migration_v36_test.dart` — build the current schema in a file database,
remove exactly what the step adds, rewind `user_version`, reopen so Drift runs the real
`onUpgrade(36 -> 37)` against a database that really lacks the objects, with pre-existing rows.

```dart
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 36 -> 37: the reference mirror the ticket wizard needs offline (contracts, commesse,
/// prodotti assistenza, agents) and the queue columns that let a created ticket carry them.
///
/// Same technique as migration_v36_test.dart: build the current schema, remove exactly what the
/// step adds, rewind user_version, reopen so Drift runs the real onUpgrade(36 -> 37) against a
/// database that really lacks the objects, with pre-existing rows.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig37_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const newTables = ['contracts', 'commesse', 'prodotti_assistenza', 'agents'];

  Future<List<String>> master(AppDatabase db, String type) async =>
      (await db.customSelect("SELECT name FROM sqlite_master WHERE type = '$type'").get())
          .map((r) => r.read<String>('name'))
          .toList();

  Future<List<String>> columnsOf(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((r) => r.read<String>('name'))
          .toList();

  /// A v36 database: everything the step adds is undone, then user_version is rewound so the
  /// real onUpgrade runs on reopen.
  Future<AppDatabase> reopenAsV36() async {
    final reopened = AppDatabase(
      NativeDatabase(file, setup: (raw) {
        for (final t in newTables) {
          raw.execute('DROP TABLE IF EXISTS $t');
        }
        for (final c in ['contract_id', 'commessa_id', 'cantiere_id',
                         'prodotto_assistenza_ids_json', 'repairable_field']) {
          raw.execute('ALTER TABLE pending_tickets DROP COLUMN $c');
        }
        raw.execute('PRAGMA user_version = 36');
      }),
    );
    addTearDown(reopened.close);
    // Force the open + migration.
    await (reopened.select(reopened.customers)..limit(1)).get();
    return reopened;
  }

  test('a v36 database upgraded to 37 gains the four reference tables', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    await db.close();

    final reopened = await reopenAsV36();

    expect(await master(reopened, 'table'), containsAll(newTables));
  });

  test('the queue columns are added to an existing pending ticket, null for a row that predates '
      'them', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.into(db.pendingTickets).insert(
          PendingTicketsCompanion.insert(
            id: 'queued-1', title: 'Caldaia', customerId: 'cu', locationId: 'l',
            statusId: 1, typeId: 1, createdAt: DateTime.utcNow(),
          ),
        );
    await db.close();

    final reopened = await reopenAsV36();

    expect(await columnsOf(reopened, 'pending_tickets'), containsAll(
        ['contract_id', 'commessa_id', 'cantiere_id', 'prodotto_assistenza_ids_json',
         'repairable_field']));
    final row = (await reopened.select(reopened.pendingTickets).get()).single;
    expect(row.id, 'queued-1', reason: 'spec 11.3: a schema bump must not touch queued work');
    expect(row.contractId, isNull);
  });

  /// The release deliberately does not reset every device's delta cursor - the reference queries
  /// carry no delta, so there is nothing a reset would fetch. This test is the guard on that
  /// decision, not a formality.
  test('the sync cursor generation is deliberately not bumped', () {
    expect(AppDatabase.syncCursorGeneration, 'v9');
  });
}
```

> Check `PendingTicketsCompanion.insert`'s real required set in `app_database.dart` before running —
> the argument list above follows the table declaration at `:756-795`. `ALTER TABLE ... DROP COLUMN`
> needs SQLite 3.35+; the test suite already runs on a version that supports it (verify with
> `PRAGMA user_version`/`sqlite_version()` if the drop fails).

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/local/migration_v37_test.dart`
Expected: FAIL — the tables and columns do not exist.

- [ ] **Step 3: Declare the four tables**

In `lib/data/local/app_database.dart`, following the `Customers` shape (`:28-48`) — no `tableName`
override, Drift derives the snake_case name:

```dart
/// Contracts of the customers this technician's payload carries. Mirrored so the ticket wizard's
/// Cliente→Contratto picker is filled offline (spec 7.4).
///
/// `isActive` is carried, not filtered: a contract deactivated on the server must arrive here as a
/// row with a false flag, or a device that cached it would offer it forever (spec 6.4).
class Contracts extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text().nullable()_();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// `numero` and `codice` are both human references a technician may read off the paper contract;
  /// the picker shows whichever is present.
  TextColumn get numero => text().nullable()();
  TextColumn get codice => text().nullable()();
  IntColumn get tipo => integer().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Commesse (`codice`, `descrizione`) of the customers this technician's payload carries.
class Commesse extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get codice => text()();
  TextColumn get descrizione => text().nullable()();
  TextColumn get customerId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get stato => text().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Products / services (`ProdottoAssistenza`) of the customers this technician's payload carries.
///
/// Deliberately separate from [Assets], which mirrors the *covered* assets of this technician's
/// tickets for the checklist feature and is pruned by `checklist_reconciler`. Two scopes, two
/// lifecycles: this table answers "what can I pick for this customer", that one answers "what did
/// this ticket cover". Merging them would put the ticket form in the hands of the checklist pruner.
class ProdottiAssistenza extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Wire names follow the entity's own JsonPropertyName attributes: codice / categoria / marchio.
  TextColumn get codice => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get categoria => text().nullable()();
  TextColumn get marchio => text().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Agents, mirrored only for the ones this technician's tickets already reference — the
/// "Riferimento" field. A tenant-wide agent book is explicitly not mirrored (spec 10, D-1(a)).
class Agents extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get nome => text()();
  TextColumn get email => text().nullable()();
  TextColumn get cellulare => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: Add the five queue columns**

In the `PendingTickets` table, after `agentId`:

```dart
  /// Reference fields the create wizard now collects, sent on the wire by [TicketApiClient].
  /// Null for every ticket queued before this column existed — and legal, since none of them is
  /// required to create a ticket.
  TextColumn get contractId => text().nullable()();
  TextColumn get commessaId => text().nullable()();
  TextColumn get cantiereId => text().nullable()();

  /// Covered products, JSON-encoded — same storage as [Tickets.tagsJson] (its doc comment has the
  /// reasoning). A JSON list rather than a join table because nothing reads it relationally: it is
  /// carried to the server verbatim and never queried by id.
  TextColumn get prodottoAssistenzaIdsJson => text().nullable()();

  /// The request field a rejected foreign key referred to ("customerId"), set when the server
  /// answered 404 with `extensions.field` and the row is now repairable by picking a replacement
  /// (see [TicketCreationQueue]). Null when the row is not waiting on a repair — the honest answer
  /// for every row written before this column existed.
  TextColumn get repairableField => text().nullable()();
```

- [ ] **Step 5: Register the tables, bump the version, add the migration step**

Add the four classes to the `@DriftDatabase(tables: [...])` list after `ChecklistOmittedTickets`, set
`int get schemaVersion => 37;`, and append after the `from < 36` block:

```dart
        if (from < 37) {
          // The reference mirror the ticket wizard needs offline, plus the queue columns that let a
          // created ticket carry them. New tables and client-authored columns: nothing is backfilled
          // and the delta cursor is NOT bumped — the reference queries carry no delta, so a device
          // receives them on its next ordinary sync. See this file's schema-33 step for the same
          // reasoning about client-authored columns.
          await m.createTable(contracts);
          await m.createTable(commesse);
          await m.createTable(prodottiAssistenza);
          await m.createTable(agents);
          await _createReferenceIndexes();

          await m.addColumn(pendingTickets, pendingTickets.contractId);
          await m.addColumn(pendingTickets, pendingTickets.commessaId);
          await m.addColumn(pendingTickets, pendingTickets.cantiereId);
          await m.addColumn(pendingTickets, pendingTickets.prodottoAssistenzaIdsJson);
          await m.addColumn(pendingTickets, pendingTickets.repairableField);
        }
```

Add the helper next to `_createChecklistIndexes`, and call it from `onCreate` as well:

```dart
  /// Indexes the reference pickers read by: every one of them is "the rows for this customer".
  Future<void> _createReferenceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS contracts_customer ON contracts (customer_id, is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS commesse_customer ON commesse (customer_id, is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS prodotti_assistenza_customer '
      'ON prodotti_assistenza (customer_id, is_active)',
    );
  }
```

- [ ] **Step 6: Regenerate the Drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 7: Run the migration, database and sync suites**

Run: `flutter test test/data/local/ test/data/sync/`
Expected: PASS. If `migration_v36_test.dart` or `app_database_test.dart` assert the schema version
directly, relax them the way `migration_v35_test.dart` was relaxed for v36 (assert `>=`, not `==`)
and note it in the ledger.

- [ ] **Step 8: Commit**

```bash
git add lib/data/local/app_database.dart lib/data/local/app_database.g.dart \
        test/data/local/migration_v37_test.dart
git commit -m "feat(mobile): Drift schema 37 - the reference mirror and the queue columns

contracts, commesse, prodotti_assistenza and agents, plus the pending_tickets
columns a created ticket needs to carry them (contractId, commessaId, cantiereId,
prodottoAssistenzaIdsJson, repairableField).

The delta cursor is deliberately NOT bumped: the reference queries carry no delta,
so a device receives them on its next ordinary sync, and a reset would cost every
device a full re-download for nothing.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B2: parse the four members, and never read a missing one as empty

**Files:**
- Modify: `lib/data/sync/sync_dto.dart`
- Test: `test/data/sync/sync_reference_dto_test.dart` (create)
- Test: `test/contract/sync_inbound_contract_test.dart`

**Interfaces:**
- Consumes: the wire members from Task A2 — `contracts`, `commesse`, `prodottiAssistenza`, `agents`.
- Produces: `ContractSyncDto`, `CommessaSyncDto`, `ProdottoAssistenzaSyncDto`, `AgentSyncDto`, and on
  `SyncResultDto` the members `contracts`, `commesse`, `prodottiAssistenza`, `agents` plus the flags
  `carriesContracts`, `carriesCommesse`, `carriesProdottiAssistenza`, `carriesAgents`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

void main() {
  // The full member set a current backend sends. Build this from sync_dto.dart's own required
  // members — if a new required member lands, this helper must be updated with it, which is the
  // point of writing it out rather than using `{}`.
  Map<String, dynamic> minimal() => {
    'syncedAt': '2026-10-08T08:00:00Z',
    'since': null,
    'schedules': <Object>[], 'draftReports': <Object>[], 'customers': <Object>[],
    'locations': <Object>[], 'tickets': <Object>[], 'materiali': <Object>[],
    'cantieri': <Object>[], 'ticketStatuses': <Object>[], 'ticketTypes': <Object>[],
    'colleagues': <Object>[],
  };

  test('the four reference members parse', () {
    final p = SyncResultDto.fromJson({
      ...minimal(),
      'contracts': [
        {'id': 'c1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
         'name': 'Manutenzione', 'customerId': 'cu', 'locationId': null,
         'startDate': '2026-01-01T00:00:00Z', 'endDate': null, 'isActive': true,
         'numero': 'N-1', 'codice': null, 'tipo': 0, 'externalId': null},
      ],
      'commesse': [
        {'id': 'm1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
         'codice': 'C-1', 'descrizione': null, 'customerId': 'cu', 'isActive': true,
         'stato': null, 'externalId': null},
      ],
      'prodottiAssistenza': [
        {'id': 'p1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
         'name': 'Caldaia', 'customerId': 'cu', 'locationId': 'l', 'isActive': true,
         'codice': 'P-1', 'serialNumber': null, 'categoria': null, 'marchio': null,
         'externalId': null},
      ],
      'agents': [
        {'id': 'a1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
         'nome': 'Rossi', 'email': null, 'cellulare': null, 'isActive': true},
      ],
    });

    expect(p.contracts.single.name, 'Manutenzione');
    expect(p.contracts.single.tipo, 0);
    expect(p.commesse.single.codice, 'C-1');
    expect(p.prodottiAssistenza.single.categoria, isNull);
    expect(p.agents.single.nome, 'Rossi');
    expect([p.carriesContracts, p.carriesCommesse, p.carriesProdottiAssistenza, p.carriesAgents],
        [true, true, true, true]);
  });

  /// The discipline the checklist members already established, and the reason the scoped prune is
  /// safe: a backend that predates this feature sends none of the four keys, and the client must
  /// treat that as "nothing to say", not as "every reference row was deleted".
  test('an older backend leaves every carries flag false', () {
    final p = SyncResultDto.fromJson(minimal());

    expect([p.carriesContracts, p.carriesCommesse, p.carriesProdottiAssistenza, p.carriesAgents],
        [false, false, false, false]);
    expect(p.contracts, isEmpty);
  });

  test('a missing isActive defaults to active, matching the server default', () {
    final p = SyncResultDto.fromJson({
      ...minimal(),
      'agents': [
        {'id': 'a1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
         'nome': 'Rossi', 'email': null, 'cellulare': null},
      ],
    });

    expect(p.agents.single.isActive, isTrue);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/sync/sync_reference_dto_test.dart`
Expected: FAIL — `contracts` is not a member of `SyncResultDto`.

- [ ] **Step 3: Add the four DTOs**

In `lib/data/sync/sync_dto.dart`, following the `CantiereDto` shape and using the file's shared
`_dt` / `_list` helpers:

```dart
/// A contract of a customer in this technician's payload. Mirrored for the Cliente→Contratto picker
/// (spec 7.4). [isActive] is stored, never filtered here — the picker is what hides a deactivated
/// contract.
class ContractSyncDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String name;
  final String customerId;
  final String? locationId;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final String? numero;
  final String? codice;
  final int? tipo;
  final String? externalId;

  const ContractSyncDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.name,
    required this.customerId,
    this.locationId,
    required this.startDate,
    this.endDate,
    this.isActive = true,
    this.numero,
    this.codice,
    this.tipo,
    this.externalId,
  });

  factory ContractSyncDto.fromJson(Map<String, dynamic> j) => ContractSyncDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    name: j['name'] as String,
    customerId: j['customerId'] as String,
    locationId: j['locationId'] as String?,
    startDate: DateTime.parse(j['startDate'] as String),
    endDate: _dt(j['endDate']),
    isActive: j['isActive'] as bool? ?? true,
    numero: j['numero'] as String?,
    codice: j['codice'] as String?,
    tipo: j['tipo'] as int?,
    externalId: j['externalId'] as String?,
  );
}
```

Add `CommessaSyncDto`, `ProdottoAssistenzaSyncDto` and `AgentSyncDto` in the same shape — one field per
member of the record it mirrors in `SyncReferenceDtos.cs` (Task A2). `isActive` defaults to `true` when
the key is absent, matching the server's own default.

- [ ] **Step 4: Add the members and the carries flags to `SyncResultDto`**

Members, with `const []` defaults, and in `fromJson`:

```dart
      contracts: _list(j['contracts'], ContractSyncDto.fromJson),
      commesse: _list(j['commesse'], CommessaSyncDto.fromJson),
      prodottiAssistenza: _list(j['prodottiAssistenza'], ProdottoAssistenzaSyncDto.fromJson),
      agents: _list(j['agents'], AgentSyncDto.fromJson),
```

Flags, by key presence, exactly as `carriesChecklist` is:

```dart
      carriesContracts: j.containsKey('contracts'),
      carriesCommesse: j.containsKey('commesse'),
      carriesProdottiAssistenza: j.containsKey('prodottiAssistenza'),
      carriesAgents: j.containsKey('agents'),
```

with the doc comment:

```dart
  /// False when the payload came from a backend that predates the reference members. Without these
  /// an older backend would look like "every contract, commessa and product was deleted" and the
  /// scoped prune would wipe the mirror. One flag per entity rather than one for the group: each is
  /// pruned independently, and a partial rollout must not be read as a deletion.
  final bool carriesContracts;
  final bool carriesCommesse;
  final bool carriesProdottiAssistenza;
  final bool carriesAgents;
```

Add the four keys to the existing `checklistWireKeys`-style registry if one exists.

- [ ] **Step 5: Extend the contract test**

In `test/contract/sync_inbound_contract_test.dart`, extend the carries-flag assertions with the four
new flags, using the same `full` / `older` pair the file already builds:

```dart
        expect(full.carriesContracts, isTrue);
        expect(full.carriesCommesse, isTrue);
        expect(full.carriesProdottiAssistenza, isTrue);
        expect(full.carriesAgents, isTrue);
        // ... and in the older-backend case:
        expect(older.carriesContracts, isFalse,
            reason: 'an older backend must NOT look like "every contract was deleted"');
```

Refresh `test/contract/openapi.snapshot.json` from the Task A2 snapshot, copied from the backend
branch explicitly — never from the root working tree, which is a different branch's contract.

- [ ] **Step 6: Run the DTO and contract suites**

Run: `flutter test test/data/sync/ test/contract/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/data/sync/sync_dto.dart \
        test/data/sync/sync_reference_dto_test.dart \
        test/contract/sync_inbound_contract_test.dart \
        test/contract/openapi.snapshot.json
git commit -m "feat(mobile): parse the reference sync members behind four carries flags

A backend that predates the members sends none of the keys; without the flags that
reads as \"every contract, commessa and product was deleted\".

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B3: write the reference rows, and prune only what the payload can vouch for

**Files:**
- Create: `lib/data/reference/reference_cache_repository.dart`
- Modify: `lib/data/sync/sync_service.dart`
- Test: `test/data/reference/reference_cache_repository_test.dart` (create)
- Test: `test/data/sync/sync_reference_test.dart` (create)

**Interfaces:**
- Consumes: `ContractSyncDto`, `CommessaSyncDto`, `ProdottoAssistenzaSyncDto`, `AgentSyncDto` (Task B2); the four Drift tables (Task B1).
- Produces, for Task B4 and Task B5:
  - `ReferenceCacheRepository(AppDatabase db)`
  - `Future<void> upsertContracts(Iterable<ContractSyncDto> rows)` — and `upsertCommesse`, `upsertProdottiAssistenza`, `upsertAgents`
  - `Future<void> pruneContracts({required Set<String> presentCustomerIds, required Set<String> keepContractIds})` — and `pruneCommesse`, `pruneProdottiAssistenza`
  - `Future<List<Contract>> contractsForCustomer(String customerId)` — and `commesseForCustomer`, `prodottiForCustomer`, `activeAgents()`
  - `final referenceCacheProvider = Provider<ReferenceCacheRepository>(...)`

**The persistence invariant, which Task B4 depends on:** `upsert*` and `prune*` are called from exactly
two places — `SyncService` (the payload) and `ReferenceSearchClient` (a search the technician ran).
No widget and no screen calls them, and no screen knows how a search result becomes a Drift row.

**Pruning rules, and why they are not "delete what the payload omits":**

- The payload's customer set is recomputed each sync and the device accumulates it. A customer absent
  from this payload is not deleted from the server — they are simply not the subject of this sync. So
  a reference row is prunable only when **its own customer is present in the payload** and that
  customer no longer has the row. That is the only case in which "absent" is evidence of "gone".
- **Agents are never pruned.** An agent can be absent from the payload simply because no ticket in
  *this* payload references them, while a ticket already on the device still does. Deleting it would
  break a ticket the technician can still open.

- [ ] **Step 1: Write the failing repository test**

```dart
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

void main() {
  late AppDatabase db;
  late ReferenceCacheRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = ReferenceCacheRepository(db);
  });
  tearDown(() => db.close());

  ContractSyncDto contract(String id, String customerId, {String? name, bool active = true}) =>
      ContractSyncDto(
        id: id, tenantId: 't', createdAt: DateTime.utcNow(), name: name ?? id,
        customerId: customerId, startDate: DateTime.utcNow(), isActive: active,
      );

  test('contractsForCustomer returns only that customer, only active, in name order', () async {
    await repo.upsertContracts([
      contract('c1', 'cu1', name: 'Zeta'),
      contract('c2', 'cu1', name: 'Alfa'),
      contract('c3', 'cu1', name: 'Cessato', active: false),
      contract('c4', 'cu2', name: 'Altro cliente'),
    ]);

    final rows = await repo.contractsForCustomer('cu1');

    expect(rows.map((r) => r.name), ['Alfa', 'Zeta']);
  });

  test('prune removes a deleted contract of a customer the payload carries', () async {
    await repo.upsertContracts([contract('c1', 'cu1'), contract('c2', 'cu1')]);

    await repo.pruneContracts(presentCustomerIds: {'cu1'}, keepContractIds: {'c1'});

    expect((await repo.contractsForCustomer('cu1')).map((r) => r.id), ['c1']);
  });

  /// The customer is not in the payload, so this sync says nothing about them — and the device
  /// must not guess. This is the case a "delete everything the payload omits" rule gets wrong.
  test('prune never touches a customer the payload does not carry', () async {
    await repo.upsertContracts([contract('c9', 'cu-absent')]);

    await repo.pruneContracts(presentCustomerIds: {'cu1'}, keepContractIds: {});

    expect((await repo.contractsForCustomer('cu-absent')).map((r) => r.id), ['c9']);
  });

  /// An empty keep-set is not an exotic case: a customer whose last contract was hard-deleted
  /// produces exactly it, and it is the one shape where a naive NOT IN list is empty.
  test('prune with an empty keep-set clears that customer and nothing else', () async {
    await repo.upsertContracts([contract('c1', 'cu1'), contract('c9', 'cu-absent')]);

    await repo.pruneContracts(presentCustomerIds: {'cu1'}, keepContractIds: {});

    expect(await repo.contractsForCustomer('cu1'), isEmpty);
    expect((await repo.contractsForCustomer('cu-absent')).map((r) => r.id), ['c9']);
  });

  test('an empty present-set prunes nothing', () async {
    await repo.upsertContracts([contract('c1', 'cu1')]);

    await repo.pruneContracts(presentCustomerIds: {}, keepContractIds: {});

    expect((await repo.contractsForCustomer('cu1')).map((r) => r.id), ['c1']);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/reference/reference_cache_repository_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the repository**

```dart
/// The four reference tables, read and written in one place.
///
/// The sync writes them from the payload; [ReferenceSearchClient] writes them again when a
/// technician picks a row an online search found (spec 7.4). Both go through these same upserts, so
/// a row materialised by a pick is indistinguishable from one the payload delivered.
///
/// Nothing above this layer knows how a reference row is stored: screens and widgets ask for rows
/// and hand back ids. See the class's callers — there are two, and neither is a widget.
class ReferenceCacheRepository {
  ReferenceCacheRepository(this._db);

  final AppDatabase _db;

  Future<void> upsertContracts(Iterable<ContractSyncDto> rows) async {
    for (final c in rows) {
      await _db.into(_db.contracts).insertOnConflictUpdate(
            ContractsCompanion(   // see ContractsCompanion.insert: required fields are the
                                  // non-nullable columns, the rest carry Value(...)
              id: Value(c.id), tenantId: Value(c.tenantId), createdAt: Value(c.createdAt),
              updatedAt: Value(c.updatedAt), name: Value(c.name), customerId: Value(c.customerId),
              locationId: Value(c.locationId), startDate: Value(c.startDate),
              endDate: Value(c.endDate), isActive: Value(c.isActive), numero: Value(c.numero),
              codice: Value(c.codice), tipo: Value(c.tipo), externalId: Value(c.externalId),
            ),
          );
    }
  }

  // upsertCommesse / upsertProdottiAssistenza / upsertAgents in the same shape.

  /// Deletes the rows of the customers this payload carries that the payload no longer lists for
  /// them — the only case where an absence is evidence of a deletion. A customer the payload does
  /// not carry is left alone: this sync has nothing to say about them, and the device accumulates
  /// across syncs (see the class doc comment).
  ///
  /// The empty keep-set is handled explicitly: it is what a customer whose last contract was
  /// deleted produces, and it is exactly the shape where a generated NOT IN list would be empty.
  Future<void> pruneContracts({
    required Set<String> presentCustomerIds,
    required Set<String> keepContractIds,
  }) async {
    if (presentCustomerIds.isEmpty) return;
    await (_db.delete(_db.contracts)..where((t) {
          final inScope = t.customerId.isIn(presentCustomerIds);
          return keepContractIds.isEmpty ? inScope : inScope & t.id.isNotIn(keepContractIds);
        }))
        .go();
  }

  // pruneCommesse / pruneProdottiAssistenza in the same shape.
  // There is deliberately no pruneAgents: an agent absent from one payload may still be referenced
  // by a ticket already on this device, and deleting it would break that ticket.

  Future<List<Contract>> contractsForCustomer(String customerId) =>
      (_db.select(_db.contracts)
            ..where((c) => c.customerId.equals(customerId) & c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  // commesseForCustomer / prodottiForCustomer / activeAgents in the same shape.
}

final referenceCacheProvider = Provider<ReferenceCacheRepository>(
  (ref) => ReferenceCacheRepository(ref.watch(appDatabaseProvider)),
);
```

- [ ] **Step 4: Wire it into `SyncService.sync()`**

In the transaction, after `_replaceColleagues(payload.colleagues)`:

```dart
      await _applyReferenceCache(payload);
```

and, next to `_applyChecklist`:

```dart
  /// The reference mirror. Each entity is skipped wholesale when the payload does not carry it —
  /// an older backend must not look like "every reference row was deleted" — and pruned only for
  /// the customers this payload actually carries. See [ReferenceCacheRepository].
  Future<void> _applyReferenceCache(SyncResultDto payload) async {
    final cache = ReferenceCacheRepository(db);

    if (payload.carriesContracts) {
      await cache.upsertContracts(payload.contracts);
      await cache.pruneContracts(
        presentCustomerIds: payload.customers.map((c) => c.id).toSet(),
        keepContractIds: payload.contracts.map((c) => c.id).toSet(),
      );
    }
    if (payload.carriesCommesse) {
      await cache.upsertCommesse(payload.commesse);
      await cache.pruneCommesse(
        presentCustomerIds: payload.customers.map((c) => c.id).toSet(),
        keepCommessaIds: payload.commesse.map((c) => c.id).toSet(),
      );
    }
    if (payload.carriesProdottiAssistenza) {
      await cache.upsertProdottiAssistenza(payload.prodottiAssistenza);
      await cache.pruneProdottiAssistenza(
        presentCustomerIds: payload.customers.map((c) => c.id).toSet(),
        keepProdottiIds: payload.prodottiAssistenza.map((p) => p.id).toSet(),
      );
    }
    if (payload.carriesAgents) {
      // No prune: see ReferenceCacheRepository.
      await cache.upsertAgents(payload.agents);
    }
  }
```

> `pruneContracts` keys on the **payload's customer ids**, not on the contracts' — a customer with no
> contracts at all still needs their old ones cleared. `SyncResultDto.customers` is already parsed by
> this point; confirm the member name.

- [ ] **Step 5: Write the sync-level test**

```dart
  test('a payload with the reference members fills the local mirror', () async { ... });

  test('a payload from an older backend leaves every cached reference row alone', () async {
    // sync once with the members, then again with none of the four keys
    expect(await db.select(db.contracts).get(), hasLength(1));
  });

  test('a payload that no longer lists a carried customer\'s contract removes it', () async {
    // second sync: same customer, contracts: []
    expect(await db.select(db.contracts).get(), isEmpty);
  });

  test('a contract of a customer absent from the payload survives', () async {
    // second sync: different customer set, contracts: [] — the absent customer's row stays
    expect(await db.select(db.contracts).get(), hasLength(1));
  });
```

- [ ] **Step 6: Run the reference and sync suites**

Run: `flutter test test/data/reference/ test/data/sync/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/data/reference/reference_cache_repository.dart lib/data/sync/sync_service.dart \
        test/data/reference/reference_cache_repository_test.dart \
        test/data/sync/sync_reference_test.dart
git commit -m "feat(mobile): mirror the reference entities, prune only what a payload can vouch for

One upsert path, called from the payload and from a technician's own search, so a row
found online is indistinguishable from one the payload sent. Pruning is keyed to the
customers a payload carries and never to agents: the customer set is recomputed every
sync and the device accumulates, so an absent customer is not a deleted one.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B4: one picker, local mirror first, search behind it

**Files:**
- Create: `lib/data/reference/reference_option.dart`
- Create: `lib/data/reference/reference_search_client.dart`
- Create: `lib/features/ticket/reference_picker.dart`
- Create: `lib/features/ticket/reference_providers.dart`
- Test: `test/data/reference/reference_search_client_test.dart` (create)
- Test: `test/features/ticket/reference_picker_test.dart` (create)

**Interfaces:**
- Consumes: `ReferenceCacheRepository` (Task B3), the A1 `q` list endpoints.
- Produces:
  - `class ReferenceOption { final String id; final String label; final String? subtitle; }`
  - `class ReferenceSearchClient` with `searchContracts({required String customerId, required String query})`,
    `searchCommesse(...)`, `searchProdottiAssistenza(...)`, `searchAgents({required String query})` — each
    `Future<List<ReferenceOption>>`
  - `ReferencePickerField` — a dumb widget (below)
  - `referencePickerProviders`: `localContractsProvider`, `localCommesseProvider`, `localProdottiProvider`,
    `localAgentsProvider`, each `FutureProvider.family<List<ReferenceOption>, String>`

**The layer rule, and it is the reason this task exists.** A widget never touches Drift and never
performs a write. The chain is exactly:

```
ReferencePickerField ──search(query)──▶ referenceSearchClient.searchX(...)
                                             ├─ GET <A1 endpoint>            (network)
                                             ├─ ReferenceCacheRepository.upsertX(rows)  (write)
                                             └─ returns List<ReferenceOption>
```

so **a search result the technician can see is already in the mirror before the option is returned**.
That is what makes the pick safe: the ticket written from it can never reference a row this device
does not have. It is structural, not a test — which is why the pick callback must not be inlined into
the widget, and `ReferencePickerField` takes `search` as a parameter rather than building a client.

- [ ] **Step 1: Write the failing search-client test**

```dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/reference/reference_search_client.dart';

/// There is no `ApiClient` class in this repo — every client takes a bare [Dio] and each has its own
/// `_MockDio`. Follow `test/features/ticket/ticket_api_client_test.dart` verbatim.
class _MockDio extends Mock implements Dio {}

void main() {
  late AppDatabase db;
  late _MockDio dio;
  late ReferenceSearchClient client;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = _MockDio();
    client = ReferenceSearchClient(dio, ReferenceCacheRepository(db));
  });
  tearDown(() => db.close());

  Map<String, dynamic> contractJson(String id) => {
    'id': id, 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
    'name': 'Manutenzione $id', 'customerId': 'cu', 'locationId': null,
    'startDate': '2026-01-01T00:00:00Z', 'endDate': null, 'isActive': true,
    'numero': 'N-$id', 'codice': null, 'tipo': 0, 'externalId': null,
  };

  /// A paginated envelope, the shape every mobile client already unwraps with [pagedItems].
  Response<Map<String, dynamic>> ok(Map<String, dynamic> body) => Response(
        requestOptions: RequestOptions(path: '/api/contracts'),
        statusCode: 200,
        data: body,
      );

  /// The D-1(a) invariant, as a test: what a search hands the widget is readable from the mirror
  /// at the moment it is handed over. If this ever fails, a technician can pick a row the ticket
  /// write will then be rejected for.
  test('every option a search returns is already in the local mirror', () async {
    when(() => dio.get<Map<String, dynamic>>('/api/contracts',
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok({'items': [contractJson('c1'), contractJson('c2')]}));

    final options = await client.searchContracts(customerId: 'cu', query: 'manu');

    expect(options.map((o) => o.id), containsAll(['c1', 'c2']));
    final cached = await ReferenceCacheRepository(db).contractsForCustomer('cu');
    expect(cached.map((r) => r.id), containsAll(options.map((o) => o.id)),
        reason: 'a pick must never reference a row the mirror lacks');
  });

  test('the customer scope is sent to the server, so a search cannot widen D-1(a)', () async {
    when(() => dio.get<Map<String, dynamic>>(any(),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok({'items': <Object>[]}));

    await client.searchContracts(customerId: 'cu', query: 'x');

    final params = verify(() => dio.get<Map<String, dynamic>>('/api/contracts',
            queryParameters: captureAny(named: 'queryParameters')))
        .captured.single as Map<String, dynamic>;
    expect(params['customerId'], 'cu');
    expect(params['q'], 'x');
  });

  test('label falls back to codice when a contract has no numero', () { ... });

  /// Offline is the normal case for this feature, not an exceptional one: dio throws, and the
  /// picker falls back to the mirror, which is the offline answer anyway.
  test('an offline search returns empty, never throws', () async {
    when(() => dio.get<Map<String, dynamic>>(any(),
            queryParameters: any(named: 'queryParameters')))
        .thenThrow(DioException(
          requestOptions: RequestOptions(path: '/api/contracts'),
          type: DioExceptionType.connectionError,
        ));

    await expectLater(client.searchContracts(customerId: 'cu', query: 'x'), completion(isEmpty));
  });
}
```

> There is no error-mapping interceptor in `dioProvider` — a non-2xx or a dead socket reaches the
> caller as a raw `DioException` (see `lib/data/api/dio_client.dart`, and the `AuthInterceptor`'s
> narrow 401 handling). So `ReferenceSearchClient` catches `Object`, and matching on
> `DioExceptionType` specifically would be wrong: a timeout, a 500 and a parse failure all belong on
> the same fallback path.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/reference/reference_search_client_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write `ReferenceOption` and `ReferenceSearchClient`**

`lib/data/reference/reference_option.dart`:

```dart
/// One row a picker can show, from either source: the local mirror or an online search. The widget
/// cannot tell them apart, and must not — that is the point.
@immutable
class ReferenceOption {
  const ReferenceOption({required this.id, required this.label, this.subtitle});

  final String id;
  final String label;
  final String? subtitle;

  /// `numero` or `codice` — a technician reads whichever is printed on the paper contract.
  factory ReferenceOption.contract(ContractSyncDto c) => ReferenceOption(
        id: c.id,
        label: c.name,
        subtitle: c.numero ?? c.codice,
      );

  // .commessa / .prodotto / .agent in the same shape.
}
```

`lib/data/reference/reference_search_client.dart` — every method the same three moves:

```dart
import 'package:dio/dio.dart';

import '../api/json_parse.dart';

/// Search the server for a reference row and write what comes back into the mirror *before*
/// returning it. The technician's own successful query is the authorisation for the write; see the
/// plan's Global Constraints on why this is not a violation of D-1(a).
///
/// Offline this returns an empty list rather than throwing: the picker falls back to the local
/// mirror, which is the offline answer anyway. A search that fails is not an error the technician
/// can act on. Catches `Object`, not `DioException` — a timeout, a 4xx, a 503 and a parse failure all
/// belong on the same fallback path, and `dioProvider` installs no error mapper that would turn them
/// into one type.
///
/// Takes a bare [Dio], like every other client in `lib/data/**`: there is no shared `ApiClient` in
/// this repo.
class ReferenceSearchClient {
  ReferenceSearchClient(this._dio, this._cache);

  final Dio _dio;
  final ReferenceCacheRepository _cache;

  Future<List<ReferenceOption>> searchContracts({
    required String customerId,
    required String query,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/contracts', queryParameters: {
        'customerId': customerId,
        // Scope, always. A search widens *discovery*, never the security boundary.
        'isActive': 'true',
        'q': query,
        'pageSize': 20,
      });
      final rows = pagedItems(response.data!).map(ContractSyncDto.fromJson).toList();
      await _cache.upsertContracts(rows);
      return rows.map(ReferenceOption.contract).toList();
    } on Object {
      return const [];
    }
  }

  /// Same three moves. `GET /api/agents` is gated by `ClientiAgentRead`, which a technician may not
  /// hold — in which case this 403s and returns empty, and the picker shows the mirrored agents,
  /// which came from the technician's own tickets and need no permission. That is the designed
  /// behaviour, not a failure to report.
  Future<List<ReferenceOption>> searchAgents(...) async { ... }

  // searchCommesse / searchProdottiAssistenza in the same shape.
}
```

- [ ] **Step 4: Write the failing widget test**

Mirror `test/features/ticket/ticket_materiali_editor_test.dart`'s debounce technique.

```dart
  testWidgets('the local mirror is offered before anything is typed', (tester) async {
    var searched = false;
    await tester.pumpWidget(_wrap(ReferencePickerField(
      label: 'Contratto',
      localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione')],
      search: (q) async { searched = true; return const []; },
      onSelected: (_) {},
    )));

    await tester.tap(find.byKey(const ValueKey('reference-picker-contratto')));
    await tester.pumpAndSettle();

    expect(find.text('Manutenzione'), findsOneWidget);
    expect(searched, isFalse, reason: 'opening the picker is not a search');
  });

  testWidgets('typing searches once after the debounce, not once per keystroke', (tester) async {
    final queries = <String>[];
    ... search: (q) async { queries.add(q); return const []; } ...

    await tester.enterText(find.byType(TextField), 'man');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(find.byType(TextField), 'manu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(queries, ['manu']);
  });

  /// A slow answer to an abandoned query must not replace the results of the current one.
  testWidgets('a stale answer cannot overwrite a newer one', (tester) async {
    final slow = Completer<List<ReferenceOption>>();
    ... search: (q) async => q == 'man' ? slow.future : const [ReferenceOption(id: 'c2', label: 'Nuovo')] ...

    // type 'man', then 'manu' before the first answer lands, then complete the slow one
    expect(find.text('Nuovo'), findsOneWidget);
    expect(find.text('Vecchio'), findsNothing);
  });

  testWidgets('a failing search keeps the local rows and says so', (tester) async {
    ... search: (q) async { throw const SocketException('offline'); } ...

    expect(find.text('Manutenzione'), findsOneWidget);
    expect(find.textContaining('Non in linea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// A new hire, or a technician between jobs: no open work, so no customers, so every picker is
  /// empty. It must say so and invite a search, never render as a dead field.
  testWidgets('an empty mirror says so and still invites a search', (tester) async {
    await tester.pumpWidget(_wrap(ReferencePickerField(
      label: 'Contratto',
      localItems: const [],
      search: (q) async => const [ReferenceOption(id: 'c1', label: 'Trovato')],
      onSelected: (_) {},
    )));

    await tester.tap(find.byKey(const ValueKey('reference-picker-contratto')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nessun elemento in cache'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'con');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Trovato'), findsOneWidget);
  });

  testWidgets('picking an option reports exactly that option', (tester) async {
    ReferenceOption? picked;
    ... onSelected: (o) => picked = o ...
    expect(picked?.id, 'c1');
  });
```

- [ ] **Step 5: Write `ReferencePickerField`**

```dart
/// A picker over one reference entity. Two sources, one list:
///
///  - [localItems], the technician's mirrored scope, shown the instant the picker opens and the
///    only source while offline;
///  - [search], an online query, run 300 ms after typing stops, whose results *replace* the list —
///    and which, by its own contract, has already written them to the mirror before returning.
///
/// The widget knows nothing about either. It does not import Drift, does not import the search
/// client, and does not decide what a search is — a caller hands both in. That keeps the
/// materialise step out of the render tree, where it would run on every rebuild.
///
/// Deliberately modelled on [TicketMaterialiEditor]'s debounce, which is the existing precedent for
/// "local first, remote behind a timer" in this codebase.
class ReferencePickerField extends StatefulWidget {
  const ReferencePickerField({
    super.key,
    required this.label,
    required this.localItems,
    required this.search,
    required this.onSelected,
    this.selectedId,
    this.initialText,
    this.hint,
    this.emptyCacheHint = 'Nessun elemento in cache. Cerca per nome.',
    this.enabled = true,
  });

  final String label;

  /// The offline candidates, from a provider. Never fetched by this widget.
  final List<ReferenceOption> localItems;

  /// Search then materialise then return. See [ReferenceSearchClient].
  final Future<List<ReferenceOption>> Function(String query) search;

  final ValueChanged<ReferenceOption?> onSelected;
  final String? selectedId;
  final String? initialText;
  final String? hint;
  final String emptyCacheHint;
  final bool enabled;
  ...
}
```

Behaviour, in the widget's own terms:
- `_debounce = Timer(Duration(milliseconds: 300), ...)`; the timer is cancelled in `dispose` and on
  every keystroke.
- Each search carries a monotonically increasing `_searchSeq`; an answer whose seq is not the current
  one is discarded. Without this, a slow `man` answer can land on top of a fast `manu` one.
- The `try/catch` around the awaited search sets `_staleSearch = true` and leaves the last good list
  in place; the sheet shows a one-line `Non in linea — mostrati i risultati salvati` hint. The widget
  never rethrows into the tree.
- The suggestion list is capped by `maxSuggestions: 6` on the underlying `AppLookupField`, exactly as
  `TicketMaterialiEditor` does.

- [ ] **Step 6: Write the providers**

```dart
/// The local half of every reference picker: what this device already has, for one customer.
/// The search half is built at the call site from [referenceSearchClientProvider], so a screen can
/// hand the picker a callback without the picker learning where results come from.
final localContractsProvider =
    FutureProvider.family<List<ReferenceOption>, String>((ref, customerId) async {
  final rows = await ref.watch(referenceCacheProvider).contractsForCustomer(customerId);
  return rows.map(ReferenceOption.contract).toList();
});

// localCommesseProvider / localProdottiProvider / localAgentsProvider in the same shape.
// localAgentsProvider takes a query-string family key it ignores when empty, returning activeAgents().
```

- [ ] **Step 7: Run the picker suites**

Run: `flutter test test/data/reference/ test/features/ticket/reference_picker_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/data/reference/reference_option.dart lib/data/reference/reference_search_client.dart \
        lib/features/ticket/reference_picker.dart lib/features/ticket/reference_providers.dart \
        test/data/reference/reference_search_client_test.dart \
        test/features/ticket/reference_picker_test.dart
git commit -m "feat(mobile): one reference picker, local mirror first, search behind it

The search callback materialises before it returns, so an option the technician can see
is already in the mirror and the ticket written from it cannot reference a missing row.
The widget is dumb: it takes the local list and the search as parameters and knows neither
source.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B5: the wizard asks for the references the server actually validates

**Files:**
- Modify: `lib/features/ticket/new_ticket_form_state.dart`
- Modify: `lib/features/ticket/ticket_api_client.dart`
- Modify: `lib/features/ticket/steps/step_cliente_sede.dart`
- Modify: `lib/features/ticket/steps/step_dettagli_ticket.dart`
- Modify: `lib/features/ticket/new_ticket_form_screen.dart`
- Modify: `lib/features/ticket/steps/step_riepilogo_ticket.dart`
- Test: `test/features/ticket/new_ticket_form_state_test.dart`
- Test: `test/features/ticket/step_dettagli_ticket_test.dart`
- Test: `test/features/ticket/ticket_api_client_test.dart`

**Interfaces:**
- Consumes: `ReferencePickerField`, `ReferenceOption` (B4); `TicketApiClient`.
- Produces: `NewTicketFormState.contractId`, `.commessaId`, `.cantiereId`,
  `.prodottoAssistenzaIds` (`List<String>`), each with its `clear*` boolean in `copyWith`.

**The defect this task fixes.** `step_dettagli_ticket.dart:233-245` fills `agentId` from
`techniciansProvider`, which is `GET /api/users?role=Technician`. The server validates that field with
`EnsureExistsAsync<Agent>` (`TicketCommandService.cs:100`) against a **different entity** (legacy
"Agente", `Core/Entities/Agent.cs`). So a ticket created with a Riferimento is rejected with
`404 not_found` — silently, through the queue, as a ticket that never arrives. Confirmed against
`master`, not inferred.

- [ ] **Step 1: Write the failing state test**

```dart
  test('the new reference fields round-trip through copyWith and clear independently', () {
    const s = NewTicketFormState();
    final withRefs = s.copyWith(
      contractId: 'c1', commessaId: 'm1', cantiereId: 'ca1',
      prodottoAssistenzaIds: const ['p1', 'p2'],
    );

    expect(withRefs.contractId, 'c1');
    expect(withRefs.prodottoAssistenzaIds, ['p1', 'p2']);
    expect(withRefs.copyWith(clearContractId: true).contractId, isNull);
    expect(withRefs.copyWith(clearContractId: true).commessaId, 'm1',
        reason: 'clearing one reference must not clear its neighbours');
    expect(withRefs.copyWith(clearProdottoAssistenzaIds: true).prodottoAssistenzaIds, isEmpty);
  });

  test('none of the four is required to submit', () {
    // The existing isValid contract, unchanged: customerId, locationId, non-empty title, typeId,
    // statusId. A reference is an enrichment, and the wizard must not start blocking on it.
    expect(
      const NewTicketFormState(title: 'x', customerId: 'cu', locationId: 'l', typeId: 1, statusId: 1)
          .isValid,
      isTrue,
    );
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/ticket/new_ticket_form_state_test.dart`
Expected: FAIL — `contractId` is not a named parameter.

- [ ] **Step 3: Extend the form state**

Add the four fields and their four `clear*` booleans to `copyWith`, in the file's existing style
(the booleans are the pattern already used for `clearAssignedUserId`). `prodottoAssistenzaIds`
defaults to `const []` and is never null — an empty list and "not asked" are the same thing here,
and a nullable list would only add a second empty to reason about.

- [ ] **Step 4: Extend the API client**

Add the four parameters and the four body entries to `createTicket`, matching the server's request
record (`TicketCommands.cs:32`): `'contractId': ?contractId`, `'commessaId': ?commessaId`,
`'cantiereId': ?cantiereId`, and — because the server reads `ProdottoAssistenzaIds` as a list —
`'prodottoAssistenzaIds': ?(prodottoAssistenzaIds?.isEmpty ?? true ? null : prodottoAssistenzaIds)`.
An empty list is sent as absent, not as `[]`, so the request body matches what a technician who
never opened the picker sends. Extend `ticket_api_client_test.dart` with the wire-shape assertion
for all four.

- [ ] **Step 5: Put the pickers in the wizard**

- **`step_cliente_sede.dart`, after the sede picker:** Contratto, `localContractsProvider(customerId)`
  and `searchContracts`. Changing the customer clears Contratto, Commessa and Cantiere — they belong
  to the previous customer and would 404 otherwise. That clearing is a test, not a detail.
- **`step_cliente_sede.dart`, below Contratto:** Commessa.
- **`step_dettagli_ticket.dart`, below Tipo:** Prodotti assistenza, multi-select, same customer scope.
  Rendered as chips with an "Aggiungi prodotto" picker, the pattern `ticket_materiali_editor.dart`
  already uses.
- **Cantiere** already exists in this wizard; source it from the picker too if it currently comes from
  a narrow local list, and leave it alone if it already reads the cached cantieri table — check first,
  do not restructure what is not broken.

- [ ] **Step 6: Re-source Riferimento from Agents**

In `step_dettagli_ticket.dart`:

- Delete the `techniciansProvider` import from this file and the `_pickAgent(List<Map<String,dynamic>>)`
  signature.
- `_pickAgent(List<ReferenceOption>)` now takes options and pops `option.id`.
- The field watches `localAgentsProvider('')` for the offline list and calls
  `searchAgents(query: q)` from `referenceSearchClientProvider`.
- Keep the "Nessuno" sentinel and the dismiss-vs-clear distinction exactly as they are — their doc
  comment explains a real gesture difference and the tests cover it.
- Keep the label, the key `'agent-field'` and the `'agent-picker-<id>'` keys, so the existing tests
  keep asserting the same surface.
- Delete or rewrite the "same Users list, same reasoning as web's TicketCreatePanel" comment: it is
  the comment that encoded the bug. Replace it with the entity distinction.

- [ ] **Step 7: Update the summary step**

`step_riepilogo_ticket.dart` shows what will be submitted. Add the four references there, resolved to
labels — a technician confirming a ticket should see "Contratto: Manutenzione N-1", not a GUID, which
is the same complaint `ticket_detail_screen.dart:191` already records for `assignedUserId`.

- [ ] **Step 8: Run the wizard suites**

Run: `flutter test test/features/ticket/`
Expected: PASS. `step_dettagli_ticket_test.dart`'s agent tests will need their fixtures switched from
user maps to `ReferenceOption`s; that is a test-only change and must not weaken an assertion.

- [ ] **Step 9: Commit**

```bash
git add lib/features/ticket/new_ticket_form_state.dart lib/features/ticket/ticket_api_client.dart \
        lib/features/ticket/steps/step_cliente_sede.dart \
        lib/features/ticket/steps/step_dettagli_ticket.dart \
        lib/features/ticket/new_ticket_form_screen.dart \
        lib/features/ticket/steps/step_riepilogo_ticket.dart \
        test/features/ticket/new_ticket_form_state_test.dart \
        test/features/ticket/step_dettagli_ticket_test.dart \
        test/features/ticket/ticket_api_client_test.dart
git commit -m "feat(mobile): ask for contract, commessa, cantiere and products on create

Also fixes Riferimento: it was filled from Users while the server validates that field
with EnsureExistsAsync<Agent> against a different entity, so every ticket created with a
Riferimento was rejected 404 through the queue. Re-sourced from the agents mirror.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B6: a queued ticket that the server rejected for one bad reference

**Files:**
- Create: `lib/data/api/problem_details.dart`
- Modify: `lib/data/tickets/ticket_creation_queue.dart`
- Modify: `lib/data/local/app_database.dart` (the `repairableField` doc comment only, if the class
  comment needs the new state — no schema change, the column landed in B1)
- Modify: `lib/features/ticket/ticket_providers.dart`
- Modify: `lib/features/ticket/ticket_list_screen.dart`
- Modify: `lib/features/ticket/new_ticket_form_screen.dart` and `new_ticket_form_state.dart` — repair
  mode: the seed that drops the blamed field, and a save that routes to `queue.repair` instead of
  `queue.create` (revision note, items 2 and 3)
- Test: `test/data/api/problem_details_test.dart`
- Test: `test/data/tickets/ticket_creation_queue_test.dart`
- Test: `test/features/ticket/ticket_list_screen_test.dart`
- Test: `test/features/ticket/new_ticket_form_state_test.dart` (the two repair-mode tests in Step 7)

**Interfaces:**
- Consumes: the flat `field` member on a `not_found` problem (Task A3); `PendingTickets.repairableField` (B1).
- Produces: `ProblemDetails.fieldOf(Object)` / `.statusOf(Object)` / `.bodyOf(Object)`;
  `TicketCreationQueue.repairableFieldOf(Object)`; queue rows whose `repairableField` is set; and a
  provider `repairablePendingTicketsProvider`.

**The split, which is the whole point of this task.**

| Layer | Responsibility |
|---|---|
| `TicketCreationQueue` | **Detects** the rejection, **persists** the offending field name, **excludes** the row from auto-retry. Opens no UI, imports no widget, shows no string. |
| `ticket_list_screen.dart` | **Observes** rows with a `repairableField`, renders "Da correggere", and routes into the wizard for that row. |
| `NewTicketFormScreen` (edit mode) | **Repairs**: writes the corrected values back and clears `repairableField`, which returns the row to the ordinary retry path. |

Nothing in the queue layer may gain a `BuildContext`.

**Why `failed` and not a new state.** The row is still a failure and the existing badge already reads
`failed`; the new fact is *which field*, which is what the column carries. Adding a state would
require every existing `state` switch to learn it and would change the meaning of a row that is
merely waiting.

| Request field | Entity | Shape | Repairable by | Cleared by |
|---|---|---|---|---|
| `customerId` | Customer | scalar | picker (step 1) | picking a different customer |
| `locationId` | Location | scalar | picker (step 1) | picking a different sede |
| `contractId` | Contract | scalar | picker (step 1) | picking a different contract, or removing it |
| `commessaId` | Commessa | scalar | picker (step 1) | picking a different commessa |
| `assignedUserId` | User | scalar | picker (step 3) | picking a different technician, or Nessuno |
| `typeId` | TicketType | scalar | picker (step 2) | picking a different type |
| `agentId` | Agent | scalar | picker (step 2) | picking a different Riferimento, or Nessuno |
| `prodottoAssistenzaIds` | ProdottoAssistenza | list | multi picker (step 2) | dropping the ids that no longer exist |

Two fields the first draft listed are **not** repairable and must not be in `_repairableFields` —
see the third-pass revision note, item 1:

- `cantiereId` — no wizard step holds a cantiere field, so there is no picker to repair it with.
- `statusId` — the technician never picks it; `new_ticket_form_screen.dart:79-92` defaults it from
  the default `TicketStatus`, so a "repair" would re-send the id the server just refused.

Any field not in this table — including a field name from a backend that has moved on — leaves
`repairableField` **null**, and the row keeps today's behaviour: shown as failed, retried, with its
server message. The client must not guess at a repair for a field it cannot render, and it must not
show a repair screen that cannot fix the problem.

- [ ] **Step 1: Write the failing queue test**

```dart
  test('a 404 naming a field marks the row repairable and stops its auto-retry', () async {
    // enqueue a ticket, then have the API answer 404 not_found with extensions.field = customerId
    await queue.submit(pendingId);

    final row = (await db.select(db.pendingTickets).get()).single;
    expect(row.state, PendingTicketState.failed);
    expect(row.repairableField, 'customerId');
    expect(row.error, contains('customerId'), reason: 'the message still travels');

    // A second pass must not resubmit it: no answer will ever differ.
    final before = await api.submitCallCount;
    await queue.retryAll();
    expect(api.submitCallCount, before, reason: 'a repairable row waits for a human, not a timer');
  });

  test('a 404 without a field extension keeps the row on the ordinary retry path', () async {
    // same failure, no extensions.field
    expect(row.repairableField, isNull);
    await queue.retryAll();
    // api.submitCallCount incremented
  });

  test('a field the client cannot repair is left null, not guessed at', () async {
    // extensions.field = 'sourceId' — not in the table
    expect(row.repairableField, isNull);
  });

  test('a field with no picker to repair it is left null too', () async {
    // 'cantiereId' and 'statusId' are in the server's vocabulary but not in the wizard's: no step
    // holds a cantiere, and the status is defaulted rather than picked — so a "repair" would
    // re-send the very id the server refused. See the third-pass revision note, item 1.
    expect(TicketCreationQueue.repairableFieldOf(notFound({'field': 'cantiereId'})), isNull);
    expect(TicketCreationQueue.repairableFieldOf(notFound({'field': 'statusId'})), isNull);
  });

  test('repairing a row clears the flag and returns it to auto-retry', () async {
    // set repairableField via a 404, then update the row's customerId and clear the flag
    expect((await db.select(db.pendingTickets).get()).single.repairableField, isNull);
    await queue.retryAll();
    // api.submitCallCount incremented
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/tickets/ticket_creation_queue_test.dart`
Expected: FAIL — `repairableField` is never set.

- [ ] **Step 3: Detect and persist in the queue**

Add one private helper and one constant, and use it where the queue already classifies a response.

First the reader, in a new `lib/data/api/problem_details.dart` — a whole file because it is the one
place that knows the shape of this backend's problem bodies, and it is pure enough to unit-test
without a Dio, a database or a queue:

```dart
/// The machine-readable members of this backend's RFC 7807 problem bodies.
///
/// `ErrorResponse : ProblemDetails` keeps these in `ProblemDetails.Extensions`, which is
/// `[JsonExtensionData]` — on the wire they are members of the ROOT object (`{"title":…,
/// "code":"not_found", "field":"customerId"}`), never nested under an `extensions` key. Keys are
/// written literally and lowercase. See `ErrorHandlingMiddleware.MapException`.
///
/// A non-2xx arrives as a raw [DioException] — `dioProvider` installs no error mapper — so this takes
/// the caught error, not a `Response`.
class ProblemDetails {
  static Map<String, dynamic>? bodyOf(Object error) {
    if (error is! DioException) return null;
    final data = error.response?.data;
    return data is Map<String, dynamic> ? data : null;
  }

  static int? statusOf(Object error) =>
      error is DioException ? error.response?.statusCode : null;

  /// The request field a `not_found` named, or null. Read from the body, never from the message:
  /// the message is human prose that changes.
  static String? fieldOf(Object error) {
    if (statusOf(error) != 404) return null;
    final field = bodyOf(error)?['field'];
    return field is String && field.isNotEmpty ? field : null;
  }
}
```

Then, in the queue:

```dart
  /// The request fields whose rejection this client can actually repair — both re-pickable in the
  /// wizard and writable back to the queue row. Not in this set means the row waits for nothing: it
  /// is shown as failed and retried as before, because guessing at a repair for a field we cannot
  /// render would only produce a screen that cannot fix the problem. Mirrors the plan's table and
  /// Task A3's flat `field` member.
  ///
  /// `cantiereId` is absent because no wizard step has a cantiere field, and `statusId` because the
  /// wizard never asks for it — it defaults from the default TicketStatus, so a repair would re-send
  /// the rejected id. See the third-pass revision note, item 1.
  static const _repairableFields = {
    'customerId', 'locationId', 'contractId', 'commessaId',
    'assignedUserId', 'typeId', 'agentId', 'prodottoAssistenzaIds',
  };

  /// The field a `not_found` blamed, when this client can repair it. Null otherwise — including for
  /// a field name from a backend that has moved on, and for every non-404.
  ///
  /// Static and pure (a caught error in, a `String?` out) so it is testable without a database or a
  /// queue: test it directly first, then wire it.
  static String? repairableFieldOf(Object error) {
    final field = ProblemDetails.fieldOf(error);
    return field != null && _repairableFields.contains(field) ? field : null;
  }
```

These two are pure, so test them directly — no queue, no database, no widget. Put this in
`test/data/api/problem_details_test.dart` and mirror the first two cases for `repairableFieldOf` in
the queue's test file:

```dart
  DioException notFound(Map<String, dynamic> body) => DioException(
        requestOptions: RequestOptions(path: '/api/tickets'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/tickets'),
          statusCode: 404,
          data: body,
        ),
      );

  test('field is read from the flat root of the problem body', () {
    expect(ProblemDetails.fieldOf(notFound({'code': 'not_found', 'field': 'customerId'})),
        'customerId');
  });

  /// The shape a nested reader would have expected, and must NOT be what this accepts: the
  /// extensions are JsonExtensionData, so they sit at the root. A test pinning the wrong shape would
  /// be worse than no test.
  test('a nested extensions object is not where the field lives', () {
    expect(ProblemDetails.fieldOf(notFound({'extensions': {'field': 'customerId'}})), isNull);
  });

  test('a 400 is not a FK rejection, however it is shaped', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/api/tickets'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/tickets'),
        statusCode: 400,
        data: {'code': 'validation_failed', 'field': 'customerId'},
      ),
    );
    expect(ProblemDetails.fieldOf(e), isNull);
  });

  test('an offline failure carries no body and no field', () {
    expect(ProblemDetails.fieldOf(DioException(
      requestOptions: RequestOptions(path: '/api/tickets'),
      type: DioExceptionType.connectionError,
    )), isNull);
  });
```

- [ ] **Step 4: Exclude repairable rows from auto-retry**

Wherever the queue selects rows to retry, add `& pendingTickets.repairableField.isNull()`. Include the
`failed` sweep *and* the `pendingSync` sweep: a row repaired back to health must re-enter through the
same path every other row uses, and that only works if the exclusion is a property of the query
rather than a branch in the loop.

- [ ] **Step 5: Add the read-only provider**

```dart
/// Queued tickets the server rejected for a reference this client can repair. Read-only: the UI
/// observes, it does not decide. See TicketCreationQueue.repairableFieldOf for what qualifies.
final repairablePendingTicketsProvider = StreamProvider<List<PendingTicket>>((ref) =>
    (ref.watch(appDatabaseProvider).select(ref.watch(appDatabaseProvider).pendingTickets)
          ..where((t) => t.repairableField.isNotNull()))
        .watch());
```

- [ ] **Step 6: Write the failing list-screen test**

```dart
  testWidgets('a rejected queue row is offered as "Da correggere"', (tester) async {
    // seed a pending ticket with repairableField = 'customerId'
    expect(find.text('Da correggere'), findsOneWidget);
  });

  testWidgets('a row the client cannot repair shows the ordinary failure, not a repair', (tester) async {
    // seed a pending ticket, state failed, repairableField null, error = 'Errore del server'
    expect(find.text('Da correggere'), findsNothing);
    expect(find.textContaining('Errore del server'), findsOneWidget);
  });
```

- [ ] **Step 7: Render the row and route into the wizard**

Wherever `ticket_list_screen.dart` renders the pending-failed rows, a row with a `repairableField`
gets a "Da correggere" badge and routes into the create wizard, seeded from the queue row.

The seed is **not** the shape `edit_ticket_screen.dart` preloads from a server ticket — that shape
carries none of the reference fields (revision note, item 2). Seed `NewTicketFormState` from the
`PendingTickets` row: `customerId`, `locationId`, `contractId`, `commessaId`, `cantiereId`,
`assignedUserId`, `statusId`, `typeId`, `agentId`, `prodottoAssistenzaIds` (through
`_decodeStringList` on `prodottoAssistenzaIdsJson`), `priorita`, `dueDate`, `technicianNotes`, `tags`.

Then **drop the blamed field** — `repairableField` names it — and surface why in that field's place:
"Il riferimento non è più valido: scegline un altro". Preloading the rejected value is the loop the
revision note's item 3 describes; a repair that writes back what already failed clears the flag and
changes nothing.

On save, repair mode calls a new `TicketCreationQueue.repair(id, …)` — an `UPDATE` of that same row
with every field above, then `repairableField: null` — and **never** `queue.create` (which would
insert a second pending row) and **never** a `PUT /api/tickets`. The repaired row returns to the
ordinary retry path on the next pass. `repair` and `create` should share their row-writing body; a
second hand-maintained copy of the column list is how a repair quietly stops carrying a field.

Two tests pin the parts that are easy to get wrong:

```dart
  test('repair mode drops the blamed field and keeps every other value', () async {
    // seed a pending row: repairableField 'agentId', a bad agentId, a good customerId/typeId/title
    final seed = NewTicketFormState.fromPendingRow(row);
    expect(seed.agentId, isNull, reason: 'preloading the rejected id makes Salva a no-op');
    expect(seed.customerId, 'cust-1');
    expect(seed.title, 'Perdita idrica');
  });

  test('repairing updates the row in place and clears the flag', () async {
    await queue.repair(row.id, customerId: 'cust-2', /* … every other field … */);
    final rows = await db.select(db.pendingTickets).get();
    expect(rows, hasLength(1), reason: 'a repair is not a second ticket');
    expect(rows.single.id, row.id);
    expect(rows.single.customerId, 'cust-2');
    expect(rows.single.repairableField, isNull);
    await queue.retryAll(); // and it is back on the ordinary path
  });
```

- [ ] **Step 8: Run the queue and list suites**

Run: `flutter test test/data/tickets/ test/features/ticket/ticket_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/data/api/problem_details.dart \
        lib/data/tickets/ticket_creation_queue.dart lib/features/ticket/ticket_providers.dart \
        lib/features/ticket/ticket_list_screen.dart \
        lib/features/ticket/new_ticket_form_screen.dart \
        lib/features/ticket/new_ticket_form_state.dart \
        test/data/api/problem_details_test.dart \
        test/data/tickets/ticket_creation_queue_test.dart \
        test/features/ticket/ticket_list_screen_test.dart \
        test/features/ticket/new_ticket_form_state_test.dart
git commit -m "feat(mobile): repair a queued ticket the server rejected for one bad reference

The queue detects and persists the blamed field and stops retrying that row; the list
screen observes it and routes into the wizard, which drops the rejected value so the
technician must re-pick it and writes the result back to the same row. A field this
client cannot render stays null and keeps the old failure path, so the UI never offers
a repair it cannot perform.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Phase B gate

Run: `flutter test` (whole suite) — expected PASS, and `flutter analyze` clean.

Then the device test, on the user's own hardware and against a real backend:

1. Fly a customer, drop the data connection, open the create wizard, and confirm Contratto, Commessa
   and Prodotti assistenza are filled from the mirror for that customer.
2. Reconnect, open the Contratto picker on a customer the device has never seen, type a name, and
   confirm the result list appears — then take the phone offline again and confirm the row the
   technician just picked is still there, because the search wrote it.
3. Set a Riferimento and submit, and confirm the ticket arrives (this is the B5 fix; before it, it did
   not).
4. Queue a ticket for a customer, delete the customer server-side, submit, and confirm the row reads
   "Da correggere" and that fixing the customer lands the ticket.

Only then: tag `v*`, per the standing release rule. The branch stays unmerged until then.

---

## Self-review

**Spec coverage.** §5 Option E: A2 (payload), B1–B4 (mirror and pickers). §6 sync design: A2, B2, B3.
§7 UX contract: B4, B5. §8 schema: B1. §9 backend scoping: A2. §10 decisions: D-1(a) in the Global
Constraints; D-2/D-3/D-4 keep the spec's stated defaults and no task here changes them. §2.6–§2.7,
the corrected facts — the 404-not-400 FK failure (A3, B6), `ProdottoAssistenzaIds` being
`[NotMapped]`, the absent tombstones (B3's scoped prune) — each lands in a task. The one spec item
with no task is the web client's identical Riferimento bug, and it is listed as out of scope.

**Placeholder scan.** Two `{ ... }` elisions remain, both in test bodies that restate a case the
preceding lines already spell out (`label falls back to codice`, and the stale-answer widget test's
setup). Every other step carries its content. `// searchCommesse / ... in the same shape` appears four
times and each marks a genuinely identical method, not an unstated one.

**Type consistency.** `upsertContracts` / `pruneContracts` / `contractsForCustomer` are the names in
B3, B4 and B6. `ReferenceOption{id,label,subtitle}` is defined once, in B4, and used by B4, B5 and the
providers. `repairableField` is the column in B1, the local in B6 and the helper's return. The four
`carries*` flags are spelled identically in B2, B3 and the Global Constraints. `field` is flat on the
wire in A3, read flat by `ProblemDetails.fieldOf` in B6, and never nested anywhere. `Dio` (not a
nonexistent `ApiClient`) is the client type in B4 and B6, matching `lib/data/**`. No `materialize*`
spelling survives anywhere — the vocabulary is `upsert`.

**Review Focus.** Each of the five lines names its owner above; all five have a test in that task's
steps, including the two that are structural rather than asserted (B4's materialise-before-return,
which its own test pins anyway).

**Read before writing, five places, all checked against `master` except the last:** the three
`GetAll` bodies and `CommesseController`'s (A1); `prodotto_assistenza`'s real member names for
`ProdottoAssistenzaSyncDto` (B2); `PendingTicketsCompanion.insert`'s required set (B1 Step 1's
callout); the widget test harness in `ticket_materiali_editor_test.dart` and the `Dio` mock in
`ticket_api_client_test.dart` (B4); and, in the mobile tree rather than on `master`, whether the
cantiere picker already reads the cached cantieri table (B5 Step 5) — if it does, leave it alone.
