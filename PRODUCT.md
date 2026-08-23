# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Flutter, shipped to both the Play Store and the App Store from one codebase
(`codemagic.yaml` builds an Android release track and an iOS App Store
workflow). One design language serves both; native affordances — safe areas,
back gesture, keyboard behavior, share/permission sheets — are honored per OS.

## Users

**Primary: the field technician.** Works on a customer site or a cantiere,
not at a desk. The scene that decides every severity call in this app:
one-handed, often gloved, phone held at arm's length in direct sun, frequently
with no usable signal. Their day is a sequence of arrive → clock in → do the
work → record what was done and what was used → get a signature → leave. They
are not a power user of software and did not choose this app.

**Secondary: the office/admin user on a phone.** Uses the same build to fix a
customer record, add a location, assign a technician, or check a report while
away from the office web app. Reaches these through the *Altro* hub, never
through the technician's daily path.

## Product Purpose

TaskTap is field-service management for Italian trade and maintenance
companies. The mobile app is the technician's half of it: it captures the
labor, materials, time, photos and signatures that turn a completed job into a
billable, defensible record, and it must do that whether or not the phone has
a network.

Success is a *rapportino* (service report) that leaves the site complete and
signed, and a timbratura (time record) accurate enough to run payroll from.
Anything the technician has to remember and re-enter later is a failure.

## Positioning

Offline is not a degraded mode here, it is the design center. The app owns a
full local database (Drift, `schemaVersion` 9) with a submission queue: a
report can be created, edited, photographed, signed and queued with the radio
off, and reconciles when signal returns. Competing tools treat the network as
present and the offline case as an error state.

The second differentiator is that the domain is modeled in the customer's own
language and in the customer's own time concepts — see Capabilities.

## Operating Context

- **Where:** customer premises, cantieri (construction sites), vans. Outdoors,
  in vehicles, in plant rooms. Sunlight and gloves are the norm, not the edge
  case.
- **Connectivity:** intermittent by default. A field test protocol exists at
  `docs/testing/2026-08-07-offline-field-test.md` (not yet run on a physical
  device as of this record).
- **Language:** the UI is Italian. Domain nouns are Italian and are not
  translated in the interface: *rapportino* (service report), *timbratura*
  (clock punch), *cantiere* (construction site), *intervento* (job / service
  call), *sede* (customer site), *squadra* (crew), *magazzino* (warehouse),
  *commessa* (work order), *prodotto in assistenza* (equipment under service),
  *fattura* (invoice).
- **Backend:** a .NET API in the same repository, 234 routes, contract frozen
  as `docs/api/openapi.snapshot.json` with a mobile-side conformance gate. A
  purpose-built `/api/app/*` endpoint family exists specifically to serve this
  client with pre-shaped aggregates.
- **Timeline:** pilot deployment targeted for September 2026.

## Capabilities and Constraints

**Three distinct time concepts, deliberately not unified.** Conflating them is
a modeling error, not a simplification:
1. *Timbratura* — the person's working day (`WorkLog`): start, break, end.
   Payroll input.
2. *Cantiere* work sessions (`CantiereWorkLog`) — time attributed to a
   construction site.
3. *Ticket / report worklog* — labor booked against one job, which is what
   gets billed.

**Shipped today:** 5-tab shell (Dashboard · Ticket · Timbra · Calendario ·
Altro); ticket list/detail/creation; a 4-step rapportino wizard with autosave,
photo capture, GPS, material lines and signature capture; personal and
cantiere timbratura; a 4-view calendar (giorno/settimana/mese/lista); clienti;
magazzino; notifications; settings; and an admin CRUD surface over cantieri,
customers, locations, materiali, prodotti, reports, schedules, squadre and
contracts.

**Auth:** OIDC against Zitadel, migrated from Supabase. Credentials are
injected at build time via `--dart-define`; nothing is committed.

**Server-projected authorization.** The client does not compute permissions.
`/auth/me` returns a permission list and the server projects which workflow
actions are available on each entity (`availableActions`); the UI renders what
the server allows and must not invent an action the server did not offer. The
one exception the client must respect: `Reports/controlla` and
`Reports/fattura` are additionally role-gated to Office/Admin server-side, so
permission alone is not sufficient to show them.

**Known constraint:** several backend capabilities are live but unwired from
the client — the whole `/api/app/*` aggregate family, `/api/Magazzino/*`
(including van stock, `furgone/{userId}`), ticket `status` / `self-assign` /
`history` / `worklogs/*`, `WorkLog/break/*`, report `firma-cliente` /
`firma-tecnico` / `invia` / `pdf`, `NotificationSettings`, and `/api/ai/*`.

**Deliberately deferred:** a dependency bump of 39 packages, held until after
the physical-device offline field test, because `drift` and `signature` are
the two riskiest possible upgrades before a pilot.

## Brand Commitments

Superseded 2026-08-23: the user reopened every prior commitment below
(color, typefaces, nav pattern included) and ran a fresh Impeccable
new-work round. Three directions were built as real HTML prototypes on
identical content and compared side by side; the user chose the
assigned-by-roll direction.

**Chosen world: Cassetta** (shadow-foam tool case). Seed key `cce7d144`,
assigned index 4 of a 7-candidate list derived from an Italian field
technician's own world (cassetta attrezzi, libretto di manutenzione,
quadro elettrico, cartellino orario, bolla a ricalco, cantiere signage,
targhetta). Two challengers were dealt and lost on audience-identification
or product-clarity: `signals-instruments-darkroom-safelight-bay` and
`digital-design-canon-warm-consumer-app-surface`.

- **THESIS:** the app is your case — every module a labeled, tool-shaped
  compartment. An empty dashed silhouette means "still needed"; a filled
  slot means "accounted for." Nothing hides in a plain list.
- **OWN-WORLD:** gunmetal case shell, foam-gray compartment lining, safety
  orange reserved strictly for what needs attention or action (replaces
  the old yellow-scarcity rule with the same discipline, new hue), bone
  label-plate cream for stencil text. Industrial condensed/stencil-styled
  headers (uppercase, tracked), clean sans for body and data, tabular
  numerals for timers and counts.
- **NAVIGATION:** the bottom nav is reimagined as the case's own latch
  row — labeled compartment tabs, not the old floating pill. The pill nav
  commitment is retired.
- **Lucide** stays the icon family (industrial line-icon character fits
  the world; no reason to replace it).
- The product name is **TaskTap**. UI copy is Italian.

Working prototype (built as the decision artifact, not yet the Flutter
implementation): `/mnt/d/AEA/Sviluppi/TaskTap/mobile` scratch prototypes,
published — see chat history 2026-08-23 for the three compared directions
and the artifact URLs.

Everything not fixed above (exact radii, spacing scale, motion timings,
per-screen composition) is resolved during the Flutter build, following
this world.

## Evidence on Hand

- `design-reference/DESIGN-SPEC.md` — the incumbent token and component set.
- `design-reference/DESIGN-SCREENS.md` — the per-screen implementation plan.
- `docs/api-gap-list.md` — a route-existence audit dated 2026-08-03. Partly
  stale: the cantieri/materiali orphan it flags has since been wired.
- `../docs/api/openapi.snapshot.json` — the frozen 234-route backend contract.
- 46 screens and ~53k lines of Dart already in `lib/`, with a test suite.

No customer testimonials, no usage metrics, no pricing or benchmark claims
exist for this product. Future work must not fabricate them.

## Product Principles

1. **The field scene sets severity.** A 40dp target or a 3.2:1 grey is not a
   nit when the user is gloved and in the sun; it is the defect.
2. **Offline is the design center**, not an error state. Every screen states
   what it knows, how stale it is, and what is still queued.
3. **Never fabricate into a record.** Payroll and invoices are downstream. An
   empty picker is better than a typed-in identifier; an honest unavailable
   state is better than a silently empty list.
4. **The server owns authorization and workflow.** The client renders offered
   actions; it does not derive them.
5. **The tool disappears into the task.** Familiar affordances, consistent
   vocabulary screen to screen; expression lives in precision, never in
   novelty that costs a technician a second.

## Accessibility & Inclusion

Driven by the operating context rather than by a compliance target: ≥44dp
touch targets throughout, ≥4.5:1 body contrast (measured against the app's own
surfaces, not white), no status conveyed by color alone, live regions on
running clocks, and reasons stated visually *and* in the semantic label when a
control refuses an action. Both light and dark themes are first-class and
shipped; the setting is an explicit user choice, not `ThemeMode.system`.
