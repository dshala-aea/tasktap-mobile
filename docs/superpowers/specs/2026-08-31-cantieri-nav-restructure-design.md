# Cantieri Nav Restructure — design

Status: **Draft, for review.**

## Context

Two related complaints drove this:

1. Personal Timbra has its own bottom-nav tab, but an operator has no easy way to reach "the
   cantieri (worksites) I'm assigned to" — the only way into a cantiere today is via a ticket's
   secondary "Timbra cantiere" button (`ticket_detail_screen.dart`), which only exists when a
   ticket happens to be assigned.
2. That same button is conceptually misplaced: a "Timbra cantiere" (clock in/out at a worksite)
   is an action that belongs to the *cantiere*, not the ticket — a ticket may or may not even be
   linked to one (`Ticket.CantiereId` is nullable, both server-side and in intent).

Investigation found the data this needs mostly already exists:

- `CantiereAssignment` (backend entity: `CantiereId`, `UserId`, `Role`, `StartDate`/`EndDate`) is
  a real per-technician cantiere assignment, already wired into the mobile sync delta
  (`MobileUserSyncResult.Cantieri`, `MobileUserSyncService`): scoped to the technician's own
  assignments, falling back to all active cantieri when they have none. Mobile's
  `SyncService._upsertCantieri` already consumes this, so the local `cantieriProvider`
  (`lib/features/timbra/cantiere_timbra_screen.dart`) is already "my available cantieri" —
  **no new backend work needed for the list itself.**
- `CantiereTimbraScreen` (the existing clock-in/out screen, reached today only from a ticket) is
  already ticket-agnostic under the hood: its route (`AppRoutes.cantiereTimbraPath`) takes
  optional `ticketId`/`customerId`, and its internal picker already prefers cantieri matching
  `customerId` when given one. It just has no direct entry point.
- `ticketId` on a cantiere clock-in session is not cosmetic — `CantiereTimbraScreen` records it on
  the resulting local/server work-log session and reads it back to show a "ticket" label
  (`serverLog?.ticketId ?? local.ticketId`). Removing the ticket entry point must not silently
  lose this.
- `Ticket.CantiereId` exists as a real column server-side (`Ticket.cs`) and
  `GET /api/tickets?cantiereId=` already filters by it (`TicketsController.cs:92,128-129`) — but
  it was never exposed to mobile. The sync wire shape (`TicketDto` in `sync_dto.dart`) has no
  `cantiereId` field, and the local `Tickets` Drift table has no such column. Today's "Timbra
  cantiere" button never used a real link at all; it only guessed via matching `customerId`.

## Scope

**In scope:**

- Bottom nav: replace the Timbra tab with a Cantieri tab (still 5 tabs).
- Personal Timbra: relocate to a Dashboard quick-action tile; the screen itself is unchanged.
- `CantieriListScreen` (new): technician-facing list of the operator's own cantieri.
- `CantiereDetailScreen` (new): cantiere info, a "Timbra cantiere" action, and a list of tickets
  linked to that cantiere.
- `CantiereTimbraScreen`: accept a direct `cantiereId` and skip its picker when one is given.
- `ticket_detail_screen.dart`: remove the "Timbra cantiere" button; add a small chip linking to
  Cantiere detail when `ticket.cantiereId` is set, carrying `ticketId` forward so the session
  tagging described above still happens when Timbra is entered that way.
- Backend: add `cantiereId` to the ticket sync projection so it reaches
  `MobileUserSyncResult.Tickets` / `TicketDto`.
- Mobile: `cantiereId` column + migration on the local `Tickets` table, synced the same way
  `DraftReports.cantiereId` already is.
- Mobile: a "tickets for this cantiere" API client method against the existing
  `GET /api/tickets?cantiereId=` endpoint (no new backend endpoint).

**Explicitly out of scope:**

- Any change to `CantiereAssignment` itself, or an admin UI to manage it (already exists via
  `CantieriController`, unrelated to this pass).
- Squadra-cantiere linkage — investigated, no such relation exists in the schema
  (`Squadra`/`SquadraMembro` link to `Schedule`/`ScheduleAssignment`, not `Cantiere`); not
  introducing one here.
- Editing `Ticket.CantiereId` from mobile — this pass only reads/displays it. Setting it (if that
  ever needs to happen from mobile rather than the web admin) is a separate ask.
- A "recent cantieri" or favorites ordering — the `CantiereAssignment` scoping already narrows the
  list enough that this isn't needed for a first pass.

## Decisions

**Nav tab swap, not an added 6th tab.** Matches the user's own framing ("remove timbra... put the
cantieri"). `AppBottomNav.defaultItems` (`lib/core/widgets/bottom_nav.dart`) is a plain ordered
list — swap the `timbra` entry for a new `cantieri` one, same position (index 2), so
`HomeShell`'s screen-per-index wiring only needs its index-2 target changed, not renumbered.

**Personal Timbra → Dashboard quick-action tile.** The Dashboard tab is already the first thing an
operator sees; a prominent tile there keeps clock-in/out one tap away without a dedicated tab.
Exact tile placement/styling follows whatever pattern the Dashboard's existing quick-actions
already use (read at plan time — not designing a new quick-action pattern here).

**`CantieriListScreen` reads `cantieriProvider` as-is.** No new filtering logic: the provider is
already the right data (see Context). List is alphabetical (matches the provider's existing
`orderBy`), each row navigating to `CantiereDetailScreen(cantiereId: c.id)`.

**`CantiereDetailScreen` is a new, focused screen** — not a reuse of the admin
`admin_cantiere_detail_screen.dart` (that one is CRUD-oriented, office/admin-only, a different
persona per this app's established "mobile stays technician-persona" precedent already applied
elsewhere). Shows: name, address/city, customer (if any), status, a `VetroButton` "Timbra
cantiere" action, and below it a section listing tickets linked to this cantiere (title, status,
tap-through to `TicketDetailScreen`). Empty state when no tickets are linked — a cantiere with no
tickets is a normal, common case (pure worksite work, no ticket at all), not an error.

**`CantiereTimbraScreen` gains a direct `cantiereId` param.** Today's constructor takes
`{ticketId, customerId}`; add `cantiereId` alongside them. When `cantiereId` is present, the
screen skips the cantiere picker entirely and proceeds as if that cantiere were already selected
— matching the screen's existing "if no active session: show picker, else show session" structure,
just with the picker step bypassed. `ticketId` stays honored when also present (from the ticket
chip's navigation) so session tagging is unaffected; when absent (direct Cantieri-tab entry) the
session is simply untagged, exactly like a cantiere clock-in with no ticket context today.

**Ticket detail's chip, not a full re-add of the button.** A small tappable chip ("📍 Cantiere:
<name>", reusing `AppChip` styling) appears only when `ticket.cantiereId` is set (i.e., resolved
via the new local Drift lookup — not the old `customerId`-matching heuristic, which stays only as
`CantiereTimbraScreen`'s own picker fallback for the direct-entry, no-cantiereId-known case).
Tapping it navigates to `CantiereDetailScreen(cantiereId: ticket.cantiereId!, ticketId: ticket.id)`
— the detail screen forwards `ticketId` into `CantiereTimbraScreen` when its Timbra action is
tapped, preserving today's session-tagging behavior end to end.

**Sync field addition, minimal surface.** `MobileUserSyncResult.Tickets` is `IReadOnlyList<Ticket>`
(the raw entity, not a projected DTO) per `MobileUserSyncResult.cs` — so `CantiereId` already
serializes over the wire once added to the query projection (if the query currently selects
specific columns) or requires no server change at all (if it already returns full `Ticket` rows).
Confirm which at plan time; either way the client-side shape (`TicketDto.fromJson` in
`sync_dto.dart`) needs the new field parsed, and `SyncService`'s ticket upsert needs the new Drift
column written — mirroring `DraftReports.cantiereId`'s existing migration pattern exactly (schema
bump, `addColumn`, no backfill for existing local rows since the value simply arrives on the next
sync).

## Data model changes

**Mobile — `Tickets` table** (`lib/data/local/app_database.dart`): add
`TextColumn get cantiereId => text().nullable()();`, schema version bump + migration step (mirror
`DraftReports.cantiereId`'s migration exactly).

**Backend — ticket sync projection**: add `CantiereId` to whatever query builds
`MobileUserSyncResult.Tickets` if it's a narrowed projection rather than the full entity (verify
at plan time).

## Testing

- `bottom_nav_test.dart` (or wherever nav is currently tested): 5 tabs, Cantieri at index 2,
  Timbra no longer present as a tab.
- `CantieriListScreen` widget test: renders `cantieriProvider`'s list, empty state when empty, row
  tap navigates with the right `cantiereId`.
- `CantiereDetailScreen` widget test: renders info fields, Timbra button navigates to
  `CantiereTimbraScreen` with `cantiereId` (and `ticketId` when passed through), linked-tickets
  section renders/empties correctly.
- `CantiereTimbraScreen` unit/widget test: given `cantiereId`, picker step is skipped.
- `ticket_detail_screen_test.dart`: chip renders only when `cantiereId` is set, navigates with
  both `cantiereId` and `ticketId`; "Timbra cantiere" button assertion (if one exists in the
  current suite) removed/updated.
- Sync round-trip test (mirroring `DraftReports.cantiereId`'s own migration test, if one exists,
  or `TicketDto` round-trip tests): a ticket with `cantiereId` set on the server round-trips
  through sync into the local Drift row.

## Open questions for review

1. Whether `MobileUserSyncResult.Tickets`' underlying query is a narrowed projection (needs a
   server field addition) or the full `Ticket` entity (already carries `CantiereId`, zero backend
   change) — settle at plan-writing time by reading `MobileUserSyncService`'s ticket query
   directly; doesn't change any other part of this design either way.
2. Dashboard quick-action tile's exact visual treatment for personal Timbra isn't designed here —
   deferred to match whatever the Dashboard's existing quick-action pattern already is, confirmed
   at plan time.
