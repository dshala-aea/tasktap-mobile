# Offline reference cache and ticket parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a technician the reference data a ticket is made of — contract, commessa, product, agent — so the create wizard works offline for the customers their own work already reaches, and reaches everything else through online search that materialises the pick.

**Architecture:** Option E from the spec: extend the existing `/api/sync/mobile` delta with four scoped entity lists, mirror them in four Drift tables, and add one picker widget that shows the local mirror first and searches the server on demand. No new sync mechanism, no new tables on the server, no permissions model: the scope is the technician's own work scope (D-1(a)), computed by the traversal `MobileUserSyncService` already performs.

**Tech Stack:** Backend — .NET 8, EF Core, xUnit + FluentAssertions + `UseInMemoryDatabase`. Mobile — Flutter/Dart, Drift (schema 36 → 37), Riverpod, dio, `flutter_test` + `mocktail`.

**Spec:** `mobile/docs/superpowers/specs/2026-10-08-offline-architecture-reanalysis-design.md` (Option E §5, sync design §6, UX contract §7, schema §8, backend §9, decisions §10). **Read §2.6 and §2.7 first** — they correct three facts the spec originally asserted, and §2.7 is a live defect this plan fixes.

## Global Constraints

- **Two working trees, two branches.** Backend work runs in `/mnt/d/AEA/Sviluppi/TaskTap` (the API repo); mobile work runs in `/mnt/d/AEA/Sviluppi/TaskTap/mobile` (a **nested git repo**, separate history, never touched by backend commits).
- **Backend branches from `master`, never from the current checkout.** The root working tree is on `feat/copilot-domain-correctness`, which is **51 commits behind `master`** and does not contain the deployed per-asset checklist feature. Phase A's first step is `git checkout -b feat/offline-reference-sync master`.
- **Scope is D-1(a): the technician's own work scope.** No tenant-wide list may enter the payload. Contracts/commesse/products are scoped to the customer ids already in the payload; agents to the agents already referenced by the payload's tickets. This is a security property, tested as one.
- **`IsActive` is carried, never filtered** (§6.4). A scope predicate that hides inactive rows is the bug this work exists to fix.
- **Old clients ignore new members; new clients must not read a missing member as "empty".** Every new member is gated by the established key-presence `carries*` flag, and a payload without the key must leave the local rows untouched.
- **Never `sed -i`, `perl -i`, or in-place Python on `/mnt/d`** — it silently deletes files on this mount.
- **Git:** explicit-path `git add` only, never `git add -A`. Commit trailers: `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- **Mobile ships on `v*` tags after the user device-tests.** Branch `feat/mobile-asset-checklists` stays unmerged.
- Copy is Italian, user-facing, and matches the existing tone. No English strings in mobile UI.
- **Out of scope, explicitly:** `maintenanceTemplateId`, `externalId`, attachments, `internalNotes` on **update** (create only), any offline write for admin/magazzino, CRDT/vector clocks/tombstone tables, and the web client's identical Riferimento bug (frontend repo, its own release).

## Review Focus

The five inputs most likely to bite a real technician, each pinned by a test in the task that owns it:

1. **A queued ticket whose FK row was deactivated or deleted after drafting.** The send is rejected; the technician must be told which field died and be able to pick a replacement without retyping the ticket. → Task B6.
2. **A search result the technician selects that is outside the mirrored scope.** It must be written into the local mirror at select time, and must still be there for the ticket that is created from it. → Task B4.
3. **An older backend that does not send the new keys at all.** It must not look like "every reference row was deleted" — the bootstrap prune must not fire. → Tasks B2, B3.
4. **A technician with no tickets yet** (new hire, or all their work is older than the sync window). Every picker must render a labelled empty state with a way forward, never a dead control. → Task B4.
5. **"Riferimento" must never again send a `User` id into `Ticket.AgentId`.** The server guards that field with `EnsureExistsAsync<Agent>`. → Task B5.

---

# Phase A — Backend

Phase A is independently shippable: the payload extension is additive, old clients ignore it, and Tasks A1–A3 ship one backend release before any mobile build consumes it (spec §11.1).

**Working directory for every task in this phase:** `/mnt/d/AEA/Sviluppi/TaskTap`.
**Create the branch once, before Task A1:**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap
git fetch origin && git checkout -b feat/offline-reference-sync master
git log --oneline -1   # must show 59e6d688 or a descendant
```

Do **not** work on `feat/copilot-domain-correctness`: it lacks `MobileUserSyncService`'s checklist block, `SyncChecklistDtos.cs`, and `TicketProdottoAssistenza.MaintenanceTemplateVersionId`.

---

### Task A1: `q` on the contracts and products list endpoints

**Files:**
- Modify: `src/TaskTapAPI.Api/Controllers/ContractsController.cs:58-100`
- Modify: `src/TaskTapAPI.Api/Controllers/ProdottoAssistenzaController.cs:53-106`
- Test: `tests/TaskTapAPI.Tests/Controllers/ReferenceListSearchTests.cs` (create)

**Interfaces:**
- Consumes: `ListQuery.Q` (`src/TaskTapAPI.Api/Queries/ListQuery.cs:11-33`).
- Produces: nothing new. Both endpoints start honouring the `q` query parameter they already accept.

**Why:** Search-on-demand (spec §7.4) is the whole online half of the design. Verified today: `ContractsController.GetAll` and `ProdottoAssistenzaController.GetAll` bind `ListQuery` and never read `query.Q` — the parameter is silently dropped. `CommesseController.cs:69-70` shows the shape to copy.

- [ ] **Step 1: Write the failing test**

```csharp
using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskTapAPI.Api.Controllers;
using TaskTapAPI.Api.Queries;
using TaskTapAPI.Application.Services;
using TaskTapAPI.Core.Entities;
using TaskTapAPI.Infrastructure.Configuration;
using TaskTapAPI.Infrastructure.Context;
using TaskTapAPI.Infrastructure.Data;
using TaskTapAPI.Infrastructure.UnitOfWork;
using Xunit;

namespace TaskTapAPI.Tests.Controllers;

/// <summary>
/// The pickers search the server through these list endpoints. `q` is the parameter the whole
/// on-demand path is built on, so an endpoint that accepts ListQuery and drops `q` is not a
/// cosmetic gap: it makes the picker claim a search it never performs.
/// </summary>
public class ReferenceListSearchTests : IDisposable
{
    private readonly ApplicationDbContext _db;
    private readonly TenantContext _tenantContext = new();
    private readonly Guid _tenantId = Guid.NewGuid();

    public ReferenceListSearchTests()
    {
        _tenantContext.SetTenant(_tenantId);
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .ConfigureWarnings(w => w.Ignore(
                Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning))
            .Options;
        _db = new ApplicationDbContext(options, _tenantContext, new TenantOptions());

        var now = DateTime.UtcNow;
        var customerId = Guid.NewGuid();
        _db.Contracts.AddRange(
            new Contract { Id = Guid.NewGuid(), TenantId = _tenantId, CustomerId = customerId,
                Name = "Manutenzione caldaie", StartDate = now, CreatedAt = now },
            new Contract { Id = Guid.NewGuid(), TenantId = _tenantId, CustomerId = customerId,
                Name = "Assistenza porte", StartDate = now, CreatedAt = now });
        _db.Set<ProdottoAssistenza>().AddRange(
            new ProdottoAssistenza { Id = Guid.NewGuid(), TenantId = _tenantId,
                CustomerId = customerId, LocationId = Guid.NewGuid(), Name = "Caldaia Nord",
                CreatedAt = now },
            new ProdottoAssistenza { Id = Guid.NewGuid(), TenantId = _tenantId,
                CustomerId = customerId, LocationId = Guid.NewGuid(), Name = "Porta garage",
                CreatedAt = now });
        _db.SaveChanges();
    }

    public void Dispose() => _db.Dispose();

    private ContractsController ContractsSut() => new(
        new UnitOfWork(_db, _tenantContext, new TaskTapAPI.Infrastructure.Time.SystemClock()),
        _tenantContext,
        new ReferentialIntegrityService(new UnitOfWork(_db, _tenantContext,
            new TaskTapAPI.Infrastructure.Time.SystemClock()), _tenantContext));

    [Fact]
    public async Task Contracts_list_filters_by_q()
    {
        var result = await ContractsSut().GetAll(new ListQuery { Q = "caldaie" });

        var page = (result as OkObjectResult)!.Value as TaskTapAPI.Application.Common.PaginatedResult<
            TaskTapAPI.Core.Entities.Contract>;
        page!.Items.Should().ContainSingle().Which.Name.Should().Be("Manutenzione caldaie");
    }
}
```

> Verify the `ContractsController` constructor argument list against the file before running; it is
> quoted from the controller's own SUT factory in `ContractsControllerTemplateAssignmentTests.cs`.
> Copy that factory rather than the list above if they differ.

- [ ] **Step 2: Run it and watch it fail**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~ReferenceListSearchTests`
Expected: FAIL — the page contains both contracts, `q` was ignored.

- [ ] **Step 3: Add the filter to both controllers**

In `ContractsController.GetAll`, immediately after the `codice` filter and before the sort:

```csharp
        // Free-text search. The mobile picker's on-demand path sends this; without it the
        // endpoint accepts ListQuery and silently drops the term, so the picker would claim a
        // search it never performed.
        if (!string.IsNullOrWhiteSpace(query.Q))
            q = q.Where(c => c.Name.Contains(query.Q));
```

In `ProdottoAssistenzaController.GetAll`, in the same position (after the existing filters, before the sort):

```csharp
        // See ContractsController.GetAll: the picker's search term must actually reach the query.
        if (!string.IsNullOrWhiteSpace(query.Q))
            q = q.Where(p => p.Name.Contains(query.Q));
```

Match the case-insensitivity convention of the file you are editing — `TicketsController` uses
`Contains` (case-sensitive on the column's collation), `UsersController` lowercases the term. Follow
whatever the neighbouring filters in each file already do, and if they lowercase, lowercase here too
and make the test's term match.

- [ ] **Step 4: Add the product test and the negative case**

Add to `ReferenceListSearchTests`:

```csharp
    [Fact]
    public async Task Products_list_filters_by_q()
    {
        var sut = new ProdottoAssistenzaController(
            new UnitOfWork(_db, _tenantContext, new TaskTapAPI.Infrastructure.Time.SystemClock()),
            _tenantContext,
            _db,
            new ReferentialIntegrityService(new UnitOfWork(_db, _tenantContext,
                new TaskTapAPI.Infrastructure.Time.SystemClock()), _tenantContext));

        var result = await sut.GetAll(new ListQuery { Q = "caldaia" });

        var page = (result as OkObjectResult)!.Value as TaskTapAPI.Application.Common.PaginatedResult<
            TaskTapAPI.Core.Entities.ProdottoAssistenza>;
        page!.Items.Should().ContainSingle().Which.Name.Should().Be("Caldaia Nord");
    }

    [Fact]
    public async Task An_empty_q_still_returns_everything()
    {
        var result = await ContractsSut().GetAll(new ListQuery { Q = "   " });

        var page = (result as OkObjectResult)!.Value as TaskTapAPI.Application.Common.PaginatedResult<
            TaskTapAPI.Core.Entities.Contract>;
        page!.Items.Should().HaveCount(2);
    }
```

Confirm the `ProdottoAssistenzaController` constructor against
`ProdottoAssistenzaControllerTests.cs:26-39` and use that factory verbatim.

- [ ] **Step 5: Run the tests**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~ReferenceListSearchTests`
Expected: PASS, 3/3.

- [ ] **Step 6: Run the neighbouring paging/search suites**

Run: `dotnet test tests/TaskTapAPI.Tests --filter "FullyQualifiedName~Pagination|FullyQualifiedName~ScopedLookup|FullyQualifiedName~ProdottoAssistenzaController"`
Expected: PASS. These pin the `Q`/paging semantics of the other list endpoints and must not move.

- [ ] **Step 7: Commit**

```bash
git add src/TaskTapAPI.Api/Controllers/ContractsController.cs \
        src/TaskTapAPI.Api/Controllers/ProdottoAssistenzaController.cs \
        tests/TaskTapAPI.Tests/Controllers/ReferenceListSearchTests.cs
git commit -m "fix(api): honour q on the contracts and products list endpoints

Both accepted ListQuery and dropped query.Q, so the mobile picker's on-demand
search would have returned unfiltered pages for two of the four reference
entities. Mirrors the CommesseController filter.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task A2: extend the mobile sync payload with the four reference entities

**Files:**
- Create: `src/TaskTapAPI.Application/Services/Sync/SyncReferenceDtos.cs`
- Modify: `src/TaskTapAPI.Application/Services/Sync/MobileUserSyncResult.cs`
- Modify: `src/TaskTapAPI.Application/Services/Sync/MobileUserSyncService.cs`
- Test: `tests/TaskTapAPI.Tests/Sync/MobileUserSyncReferenceTests.cs` (create)

**Interfaces:**
- Consumes: the already-materialised `customers`, `locations` and `tickets` inside `GetDeltaAsync`; `MobileUserSyncService.MaxAssetControlRowsPerSync` for the cap convention.
- Produces, for the mobile plan:
  - `MobileUserSyncResult.Contracts` → wire `contracts`
  - `MobileUserSyncResult.Commesse` → wire `commesse`
  - `MobileUserSyncResult.ProdottiAssistenza` → wire `prodottiAssistenza`
  - `MobileUserSyncResult.Agents` → wire `agents`
  - `SyncContractDto(Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt, string Name, Guid CustomerId, Guid? LocationId, DateTime StartDate, DateTime? EndDate, bool IsActive, string? Numero, string? Codice, int? Tipo, string? ExternalId)`
  - `SyncCommessaDto(Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt, string Codice, string? Descrizione, Guid? CustomerId, bool IsActive, string? Stato, string? ExternalId)`
  - `SyncProdottoAssistenzaDto(Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt, string Name, Guid CustomerId, Guid LocationId, bool IsActive, string? Codice, string? SerialNumber, string? Categoria, string? Marchio, string? ExternalId)`
  - `SyncAgentDto(Guid Id, Guid TenantId, DateTime CreatedAt, DateTime? UpdatedAt, string Nome, string? Email, string? Cellulare, bool IsActive)`

**Scope predicate (D-1(a)) — implement exactly this:**
- `contracts`: `CustomerId` ∈ the payload's customer ids.
- `commesse`: `CustomerId` ∈ the payload's customer ids.
- `prodottiAssistenza`: `CustomerId` ∈ the payload's customer ids.
- `agents`: `Id` ∈ `{ tickets.AgentId }` of the payload's tickets.
- Every query adds the delta `(UpdatedAt ?? CreatedAt) > cutoff` when a cutoff is present, and **never** filters `IsActive`.

- [ ] **Step 1: Write the failing tests**

Create `tests/TaskTapAPI.Tests/Sync/MobileUserSyncReferenceTests.cs`. Fixture shape follows
`MobileUserSyncSubmittedReportsTests.cs:880-943` — build the service over a real
`ScheduleAssignmentResolver`, never a stub, or "this technician's schedules" is trivially empty and
every scoping assertion passes vacuously.

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
    private readonly Guid _agentId = Guid.NewGuid();
    private readonly Guid _otherAgentId = Guid.NewGuid();
    private readonly DateTime _t = new(2025, 1, 1, 10, 0, 0, DateTimeKind.Utc);

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
        var locationId = Guid.NewGuid();
        var ticketId = Guid.NewGuid();

        _db.Locations.Add(new Location
        {
            Id = locationId, TenantId = _tenantId, CustomerId = _inScopeCustomer,
            Name = "Sede", CreatedAt = now,
        });
        // In-window schedule for the technician -> pulls location -> ticket -> customer.
        _db.Set<Schedule>().Add(new Schedule
        {
            Id = Guid.NewGuid(), TenantId = _tenantId, UserId = _techId, LocationId = locationId,
            TicketId = ticketId, ActivityDate = now.Date, TimeStart = TimeSpan.Zero,
            TimeEnd = TimeSpan.FromHours(1), StatusId = 1, Title = "Intervento",
            Description = "", CreatedAt = now,
        });
        _db.Tickets.Add(new Ticket
        {
            Id = ticketId, TenantId = _tenantId, CustomerId = _inScopeCustomer, LocationId = locationId,
            AssignedUserId = _techId, Title = "Caldaia", StatusId = 1, TypeId = 1,
            AgentId = _agentId, CreatedAt = now,
        });
        _db.Customers.AddRange(
            new Customer { Id = _inScopeCustomer, TenantId = _tenantId, CompanyName = "In scope", CreatedAt = now },
            new Customer { Id = _outOfScopeCustomer, TenantId = _tenantId, CompanyName = "Out of scope", CreatedAt = now });

        _db.Contracts.AddRange(
            new Contract { Id = Guid.NewGuid(), TenantId = _tenantId, CustomerId = _inScopeCustomer,
                Name = "Contratto in scope", StartDate = now, CreatedAt = now },
            new Contract { Id = Guid.NewGuid(), TenantId = _tenantId, CustomerId = _outOfScopeCustomer,
                Name = "Contratto fuori scope", StartDate = now, CreatedAt = now },
            // Another tenant's contract for the SAME customer id must never surface.
            new Contract { Id = Guid.NewGuid(), TenantId = _otherTenant, CustomerId = _inScopeCustomer,
                Name = "Altro tenant", StartDate = now, CreatedAt = now });
        _db.Commesse.Add(new Commessa { Id = Guid.NewGuid(), TenantId = _tenantId,
            CustomerId = _inScopeCustomer, Codice = "C-1", CreatedAt = now });
        _db.Set<ProdottoAssistenza>().AddRange(
            new ProdottoAssistenza { Id = Guid.NewGuid(), TenantId = _tenantId,
                CustomerId = _inScopeCustomer, LocationId = Guid.NewGuid(), Name = "Caldaia Nord", CreatedAt = now },
            new ProdottoAssistenza { Id = Guid.NewGuid(), TenantId = _tenantId,
                CustomerId = _outOfScopeCustomer, LocationId = Guid.NewGuid(), Name = "Porta", CreatedAt = now });
        _db.Set<Agent>().AddRange(
            new Agent { Id = _agentId, TenantId = _tenantId, Nome = "Rif. usato", CreatedAt = now },
            new Agent { Id = _otherAgentId, TenantId = _tenantId, Nome = "Rif. mai usato", CreatedAt = now });
        _db.SaveChanges();
    }

    public void Dispose() => _db.Dispose();

    private MobileUserSyncService CreateService()
    {
        var tenantContext = new TenantContext();
        tenantContext.SetTenant(_tenantId);
        return new MobileUserSyncService(_db, new TaskTapAPI.Application.Modules.Schedules.Services
            .ScheduleAssignmentResolver(new TaskTapAPI.Infrastructure.UnitOfWork.UnitOfWork(
                _db, tenantContext, new TaskTapAPI.Infrastructure.Time.SystemClock())));
    }

    [Fact]
    public async Task Reference_entities_are_scoped_to_the_callers_own_work()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Contracts.Should().ContainSingle().Which.Name.Should().Be("Contratto in scope");
        r.Commesse.Should().ContainSingle().Which.Codice.Should().Be("C-1");
        r.ProdottiAssistenza.Should().ContainSingle().Which.Name.Should().Be("Caldaia Nord");
        r.Agents.Should().ContainSingle().Which.Nome.Should().Be("Rif. usato");
    }

    [Fact]
    public async Task Only_the_agents_referenced_by_the_callers_tickets_are_sent()
    {
        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Agents.Select(a => a.Id).Should().NotContain(_otherAgentId);
    }

    [Fact]
    public async Task An_inactive_contract_is_still_sent_with_its_flag()
    {
        var id = Guid.NewGuid();
        _db.Contracts.Add(new Contract
        {
            Id = id, TenantId = _tenantId, CustomerId = _inScopeCustomer,
            Name = "Cessato", StartDate = _t, IsActive = false, CreatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync();

        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: null);

        r.Contracts.Single(c => c.Id == id).IsActive.Should().BeFalse(
            "hiding it is what leaves a deleted contract in the picker forever (spec 6.4)");
    }

    [Fact]
    public async Task The_delta_carries_a_reference_row_edited_after_the_cutoff()
    {
        var cutoff = DateTime.UtcNow;
        var id = Guid.NewGuid();
        _db.Contracts.Add(new Contract
        {
            Id = id, TenantId = _tenantId, CustomerId = _inScopeCustomer, Name = "Nuovo",
            StartDate = _t, CreatedAt = cutoff.AddMinutes(-1), UpdatedAt = cutoff.AddMinutes(1),
        });
        await _db.SaveChangesAsync();

        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: cutoff);

        r.Contracts.Should().ContainSingle().Which.Id.Should().Be(id);
    }

    [Fact]
    public async Task A_reference_row_never_synced_but_older_than_the_cutoff_is_not_sent()
    {
        var cutoff = DateTime.UtcNow;
        var id = Guid.NewGuid();
        _db.Contracts.Add(new Contract
        {
            Id = id, TenantId = _tenantId, CustomerId = _inScopeCustomer, Name = "Vecchio",
            StartDate = _t, CreatedAt = cutoff.AddDays(-1),
        });
        await _db.SaveChangesAsync();

        var r = await CreateService().GetDeltaAsync(_tenantId, _techId, since: cutoff);

        r.Contracts.Should().BeEmpty();
    }
}
```

> Confirm `Schedule`'s required members (`StatusId`, `Title`, `Description`, `TimeStart`/`TimeEnd`)
> against the entity and against `TestFixtures`' `AddScheduleWithAssignments` helper — if that
> helper exists, use it instead of the hand-built schedule.

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
/// caller's own work already reaches, and agents to the agents already referenced by the caller's
/// tickets. Widening any of these is a confidentiality decision, not a sync change (spec §10, D-1).
///
/// <c>isActive</c> travels as data and the picker filters on it. A predicate that hides inactive
/// rows would make a deactivation invisible to a device that has already cached the row — the
/// failure spec §6.4 exists to fix. Hard deletes, which no flag can describe, are handled on the
/// client by pruning on bootstrap.
/// </summary>
public sealed record SyncContractDto(
    Guid Id,
    Guid TenantId,
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    string Name,
    Guid CustomerId,
    Guid? LocationId,
    DateTime StartDate,
    DateTime? EndDate,
    bool IsActive,
    string? Numero,
    string? Codice,
    int? Tipo,
    string? ExternalId);

public sealed record SyncCommessaDto(
    Guid Id,
    Guid TenantId,
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    string Codice,
    string? Descrizione,
    Guid? CustomerId,
    bool IsActive,
    string? Stato,
    string? ExternalId);

public sealed record SyncProdottoAssistenzaDto(
    Guid Id,
    Guid TenantId,
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    string Name,
    Guid CustomerId,
    Guid LocationId,
    bool IsActive,
    string? Codice,
    string? SerialNumber,
    string? Categoria,
    string? Marchio,
    string? ExternalId);

public sealed record SyncAgentDto(
    Guid Id,
    Guid TenantId,
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    string Nome,
    string? Email,
    string? Cellulare,
    bool IsActive);
```

> `ProdottoAssistenza.Category` and `.Marca` carry `[JsonPropertyName("categoria")]` /
> `[JsonPropertyName("marchio")]`; the DTO names are what reach the wire, so the mobile field names
> are `categoria` and `marchio`. That is deliberate — the mobile plan mirrors these names.

- [ ] **Step 4: Add the four members to `MobileUserSyncResult`**

In `src/TaskTapAPI.Application/Services/Sync/MobileUserSyncResult.cs`, after `TicketTypes`:

```csharp
    // ── reference entities (additive; older clients ignore these keys) ───────────────────────────
    // Scoped to the caller's own work: the customers their tickets reach, and the agents their
    // tickets reference. Never the tenant book, even for fullScope. See SyncReferenceDtos.cs.

    /// <summary>Contracts of the customers in this payload.</summary>
    public IReadOnlyList<SyncContractDto> Contracts { get; init; } = [];

    /// <summary>Commesse of the customers in this payload.</summary>
    public IReadOnlyList<SyncCommessaDto> Commesse { get; init; } = [];

    /// <summary>Products/services of the customers in this payload.</summary>
    public IReadOnlyList<SyncProdottoAssistenzaDto> ProdottiAssistenza { get; init; } = [];

    /// <summary>Agents referenced by this payload's tickets.</summary>
    public IReadOnlyList<SyncAgentDto> Agents { get; init; } = [];
```

- [ ] **Step 5: Load them in `MobileUserSyncService.GetDeltaAsync`**

Insert immediately before the final `return new MobileUserSyncResult { ... }` initializer, so
`customers`, `locations` and `tickets` are already materialised:

```csharp
        // ── 10. reference entities for the ticket wizard ──────────────────────
        // Placed after customers/tickets so the scope is the set this payload already carries.
        // Delta on (UpdatedAt ?? CreatedAt) for the same reason the schedules block uses it: nothing
        // stamps UpdatedAt on insert, so `UpdatedAt > cutoff` would be NULL > timestamp — false —
        // and a contract created after a device's first sync would never reach it.
        var scopedCustomerIds = customers.Select(c => c.Id).ToList();
        var scopedAgentIds = tickets
            .Where(t => t.AgentId.HasValue)
            .Select(t => t.AgentId!.Value)
            .Distinct()
            .ToList();

        var contractsQuery = _db.Contracts
            .Where(c => c.TenantId == tenantId && scopedCustomerIds.Contains(c.CustomerId));
        var commesseQuery = _db.Commesse
            .Where(c => c.TenantId == tenantId && c.CustomerId.HasValue
                        && scopedCustomerIds.Contains(c.CustomerId.Value));
        var prodottiQuery = _db.Set<ProdottoAssistenza>()
            .Where(p => p.TenantId == tenantId && scopedCustomerIds.Contains(p.CustomerId));
        var agentsQuery = _db.Set<Agent>()
            .Where(a => a.TenantId == tenantId && scopedAgentIds.Contains(a.Id));

        // IsActive is deliberately NOT filtered: see SyncReferenceDtos.cs.
        if (cutoff.HasValue)
        {
            var c = cutoff.Value;
            contractsQuery = contractsQuery.Where(x => (x.UpdatedAt ?? x.CreatedAt) > c);
            commesseQuery = commesseQuery.Where(x => (x.UpdatedAt ?? x.CreatedAt) > c);
            prodottiQuery = prodottiQuery.Where(x => (x.UpdatedAt ?? x.CreatedAt) > c);
            agentsQuery = agentsQuery.Where(x => (x.UpdatedAt ?? x.CreatedAt) > c);
        }

        var contracts = await contractsQuery.ToListAsync();
        var commesse = await commesseQuery.ToListAsync();
        var prodotti = await prodottiQuery.ToListAsync();
        var agents = await agentsQuery.ToListAsync();
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

> `Tipo` is `ContractTipoEnum?`; `Stato` on `Contract` is derived and EF-ignored — do not project it.
> `ProdottoAssistenza.Code`/`Category`/`Marca` are the CLR names behind the `codice`/`categoria`/
> `marchio` JSON names.

- [ ] **Step 6: Run the tests**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~MobileUserSyncReferenceTests`
Expected: PASS, 5/5.

- [ ] **Step 7: Run the whole sync suite and the role-scope HTTP suite**

Run: `dotnet test tests/TaskTapAPI.Tests --filter "FullyQualifiedName~Sync|FullyQualifiedName~MobileSyncRoleScope"`
Expected: PASS. `MobileSyncRoleScopeHttpTests` is the HTTP-level tenant-leak gate — a new scoped
member must not open a hole there.

- [ ] **Step 8: Refresh the committed OpenAPI snapshot**

The mobile repo gates on a committed snapshot. Regenerate it from **this** branch and report the
diff in the hand-off; the mobile plan's Task B2 consumes it.

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap
dotnet build src/TaskTapAPI.Api -c Release
# Regenerate per the repo's existing snapshot procedure (see docs/api/), then:
git diff --stat docs/api/openapi.snapshot.json
```

If the repository has no scripted generation step, run the API and capture `/openapi/v1.json` the
way `Task 1` of the checklist plan did, then commit the result.

- [ ] **Step 9: Commit**

```bash
git add src/TaskTapAPI.Application/Services/Sync/SyncReferenceDtos.cs \
        src/TaskTapAPI.Application/Services/Sync/MobileUserSyncResult.cs \
        src/TaskTapAPI.Application/Services/Sync/MobileUserSyncService.cs \
        docs/api/openapi.snapshot.json \
        tests/TaskTapAPI.Tests/Sync/MobileUserSyncReferenceTests.cs
git commit -m "feat(sync): ship the reference entities a ticket is made of

contracts, commesse, prodottiAssistenza and agents join the mobile delta, scoped
to the caller's own work: the customers their tickets reach, and the agents their
tickets reference. isActive travels as data instead of being filtered, so a
deactivation reaches a device that already cached the row.

Additive: older clients ignore the members.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task A3: make the FK guards name the field they rejected

**Files:**
- Modify: `src/TaskTapAPI.Application/Services/ReferentialIntegrityService.cs:101-138`
- Modify: `src/TaskTapAPI.Application/Exceptions/NotFoundException.cs` (or wherever the type lives — locate it first)
- Modify: `src/TaskTapAPI.Api/Middleware/` — the ProblemDetails mapper that turns `NotFoundException` into a 404 body
- Modify: `src/TaskTapAPI.Application/Services/TicketCommandService.cs:63-104` and `:295-330` (pass the field name)
- Test: `tests/TaskTapAPI.Tests/Services/ReferentialIntegrityFieldTests.cs` (create)

**Interfaces:**
- Consumes: `ReferentialIntegrityService.EnsureExistsAsync<TEntity>` / `EnsureAllExistAsync<TEntity>`.
- Produces, for the mobile plan (Task B6): a 404 ProblemDetails body carrying
  `"field": "customerId"` (camelCase, matching the request body) and the existing `code`, so the
  repair flow can name the dead field instead of parsing an Italian message.

**Keep the status 404.** A cross-tenant id must stay indistinguishable from a missing one; only the
field name is added (spec §9.4).

- [ ] **Step 1: Write the failing test**

```csharp
using FluentAssertions;
using TaskTapAPI.Application.Exceptions;
using TaskTapAPI.Application.Services;
using TaskTapAPI.Core.Entities;
// ... the repository / unit-of-work / tenant-context usings that
// tests/TaskTapAPI.Tests/Services/ReferentialIntegrityServiceTests.cs already uses — copy its
// header and its SUT factory (:30-43) verbatim.

namespace TaskTapAPI.Tests.Services;

public class ReferentialIntegrityFieldTests
{
    [Fact]
    public async Task A_missing_customer_names_the_customerId_field()
    {
        var (sut, _) = /* the factory from ReferentialIntegrityServiceTests */;

        var act = async () => await sut.EnsureExistsAsync<Customer>(Guid.NewGuid(), field: "customerId");

        var ex = await act.Should().ThrowAsync<NotFoundException>();
        ex.Which.Field.Should().Be("customerId");
        ex.Which.Message.Should().Be("Customer not found", "the message must not change: it is logged and matched by existing tests");
    }

    [Fact]
    public async Task A_null_id_still_does_not_throw()
    {
        var (sut, _) = /* factory */;

        await sut.EnsureExistsAsync<Customer>(id: null, field: "customerId");
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `dotnet test tests/TaskTapAPI.Tests --filter FullyQualifiedName~ReferentialIntegrityFieldTests`
Expected: FAIL — `EnsureExistsAsync` has no `field` parameter; `NotFoundException` has no `Field`.

- [ ] **Step 3: Add the optional field to the exception and the service**

In the exception type, add an optional property without touching the message:

```csharp
    /// <summary>
    /// The request field whose value failed to resolve, in the request body's own camelCase
    /// spelling ("customerId"), or null when the caller did not name one. Deliberately not part of
    /// the message: the message is logged and asserted by existing tests, and the client that needs
    /// this is parsing a machine field, not prose.
    /// </summary>
    public string? Field { get; init; }
```

Give `NotFoundException` an optional `string? field = null` constructor parameter and assign it.
Then thread it through both guards:

```csharp
    public async Task EnsureExistsAsync<TEntity>(Guid? id, CancellationToken cancellationToken = default,
        string? field = null)
        where TEntity : TenantEntity
    {
        // ... unchanged body ...
        if (entity is null)
        {
            throw new NotFoundException($"{typeof(TEntity).Name} not found", field);
        }
    }
```

and the same optional `string? field = null` on `EnsureAllExistAsync`, carrying it into its throw.
Update `IReferentialIntegrityService` to match.

- [ ] **Step 4: Name the field at every ticket call site**

In `TicketCommandService.CreateAsync`:

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
```

Leave `EnsureTicketStatusExistsAsync` / `EnsureTicketTypeExistsAsync` alone — they already carry
their own codes and are not repairable by picking a different row.

Do the same at the update call sites (`:295-330`).

- [ ] **Step 5: Surface the field in the ProblemDetails body**

In the mapper that builds the 404 response, add the field to `extensions` when present:

```csharp
        if (exception.Field is { } field)
            extensions["field"] = field;
```

Match the surrounding extension-writing style in that file exactly.

- [ ] **Step 6: Run the tests**

Run: `dotnet test tests/TaskTapAPI.Tests --filter "FullyQualifiedName~ReferentialIntegrity|FullyQualifiedName~TicketCommandService"`
Expected: PASS. `ReferentialIntegrityServiceTests` must stay green unchanged — the added parameter is
optional and the message is untouched.

- [ ] **Step 7: Commit**

```bash
git add src/TaskTapAPI.Application/Services/ReferentialIntegrityService.cs \
        src/TaskTapAPI.Application/Services/ITicketCommandService.cs \
        src/TaskTapAPI.Application/Services/TicketCommandService.cs \
        src/TaskTapAPI.Application/Exceptions/ \
        src/TaskTapAPI.Api/Middleware/ \
        tests/TaskTapAPI.Tests/Services/ReferentialIntegrityFieldTests.cs
git commit -m "feat(api): name the offending field on a ticket FK rejection

A 404 stays a 404 — a cross-tenant id must remain indistinguishable from a missing
one — but the body now carries the request field that failed to resolve, so the
mobile repair flow can name it instead of parsing an Italian message.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

# Phase B — Mobile

**Working directory for every task in this phase:** `/mnt/d/AEA/Sviluppi/TaskTap/mobile`.
Every file path below is relative to it. `mobile/` is a nested repo: commit there, never from the root.

---

### Task B1: Drift schema 37 — four reference tables, one migration step, one cursor bump

**Files:**
- Modify: `lib/data/local/app_database.dart` (tables, `@DriftDatabase` list, `schemaVersion`, migration step)
- Create: `test/data/local/migration_v37_test.dart`
- Modify: `test/data/sync/sync_service_checklist_test.dart` (the cursor assertion at the `'v9'` expectation)

**Interfaces:**
- Consumes: nothing.
- Produces: four Drift tables — `contracts`, `commesse`, `prodotti_assistenza`, `agents` — and
  `AppDatabase.syncCursorGeneration == 'v10'`.

- [ ] **Step 1: Write the failing migration test**

Mirror `test/data/local/migration_v36_test.dart:1-122` exactly: create the current schema in a file
database, drop the new tables and rewind `user_version`, reopen so Drift runs the real
`onUpgrade(36 -> 37)`, and assert against a database that really lacks the objects, with
pre-existing rows.

```dart
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 36 -> 37: the reference mirror the ticket wizard needs offline (contracts, commesse,
/// prodotti assistenza, agents).
///
/// Same technique as migration_v36_test.dart: build the current schema, remove exactly what the step
/// adds, rewind user_version, reopen so Drift runs the real onUpgrade(36 -> 37) against a database
/// that really lacks the objects, with pre-existing rows.
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

  const newTables = [
    'contracts',
    'commesse',
    'prodotti_assistenza',
    'agents',
  ];

  Future<List<String>> master(AppDatabase db, String type) async =>
      (await db.customSelect("SELECT name FROM sqlite_master WHERE type = '$type'").get())
          .map((r) => r.read<String>('name'))
          .toList();

  test('a v36 database upgraded to 37 gains the four reference tables', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    await db.close();

    for (final t in newTables) {
      expect(await master(db, 'table'), isNot(contains(t)));
    }

    final reopened = AppDatabase(
      NativeDatabase(file, setup: (raw) {
        for (final t in newTables) {
          raw.execute('DROP TABLE IF EXISTS $t');
        }
        raw.execute('PRAGMA user_version = 36');
      }),
    );
    addTearDown(reopened.close);

    await (reopened.select(reopened.customers)..limit(1)).get();

    expect(await master(reopened, 'table'), containsAll(newTables));
  });

  test('the cursor generation is bumped so every device re-bootstraps once', () {
    expect(AppDatabase.syncCursorGeneration, 'v10');
  });

  test('a queued ticket survives the upgrade', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.into(db.pendingTickets).insert(
          PendingTicketsCompanion.insert(
            id: 'queued-1',
            payloadJson: '{}',
            createdAt: DateTime.utcNow(),
          ),
        );
    await db.close();

    final reopened = AppDatabase(
      NativeDatabase(file, setup: (raw) {
        for (final t in newTables) {
          raw.execute('DROP TABLE IF EXISTS $t');
        }
        raw.execute('PRAGMA user_version = 36');
      }),
    );
    addTearDown(reopened.close);
    await (reopened.select(reopened.customers)..limit(1)).get();

    expect((await reopened.select(reopened.pendingTickets).get()).map((r) => r.id), ['queued-1'],
        reason: 'spec 11.3: a sync-generation bump must not touch queued work');
  });
}
```

> Check `PendingTickets`' real column names before writing this — the companion's required set is
> whatever `lib/data/local/app_database.dart` declares. If the table is called something else on the
> mobile side, use that name; the assertion is about row survival, not the table's spelling.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/local/migration_v37_test.dart`
Expected: FAIL — the tables do not exist, and `syncCursorGeneration` is still `'v9'`.

- [ ] **Step 3: Declare the four tables**

In `lib/data/local/app_database.dart`, following the `Customers` shape (`:28-48`) — no `tableName`
override, Drift derives the snake_case name:

```dart
/// Contracts of the customers this technician's work reaches. Mirrored so the ticket wizard's
/// Cliente→Contratto picker is filled offline (spec 7.4). `isActive` is carried, not filtered: a
/// contract deactivated on the server must arrive here as a delta, or a device that cached it would
/// offer it forever (spec 6.4).
class Contracts extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// `Numero` and `Codice` are both human references a technician may read off the paper contract;
  /// the picker shows whichever is present.
  TextColumn get numero => text().nullable()();
  TextColumn get codice => text().nullable()();
  IntColumn get tipo => integer().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Commesse (`Codice`, `Descrizione`) of the customers this technician's work reaches.
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

/// Products / services (`ProdottoAssistenza`) of the customers this technician's work reaches.
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

/// Agents (`Agent`), mirrored only for the ones this technician's tickets already reference — the
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

- [ ] **Step 4: Register them, bump the schema, add the migration step**

Add the four classes to the `@DriftDatabase(tables: [...])` list after `ChecklistOmittedTickets`,
set `int get schemaVersion => 37;`, and append to `onUpgrade` after the `from < 36` block:

```dart
        if (from < 37) {
          // The reference mirror the ticket wizard needs offline. New tables only: nothing is
          // backfilled here, and the delta cursor is bumped to v10 so a device that already synced
          // receives the four members once, as a bootstrap (see SyncService's prune).
          await m.createTable(contracts);
          await m.createTable(commesse);
          await m.createTable(prodottiAssistenza);
          await m.createTable(agents);
          await _createReferenceIndexes();
        }
```

and add the helper next to `_createChecklistIndexes` (`:1321-1335`), calling it from `onCreate` too:

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

- [ ] **Step 5: Bump the cursor generation**

```dart
  static const String syncCursorGeneration = 'v10';
```

and update the existing assertion in `test/data/sync/sync_service_checklist_test.dart` from `'v9'` to
`'v10'`. That test is the guard that a generation bump is deliberate, not a copy-paste.

- [ ] **Step 6: Run the migration, database and sync suites**

Run: `flutter test test/data/local/ test/data/sync/`
Expected: PASS. If `migration_v36_test.dart` or `app_database_test.dart` assert the schema version
directly, relax them the same way `migration_v35_test.dart` was relaxed for v36 (assert `>=`, not
`==`), and note it in the ledger.

- [ ] **Step 7: Commit**

```bash
git add lib/data/local/app_database.dart lib/data/local/app_database.g.dart \
        test/data/local/migration_v37_test.dart \
        test/data/sync/sync_service_checklist_test.dart
git commit -m "feat(mobile): Drift schema 37 - the reference mirror the wizard needs offline

contracts, commesse, prodotti_assistenza and agents, one from<37 step, cursor
generation v9 -> v10 so every device re-bootstraps once. Nothing existing is
altered: a queued ticket survives the upgrade.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

> Run `dart run build_runner build --delete-conflicting-outputs` before committing so
> `app_database.g.dart` is regenerated, and stage it explicitly.

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

Mirror `test/data/sync/sync_service_checklist_test.dart:1-40` for the fixture helpers
(`_dt`, `_list` are file-private in `sync_dto.dart`; the test uses raw JSON).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

void main() {
  Map<String, dynamic> minimal() => {
    'syncedAt': '2026-10-08T08:00:00Z',
    'since': null,
    'schedules': <Object>[],
    'draftReports': <Object>[],
    'customers': <Object>[],
    'locations': <Object>[],
    'tickets': <Object>[],
    'materiali': <Object>[],
    'cantieri': <Object>[],
    'ticketStatuses': <Object>[],
    'ticketTypes': <Object>[],
    'colleagues': <Object>[],
  };

  test('the four reference members parse', () {
    final p = SyncResultDto.fromJson({
      ...minimal(),
      'contracts': [
        {
          'id': 'c1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
          'name': 'Manutenzione', 'customerId': 'cu', 'locationId': null,
          'startDate': '2026-01-01T00:00:00Z', 'endDate': null, 'isActive': true,
          'numero': 'N-1', 'codice': null, 'tipo': 0, 'externalId': null,
        },
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
    expect(p.commesse.single.codice, 'C-1');
    expect(p.prodottiAssistenza.single.categoria, isNull);
    expect(p.agents.single.nome, 'Rossi');
    expect(
      [p.carriesContracts, p.carriesCommesse, p.carriesProdottiAssistenza, p.carriesAgents],
      [true, true, true, true],
    );
  });

  /// The discipline the checklist members already established, and the reason the bootstrap prune
  /// is safe: a backend that predates this feature sends none of the four keys, and the client must
  /// treat that as "nothing to say", not as "every reference row was deleted".
  test('an older backend leaves every carries flag false', () {
    final p = SyncResultDto.fromJson(minimal());

    expect(
      [p.carriesContracts, p.carriesCommesse, p.carriesProdottiAssistenza, p.carriesAgents],
      [false, false, false, false],
    );
    expect(p.contracts, isEmpty);
  });

  test('a bootstrap is recognisable by a null since', () {
    expect(SyncResultDto.fromJson(minimal()).since, isNull);
    expect(
      SyncResultDto.fromJson({...minimal(), 'since': '2026-10-07T00:00:00Z'}).since,
      isNotNull,
    );
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/sync/sync_reference_dto_test.dart`
Expected: FAIL — `contracts` is not a member of `SyncResultDto`.

- [ ] **Step 3: Add the four DTOs**

In `lib/data/sync/sync_dto.dart`, following the `CantiereDto` shape (`:513-562`), using the shared
`_dt` / `_list` helpers at the file bottom:

```dart
/// A contract of a customer in this technician's work scope. Mirrored for the Cliente→Contratto
/// picker (spec 7.4). [isActive] is stored, not filtered on read of the payload — the picker is what
/// hides a deactivated contract.
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

Add `CommessaSyncDto`, `ProdottoAssistenzaSyncDto` and `AgentSyncDto` in the same shape, one field
per member of the record it mirrors (`SyncReferenceDtos.cs`, Task A2). `isActive` defaults to `true`
when the key is absent, matching the server's own default.

- [ ] **Step 4: Add the members and the carries flags to `SyncResultDto`**

Members, with the const-constructor default `const []`, and in `fromJson`:

```dart
      contracts: _list(j['contracts'], ContractSyncDto.fromJson),
      commesse: _list(j['commesse'], CommessaSyncDto.fromJson),
      prodottiAssistenza: _list(j['prodottiAssistenza'], ProdottoAssistenzaSyncDto.fromJson),
      agents: _list(j['agents'], AgentSyncDto.fromJson),
```

Flags, set by key presence exactly as `carriesChecklist` is (`:124-125`):

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
  /// bootstrap prune would wipe the mirror. One flag per entity rather than one for the group: each
  /// is pruned independently, and a partial rollout must not be read as a deletion.
  final bool carriesContracts;
  final bool carriesCommesse;
  final bool carriesProdottiAssistenza;
  final bool carriesAgents;
```

Also extend the existing `checklistWireKeys` set if it is used as a "known members" registry, and add
the four keys to whatever list that set feeds.

- [ ] **Step 5: Add the contract assertions**

In `test/contract/sync_inbound_contract_test.dart`, extend the carries-flag assertions
(`:145-182`) with the four new flags, using the same `full` / `older` pair the file already builds:

```dart
        expect(full.carriesContracts, isTrue);
        expect(full.carriesCommesse, isTrue);
        expect(full.carriesProdottiAssistenza, isTrue);
        expect(full.carriesAgents, isTrue);
        ...
        expect(older.carriesContracts, isFalse,
            reason: 'an older backend must NOT look like "every contract was deleted"');
```

Regenerate `test/contract/openapi.snapshot.json` from the Task A2 snapshot — copy it from the
backend branch explicitly, do not copy the root working tree's file, which is a different branch's
contract.

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

### Task B3: write the reference rows, prune them on bootstrap

**Files:**
- Modify: `lib/data/sync/sync_service.dart`
- Create: `lib/data/reference/reference_cache_repository.dart`
- Test: `test/data/sync/sync_reference_test.dart` (create)
- Test: `test/data/reference/reference_cache_repository_test.dart` (create)

**Interfaces:**
- Consumes: `ContractSyncDto`, `CommessaSyncDto`, `ProdottoAssistenzaSyncDto`, `AgentSyncDto` (Task B2); the four Drift tables (Task B1).
- Produces, for Task B4:
  - `ReferenceCacheRepository(AppDatabase db, Dio dio)`
  - `Future<void> materializeContract(ContractSyncDto c)` / `materializeCommessa` / `materializeProdotto` / `materializeAgent`
  - `Future<void> materializeContracts(Iterable<ContractSyncDto> c)` and the three siblings
  - `Future<List<ContractRow>> contractsForCustomer(String customerId)` and the three siblings
  - `final referenceCacheProvider = Provider<ReferenceCacheRepository>(...)`

- [ ] **Step 1: Write the failing sync test**

```dart
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

Map<String, dynamic> base() => {
  'syncedAt': '2026-10-08T08:00:00Z',
  'since': null,
  'schedules': <Object>[],
  'draftReports': <Object>[],
  'customers': <Object>[],
  'locations': <Object>[],
  'tickets': <Object>[],
  'materiali': <Object>[],
  'cantieri': <Object>[],
  'ticketStatuses': <Object>[],
  'ticketTypes': <Object>[],
  'colleagues': <Object>[],
};

Map<String, dynamic> reference() => {
  'contracts': [
    {'id': 'c1', 'tenantId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'updatedAt': null,
     'name': 'Manutenzione', 'customerId': 'cu', 'locationId': null,
     'startDate': '2026-01-01T00:00:00Z', 'endDate': null, 'isActive': true,
     'numero': 'N-1', 'codice': null, 'tipo': 0, 'externalId': null},
  ],
  'commesse': <Object>[],
  'prodottiAssistenza': <Object>[],
  'agents': <Object>[],
};

void main() {
  late AppDatabase db;
  late MockDio dio;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
  });
  tearDown(() => db.close());

  void respondWith(Map<String, dynamic> body) {
    when(() => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok(body));
  }

  test('a payload with the reference members fills the local mirror', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    expect((await db.select(db.contracts).get()).single.name, 'Manutenzione');
  });

  test('a payload from an older backend leaves every cached reference row alone', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    respondWith(base()); // no reference keys at all
    await SyncService(db: db, dio: dio).sync();

    expect(await db.select(db.contracts).get(), hasLength(1));
  });

  test('a bootstrap prunes a row the payload no longer contains', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    // Next launch: a fresh bootstrap (since == null) that no longer lists c1.
    respondWith({...base(),
      'contracts': <Object>[], 'commesse': <Object>[],
      'prodottiAssistenza': <Object>[], 'agents': <Object>[]});
    await SyncService(db: db, dio: dio).sync();

    expect(await db.select(db.contracts).get(), isEmpty,
        reason: 'spec 6.4: a hard delete is only learnable from a complete payload');
  });

  test('an incremental sync never prunes', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    // A delta: since is set, so the payload is NOT the complete set.
    respondWith({...base(), 'since': '2026-10-08T07:00:00Z',
      'contracts': <Object>[], 'commesse': <Object>[],
      'prodottiAssistenza': <Object>[], 'agents': <Object>[]});
    await SyncService(db: db, dio: dio).sync();

    expect(await db.select(db.contracts).get(), hasLength(1),
        reason: 'a delta says nothing about rows it omits');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/sync/sync_reference_test.dart`
Expected: FAIL — `db.contracts` is not defined until Task B1 regenerates the `.g.dart`; once it is,
the sync does not yet write the rows.

- [ ] **Step 3: Write the cache repository**

Create `lib/data/reference/reference_cache_repository.dart` with the upserts, the per-customer
reads, and the bootstrap prune. The upserts are one body shared with the sync, so the picker's
materialise path and the sync path can never diverge:

```dart
/// The four reference tables, read and written in one place.
///
/// The sync writes them from the delta payload; the picker writes them again when a search result is
/// selected online (spec 7.4), and both go through the same upsert so a row materialised by a pick is
/// indistinguishable from one the delta delivered.
class ReferenceCacheRepository {
  ReferenceCacheRepository(this._db);

  final AppDatabase _db;

  Future<void> upsertContracts(Iterable<ContractSyncDto> list) async {
    for (final c in list) {
      await _db.into(_db.contracts).insertOnConflictUpdate(
            ContractsCompanion.insert(
              id: c.id,
              tenantId: c.tenantId,
              createdAt: c.createdAt,
              updatedAt: Value(c.updatedAt),
              name: c.name,
              customerId: c.customerId,
              locationId: Value(c.locationId),
              startDate: c.startDate,
              endDate: Value(c.endDate),
              isActive: Value(c.isActive),
              numero: Value(c.numero),
              codice: Value(c.codice),
              tipo: Value(c.tipo),
              externalId: Value(c.externalId),
            ),
          );
    }
  }

  // upsertCommesse / upsertProdottiAssistenza / upsertAgents in the same shape.

  /// Bootstrap only: the payload is the complete scoped set, so anything it omits is gone from the
  /// server. Called when `since == null` and only for the entities the payload actually carries —
  /// a delta says nothing about the rows it omits, and a backend that predates the members says
  /// nothing at all (spec 6.4).
  Future<void> pruneContracts(Set<String> keepIds) => (_db.delete(_db.contracts)
        ..where((t) => t.id.isNotIn(keepIds)))
      .go();

  // pruneCommesse / pruneProdottiAssistenza / pruneAgents in the same shape.

  /// The picker's local half: the active contracts of one customer, in name order.
  Future<List<Contract>> contractsForCustomer(String customerId) =>
      (_db.select(_db.contracts)
            ..where((c) => c.customerId.equals(customerId) & c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  // commesseForCustomer / prodottiForCustomer / activeAgents in the same shape.
}
```

and at the bottom of the file:

```dart
final referenceCacheProvider = Provider<ReferenceCacheRepository>(
  (ref) => ReferenceCacheRepository(ref.watch(appDatabaseProvider)),
);
```

- [ ] **Step 4: Wire it into `SyncService.sync()`**

In the transaction, after `_replaceColleagues`:

```dart
        await _applyReferenceCache(payload);
```

and the method, mirroring `_applyChecklist`'s gating (`sync_service.dart:88-111`):

```dart
  /// The reference mirror. Each entity is skipped wholesale when the payload does not carry it, and
  /// pruned only on a bootstrap — see [ReferenceCacheRepository]. Skipping is what keeps an older
  /// backend from looking like "every reference row was deleted".
  Future<void> _applyReferenceCache(SyncResultDto payload) async {
    final cache = ReferenceCacheRepository(db);
    final isBootstrap = payload.since == null;

    if (payload.carriesContracts) {
      await cache.upsertContracts(payload.contracts);
      if (isBootstrap) {
        await cache.pruneContracts(payload.contracts.map((c) => c.id).toSet());
      }
    }
    if (payload.carriesCommesse) {
      await cache.upsertCommesse(payload.commesse);
      if (isBootstrap) {
        await cache.pruneCommesse(payload.commesse.map((c) => c.id).toSet());
      }
    }
    if (payload.carriesProdottiAssistenza) {
      await cache.upsertProdottiAssistenza(payload.prodottiAssistenza);
      if (isBootstrap) {
        await cache.pruneProdottiAssistenza(
            payload.prodottiAssistenza.map((p) => p.id).toSet());
      }
    }
    if (payload.carriesAgents) {
      await cache.upsertAgents(payload.agents);
      if (isBootstrap) {
        await cache.pruneAgents(payload.agents.map((a) => a.id).toSet());
      }
    }
  }
```

- [ ] **Step 5: Write the repository test**

`test/data/reference/reference_cache_repository_test.dart` — an in-memory `AppDatabase`, insert two
contracts for different customers, and assert `contractsForCustomer` returns only the active one of
the right customer, in name order; plus that `pruneContracts` removes exactly the ids not passed.

- [ ] **Step 6: Run the sync and reference suites**

Run: `flutter test test/data/sync/ test/data/reference/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/data/sync/sync_service.dart lib/data/reference/reference_cache_repository.dart \
        test/data/sync/sync_reference_test.dart \
        test/data/reference/reference_cache_repository_test.dart
git commit -m "feat(mobile): mirror the reference entities, prune them on bootstrap

One upsert path shared by the delta and by the picker's materialise step, so a
row found by an online search is indistinguishable from one the delta sent.
Pruning runs only on a bootstrap, where the payload is the complete scoped set.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B4: the reference picker — local first, server search, materialise the pick

**Files:**
- Create: `lib/features/ticket/reference_picker_field.dart`
- Modify: `lib/features/ticket/ticket_providers.dart` (add the four per-customer providers)
- Modify: `lib/features/ticket/steps/step_cliente_sede.dart`
- Modify: `lib/features/ticket/steps/step_dettagli_ticket.dart`
- Test: `test/features/ticket/reference_picker_field_test.dart` (create)

**Interfaces:**
- Consumes: `referenceCacheProvider` (Task B3); `adminApiClientProvider` and its `pagedItems` list calls; `connectivity` state.
- Produces, for Task B5: `ReferencePickerField({required String label, required List<ReferenceOption> items, required String? selectedId, required ValueChanged<String?> onChanged, Future<List<ReferenceOption>> Function(String query)? search, Future<void> Function(ReferenceOption)? onMaterialize, String? emptyHint})` and `class ReferenceOption { final String id; final String label; final String? subtitle; }`.

**The contract this widget implements (spec §7.3, §7.4):**
- It always shows the local mirror first. Empty mirror is a *labelled* state, never a blank control.
- When online, typing also asks the server and appends what it returns.
- Selecting a row that came from the server **materialises it locally before** reporting the
  selection, so the ticket created from it validates and the row is present offline next time.
- When offline, the search affordance is disabled with an explicit note rather than failing.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/features/ticket/reference_picker_field.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('an empty mirror is a labelled state, not a dead control', (tester) async {
    await tester.pumpWidget(host(ProviderScope(
      child: ReferencePickerField(
        label: 'Contratto',
        items: const [],
        selectedId: null,
        onChanged: (_) {},
        emptyHint: 'Nessun contratto in cache. Cerca online.',
      ),
    )));

    expect(find.text('Nessun contratto in cache. Cerca online.'), findsOneWidget);
  });

  testWidgets('a local item is offered without any network call', (tester) async {
    String? picked;
    await tester.pumpWidget(host(ProviderScope(
      child: ReferencePickerField(
        label: 'Contratto',
        items: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
        selectedId: null,
        onChanged: (v) => picked = v,
      ),
    )));

    await tester.tap(find.byKey(const ValueKey('reference-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manutenzione caldaie'));
    await tester.pumpAndSettle();

    expect(picked, 'c1');
  });

  testWidgets('a pick that came from the server is materialised before it is reported', (tester) async {
    final order = <String>[];
    await tester.pumpWidget(host(ProviderScope(
      child: ReferencePickerField(
        label: 'Contratto',
        items: const [],
        selectedId: null,
        onChanged: (_) => order.add('changed'),
        search: (_) async => const [ReferenceOption(id: 'c9', label: 'Trovato online')],
        onMaterialize: (_) async => order.add('materialized'),
      ),
    )));

    await tester.enterText(find.byKey(const ValueKey('reference-field-input')), 'trovato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trovato online'));
    await tester.pumpAndSettle();

    expect(order, ['materialized', 'changed'],
        reason: 'spec 7.4: the row must exist locally before the ticket can use it');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/ticket/reference_picker_field_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Implement the widget**

A `ConsumerStatefulWidget` that composes `AppLookupField` (`lib/core/widgets/lookup_field.dart:37`)
for the local half — it already renders the suggestion list, the resolved label, the clear-on-empty
behaviour and the `emptyCacheHint` — and adds a search-on-demand pass:

- `initState`/`didUpdateWidget`: build `items` for `AppLookupField` from `widget.items` merged with
  anything the search has returned this session, de-duplicated by id, local wins.
- On non-empty free text, when connectivity allows: debounce 400 ms, call `widget.search`, merge the
  results, `setState`. On failure, keep the local list and do not surface an error — a search that
  fails is not a failure of the field.
- `onSelected(id)`: resolve the id against the merged list; if it came from the server,
  `await widget.onMaterialize(option)` **first**, then `widget.onChanged(id)`. Await it — the whole
  point is that the row exists before the ticket references it.
- Offline: pass an `emptyCacheHint` that names the offline state, and do not call `search`.

Use the connectivity idiom already in the ticket feature rather than inventing one — grep for the
existing online check (`ensureOnlineOrWarn`, `step_cliente_sede.dart:63`) and reuse whatever
predicate it consults.

Keep it under ~180 lines. If it grows past that, split the merge/rank logic into a pure function in
the same file so it can be unit-tested without a widget pump.

- [ ] **Step 4: Add the per-customer providers**

In `lib/features/ticket/ticket_providers.dart`, following `allCustomersProvider`'s shape
(`schedule_providers.dart:137-143`):

```dart
/// The contracts of one customer, from the local mirror, active only. Family-scoped because the
/// wizard changes customer mid-flow and the picker must follow it.
final contractsForCustomerProvider =
    FutureProvider.autoDispose.family<List<Contract>, String>((ref, customerId) async {
  return ref.watch(referenceCacheProvider).contractsForCustomer(customerId);
});
```

and `commesseForCustomerProvider`, `prodottiForCustomerProvider`, `activeAgentsProvider` in the same
shape. `activeAgentsProvider` is not customer-scoped (an agent is not customer-scoped on the server
either).

- [ ] **Step 5: Wire the four fields into the wizard**

In `step_cliente_sede.dart`, add Contratto below Cliente/Sede, keyed by the customer as web keys it
(`TicketCreatePanel.tsx:512-520` remounts on a customer change for exactly this reason):

```dart
          if (widget.state.customerId case final customerId?)
            ReferencePickerField(
              key: ValueKey('contratto-$customerId'),
              label: 'Contratto',
              items: [for (final c in contracts) ReferenceOption(
                id: c.id,
                label: c.name,
                subtitle: c.numero ?? c.codice,
              )],
              selectedId: widget.state.contractId,
              onChanged: (id) => widget.onChanged(widget.state.copyWith(
                contractId: id,
                clearContractId: id == null,
              )),
              search: (q) => ref.read(referenceSearchProvider).contracts(customerId: customerId, q: q),
              onMaterialize: (o) => ref.read(referenceCacheProvider)
                  .upsertContracts(await ref.read(referenceSearchProvider).contracts(...)),
              emptyHint: 'Nessun contratto in cache per questo cliente.',
            ),
```

Do the same for Commessa (`step_cliente_sede.dart`) and for Prodotti (`step_dettagli_ticket.dart`,
multi-select — reuse `MultiEntityPicker`'s semantics or a `ReferencePickerField` with
`multi: true`; whichever is smaller, but the materialise-then-report order must hold for every
selected row).

For each `search:` and `onMaterialize:` pair, add the corresponding method on a
`ReferenceSearchClient` that calls the list endpoints from Task A1 with `q`, `customerId` and
`pageSize: 50`, and parses the response with the **same** `ContractSyncDto.fromJson` the sync uses —
that is what makes the materialised row identical to a synced one.

- [ ] **Step 6: Add the Cantiere field**

Cantieri are already mirrored (`allCantieriProvider`) and already on the create contract, so this is
a local-only `ReferencePickerField` with no `search:`. Add it to `step_dettagli_ticket.dart`.

- [ ] **Step 7: Run the picker and wizard suites**

Run: `flutter test test/features/ticket/`
Expected: PASS. The existing `step_cliente_sede` tests must stay green — the new field is additive,
and the customer-change reset already clears `locationId`, so add `contractId` to that same reset.

- [ ] **Step 8: Commit**

```bash
git add lib/features/ticket/reference_picker_field.dart \
        lib/features/ticket/reference_search_client.dart \
        lib/features/ticket/ticket_providers.dart \
        lib/features/ticket/steps/step_cliente_sede.dart \
        lib/features/ticket/steps/step_dettagli_ticket.dart \
        lib/features/ticket/new_ticket_form_state.dart \
        test/features/ticket/reference_picker_field_test.dart
git commit -m "feat(mobile): reference pickers - local mirror first, server search on demand

The widget shows the mirror, searches the server when online, and writes the
selected row into the mirror before reporting the selection, so the ticket
created from it validates and the row is present offline next time. An empty
mirror is a labelled state with a way forward, never a dead control.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B5: the create path sends the new fields, and Riferimento stops sending a User id

**Files:**
- Modify: `lib/features/ticket/new_ticket_form_state.dart`
- Modify: `lib/features/ticket/ticket_api_client.dart`
- Modify: `lib/features/ticket/steps/step_dettagli_ticket.dart` (Riferimento, Note interne)
- Modify: `lib/features/ticket/new_ticket_form_screen.dart`
- Test: `test/features/ticket/ticket_api_client_test.dart`
- Test: `test/features/ticket/new_ticket_form_state_test.dart` (create if absent)

**Interfaces:**
- Consumes: `ReferencePickerField` (Task B4); `TicketCommand.CreateAsync`'s field list (`TicketCommands.cs`).
- Produces: `NewTicketFormState` gains `contractId`, `commessaId`, `cantiereId`, `prodottoAssistenzaIds`, `internalNotes` with matching `clear*` flags; `createTicket` sends them.

**Two things happen here, and both matter.** The parity fields are the feature. The `agentId` fix is a
**live defect**: `CreateTicketCommand.AgentId` is guarded by `EnsureExistsAsync<Agent>`, and this
client populates it from the technicians list, so any ticket saved with "Riferimento" set is rejected
404 (spec §2.7).

- [ ] **Step 1: Write the failing API test**

```dart
  test('the create body carries the reference fields', () async {
    Map<String, dynamic>? body;
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((inv) async {
      body = inv.namedArguments[#data] as Map<String, dynamic>;
      return Response(data: {'id': 't1'}, statusCode: 201,
          requestOptions: RequestOptions(path: '/api/tickets'));
    });

    await client.createTicket(
      title: 'Caldaia', customerId: 'cu', locationId: 'l', statusId: 1, typeId: 1,
      contractId: 'c1', commessaId: 'm1', cantiereId: 'k1',
      prodottoAssistenzaIds: const ['p1', 'p2'], internalNotes: 'nota interna',
    );

    expect(body!['contractId'], 'c1');
    expect(body!['commessaId'], 'm1');
    expect(body!['cantiereId'], 'k1');
    expect(body!['prodottoAssistenzaIds'], ['p1', 'p2']);
    expect(body!['internalNotes'], 'nota interna');
  });

  test('an unset reference field is omitted, not sent as null', () async {
    Map<String, dynamic>? body;
    // ... same capture ...
    await client.createTicket(
      title: 'Caldaia', customerId: 'cu', locationId: 'l', statusId: 1, typeId: 1,
      prodottoAssistenzaIds: const [],
    );

    expect(body!.containsKey('contractId'), isFalse);
    expect(body!.containsKey('prodottoAssistenzaIds'), isTrue,
        reason: 'an explicit empty list means "covers no asset", which is not the same as unset');
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/ticket/ticket_api_client_test.dart`
Expected: FAIL — `createTicket` takes no `contractId`.

- [ ] **Step 3: Extend the state and the client**

Add to `NewTicketFormState`: `final String? contractId;`, `final String? commessaId;`,
`final String? cantiereId;`, `final List<String> prodottoAssistenzaIds;`,
`final String? internalNotes;`, each with the matching `clear*` flag in `copyWith` — the existing
file's convention, which the wizard's back-navigation depends on.

`isValid` is **unchanged**: none of these is required to create a ticket, and making one required
would turn a sparse mirror into a dead wizard, which is the failure this whole plan exists to fix.

In `ticket_api_client.createTicket`, add the parameters and the body entries using the same
null-aware element syntax the file already uses (`'assignedUserId': ?assignedUserId`):

```dart
        'contractId': ?contractId,
        'commessaId': ?commessaId,
        'cantiereId': ?cantiereId,
        'internalNotes': ?internalNotes,
```

`prodottoAssistenzaIds` is sent whenever the caller passes a non-null list, **including an empty
one** — on create, empty and omitted both mean "no covered assets", but an explicit empty list is
what the edit path will need to clear them, and one wire shape is better than two.

- [ ] **Step 4: Fix Riferimento — pick an Agent, not a User**

In `step_dettagli_ticket.dart`, replace the `techniciansProvider` source at the Riferimento field
(`:236-272`) with the mirrored agents:

```dart
            // Ticket.AgentId is an Agent foreign key: the server guards it with
            // EnsureExistsAsync<Agent> and a User id can never satisfy that. This field used to be
            // fed from the technicians list, which made every ticket saved with a Riferimento fail
            // with a 404 (spec 2.7). It now picks from the mirrored agents, and searches the server
            // for one outside the mirror.
            final agentsAsync = ref.watch(activeAgentsProvider);
```

Keep the label "Riferimento" and the tap-sheet interaction; only the data source and the
search/materialise behaviour change. When the mirror is empty, `ReferencePickerField`'s labelled
empty state applies.

- [ ] **Step 5: Add the Note interne field**

Web exposes `internalNotes` and the create contract accepts it. Add an `AppTextField.multiline` under
Descrizione in `step_dettagli_ticket.dart`, labelled "Note interne", with the hint that it is
office-only — a technician should not have to guess who reads it.

- [ ] **Step 6: Send the fields from the wizard**

In `new_ticket_form_screen.dart`'s `_onSubmit`, pass the new state members to
`queue.create(...)`, and make sure the same values go into whatever the queue persists, so a ticket
queued offline is sent with its contract, commessa, cantiere, covered assets and internal notes on
reconnect.

- [ ] **Step 7: Delete the stale docstring**

`new_ticket_form_screen.dart:122-125` claims the ticket "has no client-supplied dedup key … never
auto-retried". Both halves are false — the queue mints a `clientId` and retries `failed` rows
(`ticket_creation_queue.dart`). Read the queue, confirm, and replace the comment with what the code
does. Do the same for the `ticket_creation_queue.dart` header if it contradicts the code. A comment
that describes a worse system than the one that exists is how the next person deletes a fix.

- [ ] **Step 8: Run the ticket suite**

Run: `flutter test test/features/ticket/ test/data/tickets/`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/features/ticket/new_ticket_form_state.dart \
        lib/features/ticket/ticket_api_client.dart \
        lib/features/ticket/new_ticket_form_screen.dart \
        lib/features/ticket/steps/step_dettagli_ticket.dart \
        test/features/ticket/ticket_api_client_test.dart \
        test/features/ticket/new_ticket_form_state_test.dart
git commit -m "feat(mobile): ticket create parity, and Riferimento picks an Agent

The wizard now sends contractId, commessaId, cantiereId, prodottoAssistenzaIds and
internalNotes, the fields web has had since the merged Interventi panel.

Riferimento was a live defect: Ticket.AgentId is guarded by EnsureExistsAsync<Agent>
and this field was fed from the technicians list, so every ticket saved with a
Riferimento set was rejected 404. It now picks from the mirrored agents.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task B6: repair a queued ticket whose FK is gone, instead of a bare toast

**Files:**
- Create: `lib/data/tickets/ticket_fk_repair.dart`
- Modify: `lib/data/tickets/ticket_creation_queue.dart`
- Modify: `lib/features/ticket/new_ticket_form_screen.dart` (surface the repair sheet)
- Test: `test/data/tickets/ticket_fk_repair_test.dart` (create)

**Interfaces:**
- Consumes: the ProblemDetails `field` extension (Task A3); `TicketCreationQueue`'s persisted row; `ReferencePickerField` (Task B4).
- Produces: `TicketFkProblem? parseFkProblem(Object error)` returning `{ String field, String message }`, and `Future<bool> repairQueuedTicket(String queueId, String field, String newValue)`.

**The contract (spec §6.6):** the technician is never asked to retype the ticket. The queue row is
edited in place and retried, and nothing typed is lost.

- [ ] **Step 1: Write the failing test**

```dart
  test('a 404 ProblemDetails naming customerId yields a repairable problem', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/tickets'),
      response: Response(
        statusCode: 404,
        data: {
          'title': 'Customer not found',
          'status': 404,
          'extensions': {'field': 'customerId'},
        },
        requestOptions: RequestOptions(path: '/api/tickets'),
      ),
    );

    final problem = parseFkProblem(error);
    expect(problem!.field, 'customerId');
  });

  test('a 404 with no field is not repairable', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/tickets'),
      response: Response(statusCode: 404, data: {'title': 'Not found'},
          requestOptions: RequestOptions(path: '/api/tickets')),
    );

    expect(parseFkProblem(error), isNull,
        reason: 'a backend that predates the field name must fall back to the existing toast');
  });

  test('repairing a queued ticket edits the row in place and keeps its clientId', () async {
    final id = await queue.create(/* ... an offline ticket with customerId 'gone' ... */);

    final ok = await repairQueuedTicket(id, 'customerId', 'cu-new');

    expect(ok, isTrue);
    final row = await queue.byId(id);
    expect(row!.customerId, 'cu-new');
    expect(row.clientId, id, reason: 'the idempotency key must survive the repair, or the retry duplicates');
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/tickets/ticket_fk_repair_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Implement the parser and the in-place edit**

`parseFkProblem` reads `response.data['extensions']['field']` (accepting a top-level `field` too, for
a proxy that flattens it) and returns null for anything it does not recognise. It never throws.

`repairQueuedTicket` must go through whatever `TicketCreationQueue` already uses to rewrite a row,
so the `clientId`, the attachments and the payload's other fields are untouched — read
`ticket_creation_queue.dart` and add a narrow `updateField(queueId, field, value)` there rather than
patching JSON in the caller.

- [ ] **Step 4: Surface it**

In `_onSubmit`'s error path and in the queue's retry loop, when `parseFkProblem` returns a problem:
open a sheet that names the dead field in Italian ("Il cliente di questo ticket non è più
disponibile. Scegline un altro: il ticket è salvato e non perderai nulla."), carries a
`ReferencePickerField` for that field's entity, and on confirm calls `repairQueuedTicket` then
retries. Only when the repair succeeds is the queue row cleared.

If `parseFkProblem` returns null, keep today's toast verbatim. An unrepairable 404 is still a 404.

- [ ] **Step 5: Pin the reported defect**

Add the regression the spec asks for (§12): a queued row whose `customerId` no longer resolves →
the send is rejected → the repair path runs → the ticket lands with its original `clientId`. Drive
it through `TicketCreationQueue.processAll()` with a mocked client, not by calling the repair
directly, so the wiring is covered too.

- [ ] **Step 6: Run the ticket data suite**

Run: `flutter test test/data/tickets/ test/features/ticket/`
Expected: PASS.

- [ ] **Step 7: Run the full mobile suite**

Run: `flutter test`
Expected: PASS. Report the exact totals.

- [ ] **Step 8: Commit**

```bash
git add lib/data/tickets/ticket_fk_repair.dart lib/data/tickets/ticket_creation_queue.dart \
        lib/features/ticket/new_ticket_form_screen.dart \
        test/data/tickets/ticket_fk_repair_test.dart
git commit -m "feat(mobile): repair a queued ticket whose reference row is gone

The server now names the field it rejected, so the phone can say which reference
died and let the technician pick a replacement, editing the queued row in place.
The clientId survives the repair, so the retry cannot duplicate. A 404 without a
field name keeps today's toast.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Open decision introduced by this plan

- **D-5 — "Riferimento" semantics.** This plan makes the mobile field pick from `Agent`, because the
  server guards `Ticket.AgentId` with `EnsureExistsAsync<Agent>` and serves a real `AgentsController`.
  The alternative — that the field was always meant to be a *User* and the guard is wrong — would be a
  server change with different semantics, and the web client has the same defect and would need the
  same decision. **Default taken: clients pick Agents.** If the product answer is the other way, the
  change is one line in `TicketCommandService` plus its tests, and this plan's B5 Step 4 is reverted;
  the web repo needs fixing either way.

## Self-review

**Spec coverage.** §6.1 bootstrap → B3 prune; §6.2 delta extension → A2/B2; §6.4 deletions → A2
(`IsActive` carried) + B3 (prune on bootstrap); §6.5 cursors → B1 v10; §6.6 stale FK → A3 + B6; §6.8
scope → A2's predicate, tested in `MobileUserSyncReferenceTests`; §7.3 labelled degradation → B4's
empty state; §7.4 search discovers, pick materialises → B4, asserted by the ordering test; §8 schema
→ B1; §9 backend → A1/A2/A3; §11 migration → B1's queued-ticket test; §12 testing → each task's own
suite. **Not covered, deliberately, and stated in Global Constraints:** `maintenanceTemplateId`,
attachments, update-path `internalNotes`, and the web client's copy of the Riferimento defect.

**Placeholder scan.** No "TBD"/"handle edge cases"/"similar to Task N" — every task carries its own
code. Two steps intentionally tell the implementer to copy a factory verbatim from a named existing
file rather than reproducing a constructor they must verify anyway (A1 Step 1, A3 Step 1); that is a
deliberate pointer to a line, not a gap.

**Type consistency.** Wire names: `contracts`/`commesse`/`prodottiAssistenza`/`agents` used
identically in A2, B2 and B3. Dart classes `ContractSyncDto`/`CommessaSyncDto`/
`ProdottoAssistenzaSyncDto`/`AgentSyncDto` used identically in B2, B3 and B4. Drift tables
`contracts`/`commesse`/`prodotti_assistenza`/`agents` in B1, B3 and B4. `ReferenceOption` and
`ReferencePickerField`'s parameter names (`items`, `selectedId`, `onChanged`, `search`,
`onMaterialize`, `emptyHint`) are fixed in B4 and used unchanged in B5 and B6.
`repairQueuedTicket(queueId, field, value)` and `parseFkProblem` fixed in B6 and used only there.

**Review Focus.** (1) → B6 Step 5. (2) → B4 Step 1's ordering assertion. (3) → B2 Step 1 and B3
Step 1's "older backend" cases. (4) → B4 Step 1's labelled-empty-state test. (5) → B5 Step 4.
