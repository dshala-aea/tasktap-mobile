# Mobile redesign + wiring — handoff

Branch `feat/mobile-rack-redesign`, seventeen commits, **698/698 tests green, `flutter analyze` clean**
at every one. Baseline before this work was 637 tests.

Written 2026-08-14 at the end of a session that ran out of context mid-Phase-3. Everything below
is either verified against the code or against `../docs/api/openapi.snapshot.json` and the C#
controllers — nothing here is recalled.

---

## The visual world

**Allestimento Furgone** — the technician's van rack. Impeccable direction seed `1e21eb0b`,
candidate 4 of 7, chosen by the user over an emission-line-rail challenger.

The direction contract lives at the top of `lib/core/theme/theme.dart` and must survive future
edits to the design system. Read it before changing anything visual.

Grammar, in three rules:

1. **Everything hangs off one rail.** `Rack` paints a 4dp aluminium extrusion at x 8–12, inside
   the 19dp gutter every screen already had. `AppRack.railColumn` works out to exactly 19, which
   is why adopting the rail reflowed nothing.
2. **Cells sit on a constant pitch.** `AppRack.cellGap` never varies inside one rack.
3. **Absence is drawn.** An empty slot is a cut silhouette (`ShadowBoard`), not whitespace.

**Brand yellow has exactly one job: the load strap marking what is live** — running timbratura,
selected cell, in-corso ticket. Spending it anywhere else dilutes the only signal it carries. When
a state needs marking that is *not* "live", use the ledge colour instead (stock below minimum uses
`c.red` on the ledge — see `_GiacenzaRow`).

Pinned by the user, not negotiable: yellow `#FFF10E`, Sora + Manrope, Lucide, the floating pill
nav and its 5-tab IA.

### Where the leverage is

Rebuilding a primitive converts every screen using it with no call-site diff. Counts at the time
of the rebuild:

| Primitive | Files | Uses |
|---|---:|---:|
| `ScreenHeader` | 29 | 33 |
| `ListRow` | 21 | 28 |
| `AppFab` | 18 | 18 |
| `EmptyState` | 16 | 20 |
| `AppCard` | 13 | 33 |
| `AppSearchBar` | 13 | 13 |
| `KeyVal` | 6 | 33 |

Prefer changing these over touching screens.

---

## Two bug classes worth grepping for first

### 1. A fixed-dark surface with a theme-flipping foreground

`inkInverse` is white in the light palette and near-black in the dark one. On a surface that is
dark under *both* themes — a hero, a CHARCOAL bar — it disappears the moment dark mode is on.

Found twice and fixed: `ActiveJobCard`'s client line, and `new_ticket_form_screen`'s AppBar. Both
times the adjacent text used a fixed `AppColors.WHITE`, which is exactly why review never caught
it. **Fixed-dark surfaces take fixed inks.**

`test/core/theme/app_palette_test.dart` guards this ("screens read colour from the theme, not from
constants") with an `allowedTokens` escape hatch. It caught a real mistake during this work. Extend
`allowedTokens` with a stated reason rather than working around it.

### 2. Controls that look tappable and do nothing

The dashboard shipped six: two `onTap: () {}` header buttons, four `QuickAction`s that never
passed `onTap` at all, an `onPressed: null` button *inside the empty state whose job was to offer
the way out*, and pressable cards with no destination.

Grep `onTap: () {}`, `onPressed: null`, and widgets accepting `onTap` that omit it. **Where there
is no honest destination, delete the control** — that is what happened to "Nuova pianificazione",
whose only possible target was a placeholder.

---

## Stale-comment hazard

Three separate findings in this codebase were fixed long before their comments were. Verify before
acting on any TODO:

- `magazzino_screen.dart` carried a `TODO(backend)` saying the materiali catalogue was never
  fetched. Untrue since sync started filling the mirror — and the stale note had teeth: the empty
  branch rendered *"L'app non scarica ancora l'elenco materiali"* for **any** empty result,
  including a search that matched nothing. Fixed.
- `giorno_view.dart` was recorded as clamping tappable height to 24dp. It already clamped to 44.
- `docs/api-gap-list.md` (2026-08-03) lists cantieri and materiali as orphaned. Both are wired now.
  **That document is stale as a whole** — treat it as history.

---

## Backend contracts already read

Saves re-deriving from `../docs/api/openapi.snapshot.json` (234 routes).

### Wired during this work

`GET /api/app/magazzino/giacenze` → `MagazzinoGiacenzeDto { elementi: GiacenzaDto[], pagina,
dimensionePagina, totaleElementi, totalePagine }`.
`GiacenzaDto { id, magazzinoId, magazzinoNome?, magazzinoTipo?, materialeId, materialeNome?,
unitOfMeasure?, quantita, stockMinimo?, sottoScorta }`.
Query params: `magazzinoId, sottoScorta, q, page, pageSize, sort`.

`GET /api/app/magazzino/movimenti` → same paged wrapper over
`MovimentoDto { id, data, tipo, magazzinoOrigine{Id,Nome}?, magazzinoDestinazione{Id,Nome}?,
materialeId, materialeNome?, quantita, causale?, userId, userNome? }`.

> **Every decimal on these endpoints is declared `number|string`** and the backend really does
> send both. Parse, never cast — see `_num`/`_int` in `lib/data/magazzino/magazzino_api_client.dart`.
> A cast throws on the first `"4.0"` and takes the whole stock list with it.

### Read, deliberately NOT wired

`GET /api/app/home` → `HomeDto`. **This is the office control-room landing page, not the technician
dashboard** — `AppHomeController`'s own doc comment says so, and the payload is office work
(`fatturatoMese`, `daFatturare`, `rapportiniDaControllare`, `interventiDaPianificare`). It is also
role-layout-gated through `HomeLayoutPolicy`, so a Technician gets most sections omitted by design,
and it is online-only.

Wiring the technician dashboard to it would be wrong twice: wrong audience, and it would replace an
offline-first read path with an online one, against the app's design center. The user's decision
was to skip it.

Its **omit-per-section contract is worth copying anywhere else in `/api/app/*`**: every section is
independently nullable and `sezioniNonDisponibili: string[]` names the omitted ones. A null section
means *unavailable*, never zero — rendering it as `0` fabricates a number the server refused to
give. An unauthorized caller gets `200` with every section omitted, never a `403`.

`KpiDto { oreMese, fatturatoMese, interventiAperti }`, `QueueSummaryDto { count, oldestAgeDays? }`,
`ScheduleOggiDto { id, titolo?, data, oraInizio?, oraFine?, tecnico?, tecnicoId? }`,
`ScortaSottoMinimoDto { id, nome, quantita, stockMinimo }`,
`ContrattoInScadenzaDto { id, name, customerName?, numero?, endDate?, daysLeft }`.

### Verified NOT a gap — do not "fix"

`POST /api/WorkLog/break/start|end` is uncalled **on purpose**. Mobile records pauses locally
(`timbra_providers.dart`, event type `pausa`) and syncs them through the idempotent
`POST /api/worklog/mobile/sessions` upsert. That is the offline-first path and it is correct; the
break endpoints are the online/kiosk route. Wiring them would be a regression.

---

## What remains

Ordered by technician value. The user's Phase-3 scope was: technician-critical writes, the
technician `/api/app/*` endpoints, real settings, and AI.

1. ~~**Ticket workflow writes**~~ — **done** (`eab8dff`). `TicketWorkflowApiClient` covers status,
   self-assign, history and worklogs start/stop/manual/list; the detail screen has a timer bar.
   Self-assign and status change are surfaced too (`8f36b46`), in the status row rather than the
   bottom action stack — that stack has now twice been squeezed until something under it stopped
   laying out, so treat it as full.

   History and the worklog list are surfaced too, as the Ore and Storico tabs (`e9…`). Nothing on
   the ticket workflow remains unsurfaced.

   Note the ticket detail now carries **seven** tabs, and at 800dp the strip scrolls — a widget
   test tapping the right-most labels needs a wider surface or the tap lands on whatever is
   beneath. See `tapWideTab` in `ticket_detail_screen_test.dart`.

   Two facts worth keeping: the backend refuses `worklogs/start` when the caller has an open timer
   on **any** ticket, not just the one on screen; and these routes have no idempotent upsert, so
   they must stay online-only rather than being queued.
2. **Technician `/api/app/*`** — assessed in full; most of it is worth less than it looks.
   - `clienti/{id}/overview` — **done**, additive (pec/sdiCode/codiceFiscale/provincia + four
     counts, none of which the mirror has columns for).
   - `interventi/{id}` — its real win was resolving the technician's name, now done offline from
     the `colleagues` mirror. The rest (linked schedules, linked rapportini) is already on the
     detail's tabs from local data. Low value.
   - `pianificazione/calendar` — duplicates the offline calendar with resolved names. Wiring it
     would trade offline for cosmetics. **Do not.**
   - `rapportini/{id}` — rich and authoritative for a *submitted* report (staff hours, materiali,
     controlli, firme, allegati, audit trail). Belongs with the Phase 4 wizard, not standalone.

   Original list, for reference: — `interventi/{id}`, `rapportini/{id}`, `clienti/{id}/overview`,
   `pianificazione/calendar`. Honour `sezioniNonDisponibili` wherever present.
3. **Report tail** — `firma-cliente`, `firma-tecnico`, `invia`, `pdf`, `annulla`, `mail`. Overlaps
   Phase 4's rapportino wizard; do them together.
4. **Real settings** — `GET/PUT /api/NotificationSettings`, `PUT /api/Users/me/preferences`,
   `PUT /api/Auth/profile`. The Impostazioni toggles currently write local prefs the server never
   sees.
5. ~~**AI**~~ — **partly done**. `reports/draft` + `quota` are wired into the rapportino wizard's
   Dettagli step, gated on the report having a `scheduleId` (the endpoint requires one).

   **The quota is per tenant, and spent before the work.** `TryConsumeAsync` takes a tenant id, so
   one technician exhausts the company's month; and the controller consumes it before calling the
   model, so a failed generation still costs one. Any future AI surface must say both.

   **`POST /api/ai/transcribe` is NOT wired, and needs a decision first.** It takes multipart
   audio, but the app has no audio-recording package and no microphone permission on either
   platform. Wiring it means adding a dependency, an Android manifest entry and an iOS usage
   description — a platform change to weigh against the pilot date, not a wiring task.

### Phase 4 (untouched)

The rapportino wizard and 27 admin CRUD screens. Known defects in there:

- `rapportini_list_screen.dart:91` — `_createNewDraft` writes `tenantId: 'local'` and
  `insertedUserId: 'local-user'` as literals into a draft that is later submitted through the
  queue. **Fabricated identifiers in a payroll/invoice record**, the same class as the
  `user-<timestamp>` bug fixed in `ae766a1`. Read the submit path before changing it.
- `Color(0xFF363636)` hardcoded in four rapportino step files — ink that never flips, so it is a
  dark-mode defect.
- `admin_report_list_screen.dart:230` hand-rolls a status→colour switch that disagrees with
  `status_colors.dart`.
- 14 screens still on Material `AppBar` rather than `ScreenHeader` (all form screens).

### Phase 5 (untouched)

`node ~/.claude/skills/impeccable/scripts/detect.mjs --json <targets>`, then the
`impeccable-finish-reviewer`, then `impeccable-documenter` to write `DESIGN.md` from the built
world. **The reviewer needs light and dark screenshots and this environment cannot produce them** —
no emulator, and Flutter will not render headless on `/mnt/d`. Either capture them on a Windows
device or accept a code-only review, and disclose which.

---

## Working notes for this repo

- `flutter analyze` takes ~350s and `flutter test` ~70s on this mount. Batch verification; do not
  run them per edit.
- **Run the test suite before attributing a failure.** 109 failures once looked like a broad
  regression; 106 came from a single `CrossAxisAlignment.stretch` demanding bounded height inside a
  scroll view, and the baseline had been green all along.
- `perl -i` and `sed -i` silently delete files on `/mnt/d`. Use the editor tools or a Python
  read-modify-write.
- Lucide is a **local curated subset** at `lib/core/icons/app_lucide_icons.dart` — the published
  package's Dart no longer compiles. Adding a glyph means copying its code point from
  `~/.pub-cache/hosted/pub.dev/lucide_icons-0.257.0/lib/lucide_icons.dart`.
- `mobile/` is its own git repo nested inside the monorepo. Never give a subagent worktree
  isolation here.
