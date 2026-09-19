---
name: TaskTap Mobile
description: Il Documento, adapted for a gloved field technician's phone
colors:
  stamp-red:
    canonical: "#C03221"
  carbon-ink:
    canonical: "#22252E"
  paper:
    canonical: "#F1EEE7"
  sheet:
    canonical: "#FBF9F4"
  muted-fill:
    canonical: "#EDEAE3"
  rule:
    canonical: "#DED9CE"
  verificato-blue:
    canonical: "#4F6BFF"
  approvato-green:
    canonical: "#248A3D"
  in-lavorazione-amber:
    canonical: "#B36200"
  non-valido-red:
    canonical: "#FF3B30"
typography:
  display:
    fontFamily: "Archivo Narrow, sans-serif"
    fontWeight: 700
  body:
    fontFamily: "Archivo, sans-serif"
    fontWeight: 400
  mono:
    fontFamily: "IBM Plex Mono, monospace"
    fontWeight: 500
rounded:
  paper: "2px"
  compartment: "1.33px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  base: "16px"
  lg: "20px"
  xl: "24px"
---

# Design System: TaskTap Mobile

<!-- Scan-mode extraction, 2026-09-16, run as part of an Impeccable critique's fix pass. Mobile
has never had its own DESIGN.md; this one exists because the app's own AppColors/AppPalette/
AppTextStyles/AppRack doc comments, plus the web app's frontend/DESIGN.md, are now the actual
sources of truth and deserved a single place a builder can read instead of chasing comments
across a dozen files. Names, palette, and manifesto below are adapted from
`../frontend/DESIGN.md` (the web app's Il Documento spec) — this file states mobile's OWN
translation of that world, not a copy of the desktop one. -->

## Overview

**Creative North Star: "Il Documento" — an Italian office where paper documents are law.**

TaskTap is field-service software for Italian trade and maintenance companies. The mobile app
puts a technician's paperwork — rapportini, timbrature, materiali — into their pocket. The web
app's Il Documento world reads that literally: a desktop back-office where a document is a
bordered sheet with registration marks and a masthead, and a status is a rubber stamp. Mobile
does not attempt that desktop reading on the technician's own daily screens (Dashboard, Timbra,
the rapportino wizard) — those screens carry the world's *material rules* (flat, no glass, no
floating cards, one scarce red accent) and its *status device* (the Stamp, not a pill), but not
its literal paper/masthead/registration-mark furniture, which reads as an office-desk metaphor a
gloved technician in direct sun has no use for. On the admin CRUD surface reached through Altro —
where the office/admin persona actually works — the world can carry more of that literal
character; as of this writing it mostly does not yet (see Do's and Don'ts).

**Key Characteristics:**
- Flat surfaces only: no shadows, no blur, no gradients. A hairline rule or a step in the
  background scale does the job a shadow used to.
- One scarce accent: stamp red appears on the active/primary action and nowhere else as
  decoration.
- Status is a stamp: a double-ring (or single-ring for "in lavorazione"), slightly rotated,
  all-caps Archivo Narrow badge — never a plain colored pill.
- Mono marks identity: IBM Plex Mono is reserved for document codes and running timestamps, never
  body text or labels.
- Both themes are first-class, explicit user choices (never `ThemeMode.system`) — every named
  color below has a verified-AA light and dark value; see `app_palette.dart`'s own doc comments
  for the exact pairs and their contrast ratios.

## Colors

Paper and ink, with exactly one saturated color.

### Primary
- **Stamp Red** (`#C03221`): the one accent — primary buttons, the FAB, the active bottom-nav
  tab, a Stamp's ring/ink when its status family is "info-adjacent" is NOT this color (see
  Semantic below) — Stamp Red itself is reserved for the primary action and the active-document
  read, per the "red stamps are scarce" rule inherited from the web world.

### Neutral
- **Carbon Ink** (`#22252E`): primary text. 13.21:1 on Paper.
- **Slate** (`#5E6878`): secondary text — captions, list-row subtitles. 4.86:1 on Paper.
- **Paper** (`#F1EEE7`): the page ground (`bg1`/`bg2`).
- **Sheet** (`#FBF9F4`): a card, an input, a dialog — the raised paper surface.
- **Muted Fill** (`#EDEAE3`): an input/muted fill (`bg3`).
- **Rule** (`#DED9CE`): the one hairline border/divider value. Every border in the app is this,
  at 1px — there is no second border weight.

### Semantic (Stamp families — see Components/Status Stamp)
- **Verificato / info** (`#4F6BFF` light, `#7C93FF` dark): "in flight, needs eyes" — open,
  awaiting, submitted-but-not-yet-reviewed states.
- **Approvato / good** (`#248A3D` light, `#3DD866` dark): completed, paid, active — the only
  non-red "approved" ink, to stay legal-adjacent per the web world's own rule.
- **In lavorazione / warn** (`#B36200` light, `#FFB238` dark): actively being worked.
- **Non valido / bad** (`#FF3B30` light, `#FF6961` dark): cancelled, expired, suspended, rejected
  — the one family that also carries a coarse ink texture, reserved for exactly this severity.

### Named Rules
**The One Accent Rule.** Stamp Red is the primary action and the active state. It is not a
decoration, a link color, or a second "brand" wash — every other saturated need routes through
the Semantic stamp families above instead.

## Typography

**Display Font:** Archivo Narrow (with system sans-serif fallback)
**Body Font:** Archivo (with system sans-serif fallback)
**Label/Mono Font:** IBM Plex Mono

**Character:** A condensed, slightly industrial display face over a plain, legible body face —
built to be read fast, one-handed, in direct sun, not admired up close.

### Hierarchy
- **Display** (Archivo Narrow 700, 26–32px): screen-level headings, KPI figures.
- **Headline** (Archivo Narrow 600, 18–22px): section headers, dialog titles.
- **Title** (Archivo Narrow 600, 14–16px): card/list-row titles, compartment tile labels.
- **Body** (Archivo 400, 14–16px): running text, form values.
- **Label** (Archivo 500–600, 11–14px, tracked): buttons, chips, stamp text (uppercase).
- **Mono** (IBM Plex Mono 500, tabular figures): running-clock readouts, document/reference
  codes, punch timestamps — nothing else.

### Named Rules
**The Mono Scarcity Rule.** IBM Plex Mono marks identity — a code, a number, a clock — never a
costume for "feels technical." If it isn't a code, a timestamp, or a clock, it is Archivo.

## Layout

Single-column phone layout throughout; a `>600px` width (tablet, unfolded foldable) switches the
bottom navigation from a floating bar to a leading-edge rail (see Components/Navigation) and
compartment grids gain a fourth column. Compartment/checklist grids are the app's own structural
idiom for a multi-part task (the rapportino's Dettagli/Ore/Controlli/Materiali tiles): square
tiles, `mainAxisSpacing`/`crossAxisSpacing` at the `md` (12px) step, never more than one row of
primary choices before the rest folds into a review step. Screen padding uses the spacing scale's
`pagePadding` step; content that sits under the floating bottom nav reserves `context.navClearance`
so nothing is ever occluded.

## Elevation & Depth

**Flat, deliberately.** No card shadows in either theme — depth is a hairline `Rule` border and
a step in the background scale (Paper → Sheet → Muted Fill), never a cast shadow or a blur. This
is a named rule inherited directly from the web world and holds without exception across every
surface audited in the 2026-09-16 critique.

### Named Rules
**The Flat-By-Default Rule.** Surfaces are flat at rest and stay flat. A raised layer reads as
raised because it steps to a lighter/darker named surface, not because it casts a shadow.

## Shapes

**Near-square.** `AppRack.cellRadius` (2px) is the standard corner radius — "paper, nearly
square" — used on cards, dialogs, and standalone sheets. `AppRack.insetRadius` (2px ÷ 1.5,
≈1.33px) is for a compartment nested inside a larger container (a material line, an hour tile).
Borders are always 1px, the single `Rule` color.

**Known drift (honest, not aspirational):** several widgets still carry pre-Documento radii that
were never migrated onto these tokens — the bottom nav's pill (10–16px) and a scattered handful
of others in `lib/core/widgets/`. Treat the 2px token as the standard for new work; migrating the
stragglers is tracked, not yet done.

## Components

### Buttons
- **Shape:** `AppRack.cellRadius`-family rounding (see Shapes' own honesty note — `AppButton`
  currently uses a slightly larger local radius scale of its own).
- **Primary:** Stamp Red fill, `brandOn` (near-white paper) text/icon — never Stamp Red used
  directly as a text color on a surface that isn't a solid fill (`AppPalette.accentInk` exists
  specifically for the rare case text needs the accent's hue and must survive both themes).
- **Secondary / Ghost / Danger:** neutral/`redSoft` fills per `AppButton`'s own variant set.

### Status Stamp
The world's signature device (`lib/core/widgets/status_stamp.dart`) — double- or single-ring
border, all-caps Archivo Narrow, a slight (±1.4°) label-stable rotation, family-driven ring/fill
per the Semantic colors above, a coarse ink-fleck texture reserved for the "Non valido" family
only. Replaces every flat colored status pill in the app (`StatusPill`/`StatusBadge` both render
through it). An optional "stamping" entrance (scale 1.18→0.95→1 over 220ms) is reserved for the
moment a status genuinely becomes true — a report's own submission success, not a status
scrolling into view in a list.

### Cards / Containers
- **Corner Style:** `AppRack.cellRadius` (2px).
- **Background:** Sheet on Paper.
- **Shadow Strategy:** none — see Elevation & Depth.
- **Border:** 1px `Rule`.

### Navigation
Floating flat-sheet bar (phone) / leading-edge rail (≥600px width) — Sheet fill, 1px `Rule`
border, no blur, no gradient. The active tab is a solid Stamp Red fill with white label; inactive
tabs are icon-only in muted ink. See Shapes' honesty note on this component's own un-migrated
radius.

## Do's and Don'ts

### Do:
- **Do** keep every surface flat — a hairline border and a named background step, never a shadow.
- **Do** route status display through `StatusStamp`, not a bespoke colored pill.
- **Do** reserve IBM Plex Mono for codes, references, and running clocks.
- **Do** keep Stamp Red scarce — the primary action and the active state, nothing else.
- **Do** verify a new color pair against both themes' own AA floor before shipping it (see
  `app_palette_contrast_test.dart` and `AppPalette.accentInk`'s own doc comment for the shape of
  bug this catches).

### Don't:
- **Don't** add card shadows, gradients, or `BackdropFilter` blur — three prior visual eras of
  this app (Cassetta, Vetro) used exactly these devices, and this world is a deliberate reaction
  against all three.
- **Don't** hardcode `fontFamily: 'Inter'` (or any font literal) in a new widget — use
  `AppTextStyles`/the theme's own `TextTheme`, so the display/body/mono split stays real instead
  of aspirational.
- **Don't** build a second literal "paper office" reading (registration marks, a masthead strip,
  an Indice sidebar) for the technician's own screens — that furniture belongs to the web app's
  desktop context, not a gloved phone in direct sun. It is fair game for Altro's admin surface,
  where the office persona actually works, if a future pass deliberately chooses to build it
  there.
