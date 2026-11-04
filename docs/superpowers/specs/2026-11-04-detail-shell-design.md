# Detail shell — “Il giorno” applied to every detail screen

**Date:** 2026-11-04
**Status:** Draft for approval
**Surface:** Flutter mobile app, all entity detail screens
**Chosen layout:** A — Hero + stack
**Migration rule:** one core feature at a time

## Intent

Every detail screen should feel like the same document, opened on a different subject. The cantiere detail already proved the shape: identity at the top, one hero that answers “what is this and what do I do now”, then the facts and activity in a predictable order. This spec turns that into a shared shell and applies it to ticket, rapportino, cantiere and the admin master-data details.

The shell must serve two people:

- **The field technician** — one-handed, outdoors, often offline. The primary action must stay reachable, the day must be legible at a glance, and nothing may disappear because the network did.
- **The office/admin user** — fixing a record on a phone. The same document shape should read as a record, with edit as the primary action instead of a clock.

Success is not “every screen looks identical”. Success is that a technician who learns one detail screen can predict every other one, and an admin screen can be read without hunting through a FAB and a stack of unrelated cards.

## Goals

- One shared `DetailScaffold` used by every detail screen.
- One hero contract with two variants: **OperationalHero** and **SummaryHero**.
- A **56px collapsed sticky bar** that keeps status and the primary action reachable while scrolling.
- A fixed section vocabulary: **Sintesi, Relazioni, Attività, Documenti & mappa**.
- No duplicated facts between hero and Sintesi.
- A standard state matrix for loading, offline, empty, closed and permission-denied.
- Preserve every existing behaviour, data source, offline path and deep link.

## Non-goals

- Redesigning lists, forms, navigation, timbra, or the rapportino wizard.
- New API calls or new local tables.
- A generic form/schema renderer driven by configuration.
- A visual redesign of the Il Documento world.
- Changing the existing cantiere day logic or the timbra providers.
- Dark mode work beyond what the existing palette already supports.

## Anti-goals

- A screen that hides the primary action because the user scrolled.
- A screen that shows an action the user cannot take, with no explanation.
- The same fact shown in the hero, Sintesi and a random card.
- A “one-size-fits-all” detail that turns master data into a fake operational screen.
- A big-bang migration that leaves half the app on the old pattern for weeks.

## Approaches considered

### A — Hero + stack (chosen)

Identity header → hero → ordered sections. The hero carries status and the primary action; sections carry the detail. It is the cantiere pattern generalised.

**Trade-off:** long pages. Mitigated by the collapsed sticky bar and by skipping empty sections.

### B — Overview board

Header → 2-column KPI grid → sticky action bar → facts open in sheets.

**Trade-off:** excellent scan density, but hides the day/activity behind taps and reads as a dashboard, not a document. Wrong for the technician’s arrival-to-departure flow.

### C — Timeline first

Header → compact hero → chronological activity feed, with facts in a sheet.

**Trade-off:** best for ticket/cantiere, weak for customer/product/warehouse master data, and it demotes the facts an admin opens the screen to edit.

**Why A:** it is the only option that survives both operational and master-data screens without pretending they are the same, and it is already proven on cantiere. B and C are kept as possible section treatments later, not as the shell.

## The shell

### Anatomy

```
SafeArea
  ScreenHeader (back, generic screen title, header actions)
  CustomScrollView
    Hero: kicker · entity title · subtitle (outside the card), then the hero card
    [expandedExtra]          optional, screen-specific
    DetailSection …
  CollapsedBar (56px)        pinned under the header once the hero leaves
  [fab]                      only when a screen has a secondary create action
```

**Identity split:** the header names the *screen* ("Ticket", "Cliente") and owns back/overflow; the hero owns the *entity* (job title, customer name) and its subtitle. Your eye reads the generic screen type first, then the specific record.

**Source of truth.** Option A of `prototypes/detail-layouts.html` ("Hero + stack") defines the visual. Where this spec and that mockup disagree, the mockup wins.

### Hero

Two variants, one contract:

- **OperationalHero** — a mono state label and a live value (timer or day total) at the top of the card, a copy line, the primary action (`Timbra ingresso` / `Timbra uscita`) and secondary actions (`Crea rapportino`, `Dettagli`).
- **SummaryHero** — state label, primary action (`Modifica`), optional secondary action. No timer, no fake “day”.

The hero has two parts.

**Header (outside the card).** In this order:

1. Kicker row — mono 9px / 600, uppercase, letter-spacing .1em, muted: the document kind + reference in Stamp Red (`TICKET · INT-2026-0412`), then `·`, then a muted context (`OGGI`). `DetailHeroData.kicker` / `kickerContext`.
2. Entity title — Archivo Narrow 30, line-height .98, letter-spacing -.025em, at most two lines, then ellipsis.
3. Subtitle — Archivo 11.5, line-height 1.45, muted, up to two lines (typically “who · where” and “assigned to”).

**Card.** A `Sheet` surface, 1px `Rule` border, 2px radius, 14px padding, no shadow:

- Top row: mono 9px uppercase muted **state label** (e.g. `IN CORSO`) on the left, live value on the right (mono 22, tabular, Stamp Red for a timer).
- Copy line (`heroCopy`): 11.5 muted, emphasis in bold ink (`Ingresso alle **09:12** · sessione aperta`).
- Primary action: full width, Stamp Red fill, 12/600 Archivo, 2px radius. The mockup draws it 42px; the shell keeps a 48px minimum.
- Secondary row: first action is secondary (Muted Fill + Rule border), the rest ghost; 11px, drawn 36px in the mockup, kept at 44px minimum.

Rules:

- The entity title lives in the hero header, not in the app header and not inside the card.
- **Facts do not live in the hero card.** Cliente / Sede / Tecnico (and the rest) render in the Sintesi section's `DetailFactsGrid`. This is the no-duplication rule: one place, Sintesi.
- A disabled primary action stays visible with one line of reason under it.
- Long titles wrap to two lines, then ellipsis; they never push the action off-screen.

### Collapsed bar

- 56px, `Sheet` surface, 1px bottom `Rule`, sits directly under the header.
- Shows the status stamp and the primary action (compact). No secondary actions.
- Appears when the hero’s bottom edge passes under the header; animates height/opacity over 150ms with an ease-out curve. Respects reduced motion.
- Built from the same `DetailHeroData` as the expanded hero, so the two cannot drift.
- If a screen has no primary action, the bar shows status and the header overflow only.

### Sections

Fixed vocabulary and order:

1. **Sintesi** — the full fact set, as a two-column `DetailFactsGrid` (Cliente, Sede, Tecnico, Commessa, …). Trailing: mono count (`4 CAMPI`).
2. **Relazioni** — customer, site, commessa, contract, technician, crew, linked tickets.
3. **Attività** — a `DetailActivityTimeline` (1px left rule, 9px dot per event, outline when neutral and filled green / Stamp Red / amber by tone, mono time, 11.5/600 title, 10.5 muted meta) fed only from data the screen already has; trailing mono `APRI` link opens the full detail.
4. **Documenti & mappa** — attachments as inline rows (28px icon box on Fill with a Rule border, 11/600 name, mono 8.5 size, top/bottom 1px rules; trailing `N FILE`), photos, signatures, map.

Operational screens (Ticket, Cantiere, Rapportino) put **Attività** directly under the hero; the screen supplies the ordered section list, so the scaffold stays agnostic. Master data keeps Sintesi first.

**Specialist exception.** The four sections are the default, not a prohibition. A screen may add one specialist top-level section only when that dimension is its primary job: Rapportino (Ore, Materiali, Controlli), Magazzino (Movimenti). If a second screen needs the same specialist section, it becomes a shared section rather than a local exception. The specialist section must not replace Sintesi/Relazioni/Attività/Documenti.

Rules:

- Empty sections are not rendered. Never an empty card.
- A section is a title plus content; it is not necessarily a card. Use rules and spacing before adding a container.
- Section titles use Archivo Narrow 17/600. No uppercase eyebrow over every section.
- Section trailing slot is mono 9px, uppercase: a count (`4 CAMPI`, `2 FILE`) in muted, or a link (`APRI`, `TUTTE`) in Stamp Red.
- 19px between sections; 8px between title and content.

### States

The screen resolves one state and renders the standard treatment:

| State | Treatment |
|---|---|
| Loading | Header + hero skeleton. No full-screen spinner, no layout jump. |
| Error | Full `UnavailableState` with retry. |
| Not found | `UnavailableState`, same as today. |
| Offline | Render the mirror; quiet stale/offline banner; keep offline-capable actions enabled. |
| Pending sync | Action stays enabled; small `Da inviare` marker on the relevant row/hero. |
| Closed / not actionable | Primary action visible but **disabled with one line of reason**. |
| Active session elsewhere | Primary action visible but disabled with the reason; no silent removal. |
| Permission denied | Write action **hidden**; the screen stays read-only. |

No action is removed for a transient state. Permission is the only reason to hide an action.

### Typography, spacing, colour

- Il Documento tokens only: Paper ground, Sheet surface, Carbon Ink, Slate, Stamp Red as the sole accent.
- Display: Archivo Narrow 30 for the entity title in the hero header (the app header stays generic).
- Body: Archivo 12–16. Mono: IBM Plex only for references, timestamps, clocks and counts.
- Primary button: Stamp Red, `brandOn` text, 2px radius. Secondary: Muted Fill with a Rule border. Ghost: text only. Hero buttons are `DetailHeroButton` (Archivo 12/11, 2px radius), not the app-wide `AppButton`.
- Standard page padding; 19px section rhythm; 2px radius on every surface.
- Max content width: 600px for master data, 720px for operational screens; centered above the breakpoint.

### Accessibility

- 48px minimum touch targets; the collapsed bar’s action is at least 44px high.
- Every icon-only control has a semantic label; the collapsed bar exposes status + action as one readable group.
- Stamps carry text, not colour alone. Contrast follows the existing AA-verified palette.
- Scroll order matches reading order; the collapsed bar is not a second focus trap.
- Reduced motion disables the collapse animation and the live-dot pulse.

## Component contract

The exact names may change during implementation; the responsibilities may not.

```dart
DetailScaffold(
  screenTitle: String,             // "Ticket", "Cliente" — generic, in the header
  headerActions: List<Widget>,
  hero: DetailHeroData,
  expandedExtra: Widget?,          // cantiere crew strip, ticket timer detail, …
  sections: List<DetailSection>,
  onRefresh: Future<void> Function()?,
  maxWidth: double,                // 600 master data, 720 operational
  fab: Widget?,                    // only for a secondary create action
)

DetailHeroData(
  variant: DetailHeroVariant.operational | .summary,
  title: String,                   // entity title, two-line clamp
  kicker: String?,                 // red part of the mono kicker row
  kickerContext: String?,          // muted part after the "·"
  subtitle: String?,               // two-line clamp
  status: DetailStatus(label, tone),
  heroCopy: Widget?,               // 11.5 muted line under the state row
  liveValue: Widget?,              // mono timer / day total
  primaryAction: DetailAction?,
  secondaryActions: List<DetailAction>,
)

DetailAction(
  label: String,
  icon: Widget?,
  onPressed: VoidCallback?,
  enabled: bool,
  disabledReason: String?,
)

DetailSection(
  title: String,
  trailing: Widget?,               // DetailSectionMeta('4 campi') | DetailSectionLink('Apri')
  child: Widget,
  isEmpty: bool,                   // scaffold skips it
)
```

Rules for the contract:

- The scaffold renders both the expanded hero and the collapsed bar from `DetailHeroData`.
- `expandedExtra` is the only place a screen may inject custom hero-adjacent content. It must not duplicate Sintesi facts.
- The screen supplies sections in its own order; the scaffold does not know about `activityFirst`.
- No FAB when the hero has a primary action. A FAB remains only for a genuinely different secondary create action.
- The scaffold owns pull-to-refresh, page padding, max width and the sticky bar.
- The scaffold never fetches data. Providers stay with the screen.

## Per-screen mapping

| Screen | Hero | Sintesi facts (not in hero) | Section order | Primary |
|---|---|---|---|---|
| Ticket | Operational | Cliente, Sede, Tecnico, Commessa, Contratto | Attività, Sintesi, Relazioni, Allegati, Documenti & mappa | Avvia / Chiudi intervento |
| Cantiere | Operational | Cliente, Squadra, Ticket aperti | Attività (Il giorno), Sintesi, Relazioni, Documenti & mappa | Timbra ingresso/uscita |
| Rapportino (view) | Operational | Cliente, Sede, Tecnico | Attività (Cronologia), Sintesi, Ore, Materiali, Controlli, Documenti & mappa | Scarica PDF / Rilavora (respinto) |
| Cliente | Summary | Stato, Sedi, Contratti | Sintesi, Relazioni (sedi, contratti, referenti), Attività, Documenti | Modifica |
| Sede | Summary | Cliente, Città, Stato | Sintesi, Relazioni, Attività, Documenti & mappa | Modifica |
| Commessa | Summary | Cliente, Stato, Periodo | Sintesi, Relazioni, Attività, Documenti | Modifica |
| Contratto | Summary | Cliente, Stato, Scadenza | Sintesi, Relazioni, Attività, Documenti | Modifica |
| Prodotto in assistenza | Summary | Cliente, Stato, Seriale | Sintesi, Relazioni, Attività, Documenti | Modifica |
| Materiale / Magazzino | Summary | Stato, Famiglia, Giacenza | Sintesi, Movimenti, Documenti | Modifica |
| Squadra | Summary | Lead, Membri, Cantieri | Sintesi, Relazioni, Attività | Modifica |
| Pianificazione | Summary | Stato, Data, Squadra | Sintesi, Relazioni, Attività | Modifica |
| Report admin | Summary | Stato, Cliente, Periodo | Sintesi, Attività, Documenti | Apri / Modifica |

**Ticket compartment mapping.** The existing nine-compartment grid becomes the body of the four sections:

- **Sintesi** ← Dettagli
- **Attività** ← Ore + Storico
- **Relazioni** ← Pianificazioni + Fabbisogno + Asset
- **Allegati** (own section, inline rows; header opens the full list with upload) and **Documenti & mappa** ← Report + Controllo + Mappa

**Ticket primary action.** The hero owns the existing ticket worklog timer: `Avvia intervento` / `Chiudi intervento`. A secondary `Timbra cantiere` action appears only when the ticket has a `cantiereId`; it routes to the existing cantiere timbra screen. The cantiere punch is never faked as the ticket hero action.

**Rapportino target.** Feat 2 migrates `RapportinoViewScreen` (read-only). The view has no Modifica/Firma: the hero primary is `Scarica PDF`, or `Rilavora` when the report was rejected; the secondary is `Condividi`. The wizard/review step is out of scope.

The mapping is a starting contract, not a reason to invent data. If a screen lacks the data for a fact, drop the fact; do not add a fetch.

## Migration plan — one core feature at a time

1. **Core feat 1 — the shell + Ticket.** Build `DetailScaffold`, `DetailHero`, `DetailSection`, `DetailAction`, the collapse behaviour, the state matrix and their widget tests. Migrate only the ticket detail. No other screen changes.
2. **Core feat 2 — Rapportino view.** Adopt the shell on `RapportinoViewScreen`; hero primary is `Scarica PDF` / `Rilavora` when rejected, secondary `Condividi`; preserve the existing section internals. The wizard/review step is out of scope.
3. **Core feat 3 — Cantiere alignment.** The cantiere reference is merged on `main` (PR #192). Replace its bespoke header/hero wrapper with the shared shell; keep the day logic and the map screen unchanged.
4. **Core feat 4+ — Admin master data.** Cliente + Sede, then Commessa + Contratto, then Prodotto + Materiale + Magazzino, then Squadra + Pianificazione + Report. Batch only screens that share the same hero shape.

Each step is its own branch/PR. Do not start the next screen until the previous one is merged and its tests are green.

## Testing

- **Shell widget tests:** collapsed bar appears after the hero scrolls out; it disappears on scroll back; status/action match the expanded hero; no FAB when a primary action exists; empty sections omitted; max width respected; reduced-motion branch.
- **State tests:** disabled-with-reason for closed/active-elsewhere; hidden action for permission-denied; offline banner; pending-sync marker; loading skeleton.
- **Per-screen tests:** migrate existing expectations rather than deleting them. Keep the current section-order tests (adjusted to the new order), the timbra push test and the report-creation test.
- **No new packages.** No golden tests unless the repo already adopts them for this surface.

## Risks and builder notes

- **Ticket is the hardest migration.** It currently owns a 9-compartment grid and a timer bar. The first feat should wrap the existing section content rather than rewrite it; the grid can stay as the body of its sections.
- **Collapse measurement:** measure against the hero’s laid-out bottom, not a hard-coded scroll offset. Use a sliver/scroll listener; do not rebuild the whole page on every scroll tick.
- **Long titles and long facts:** two-line clamp, ellipsis, and `maxLines` on facts. Test with Italian strings, not placeholders.
- **Offline:** the shell must never introduce a network read. If the existing screen reads a mirror, the shell inherits that; if it does not, the shell does not add one.
- **Admin `dynamic` customer model:** out of scope; type it during the Cliente migration only if it is already being touched.
- **Delete/archive actions** stay in the header overflow, not in the hero; they are destructive and should not compete with the primary action.
- **Builder calls left open:** exact skeleton shapes, the precise collapse threshold, whether `ScreenHeader` becomes a sliver app bar, and the final file location under `lib/core/widgets/detail/`.

## Decisions resolved by the builder check

- Ticket hero = existing worklog timer; cantiere timbra is a conditional secondary action.
- Ticket's nine compartments map into the four sections as listed above.
- Rapportino feat 2 targets the read-only view screen; the hero primary is `Scarica PDF` or `Rilavora` when rejected; the wizard stays out of scope.
- The four sections are the default, with the explicit specialist-section exception.

## Open questions for the human partner

None. All five grilled properties and the four builder-check questions are decided.
