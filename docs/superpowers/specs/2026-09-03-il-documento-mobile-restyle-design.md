# Mobile shell restyle: "Il Documento" alignment — design

Status: **Draft, for review.**

## Context

Two design systems currently exist for TaskTap:

- **Web desktop** has a committed spec, `DESIGN.md` ("Il Documento" — paper/carbon/stamp-red,
  Archivo Narrow/Archivo/IBM Plex Mono typography, near-square 2px radius, hairline-driven,
  explicitly bans "glassy gradients, no blur plates, no dark-mode shadows-in-space").
- **Mobile** has two systems layered on each other: the original "Cassetta" (safety-orange,
  machined-rack corner language, Sora/Manrope) and "Vetro" (glass/blur, gradient), which — this
  was checked directly, not assumed — is **not** a small in-flight pilot. `grep` for real widget
  instantiations (`VetroGlass(`, `VetroCard(`, `VetroButton(`, `context.vetro`, etc.) across
  `lib/` returns **77 of ~89 feature-screen files**: dashboard, both ticket list and detail, all
  of `admin/*` (customers, contracts, locations, materiali, prodotti, squadre, schedules,
  magazzini, cantieri), agenda, altro, calendario, login, profilo, rapportino, timbra. Only a
  handful of screens remain on the older Cassetta look. An earlier characterization of Vetro as
  "Timbra-only, two more modules queued" was wrong — flagged and corrected before this spec was
  written, not after.

Decision (made with the corrected scope in view): **retire Vetro entirely and move the whole app
to DESIGN.md's system.** This is a full-app visual migration, not a shell-only change — "shell"
in the original ask meant nav chrome specifically, but the token-driven cascade this app already
uses (mobile is a re-skin of stock Material 3, not a custom widget kit) means the actual unit of
change is the shared theme + shared widget layer, which every screen sits on top of.

**A related, narrower prior finding, surfaced and resolved during this same design pass:**
`AppRack.cellRadius`'s own doc comment records that a squarer ~6px radius was already tried in
this app and reverted on direct user feedback ("reads as dated and over-square, not machined") —
but that finding was under Cassetta's machined-metal reading, where square corners read as a
manufacturing defect. Under Il Documento's paper/form-sheet reading, square is the intended
reading, not a flaw — different visual premise, so the decision is to use DESIGN.md's literal 2px
radius rather than hedge toward something softer. Noted here so the reasoning survives past this
conversation, in case the radius is questioned again later.

## Scope

**In scope:**
- Theme tokens: `AppColors`, `AppRack` (radius), typography (`app_text_styles.dart`,
  `app_theme.dart`'s `TextTheme`).
- The shared widget layer that currently implements Vetro:
  `vetro_glass.dart`/`vetro_card.dart`/`vetro_button.dart`/`vetro_compartment_tile.dart`/
  `vetro_map_card.dart`, plus `app_vetro_palette.dart` and any widget that reads `context.vetro`.
  These get replaced with DESIGN.md-aligned equivalents (flat sheet, hairline border, no
  `BackdropFilter`).
- `AppRack` (the shared `AppButton`/`AppCard`/`AppFab`/etc. widgets in `lib/core/widgets/` that
  are still Cassetta-styled, not yet Vetro) — brought forward to the same target system in the
  same pass, so there's one system at the end, not two.
- All 77 screens currently on Vetro, plus the remaining Cassetta screens — swept to the new
  system. Most of this is free (theme-token cascade via `Theme.of(context)`); the real per-file
  work is screens that directly instantiate a `Vetro*` widget or reference `AppVetroColors`/
  `context.vetro`, which need a mechanical swap to the new equivalent widget.
- New golden-image test coverage (package: `alchemist`, chosen over `golden_toolkit` as the
  actively-maintained successor with a cleaner CI-vs-local golden separation) for the 5 shell
  tabs plus one representative screen per module — regression protection going forward, not a
  before/after diff (there's no useful "before" once the whole system changes at once).
- Punch-clock screens' dark, theme-invariant surfaces (`AppColors.punchGround`, `stopLight`/
  `stopDark`) — these are read outdoors in direct light by design and stay dark under both
  themes; only their accent/border treatment (glass → flat) changes, not their darkness.

**Out of scope:**
- Bottom-nav vs. sidebar structural change. Mobile keeps its bottom nav (tablet already has a
  vertical-rail fallback at `wideBreakpoint` — `home_shell.dart:170-183`); this is a legitimate,
  already-handled platform convention difference from web's fixed sidebar, not something to
  unify.
- Any change to app *behavior* — this is visual only. No provider, routing, or data-flow changes.
- The two build-pipeline gaps found incidentally during the earlier CI investigation (Android R8
  missing keep-rules, iOS Podfile missing a deployment-target line) — unrelated, already reported
  separately, not part of this project.
- Icon set — mobile already uses `lucide_icons` (`bottom_nav.dart:13-17`), the same family as
  web's `lucide-react`. No work needed here.

## Design token mapping

| Token role | Current (Cassetta/Vetro) | Target (DESIGN.md) |
|---|---|---|
| Background (desk) | `AppColors.BG1` `#FAFAFA` | `#F1EEE7` paper |
| Surface (sheet/card) | Vetro glass fill (translucent, blurred) | `#FBF9F4` flat |
| Ink (primary text) | `AppColors.DARK` `#363636` | `#22252E` carbon ink |
| Muted text | `AppColors.MUTED` `#6B6B6B` (already AA-corrected, see its own doc comment) | `hsl(218 12% 44%)` — re-verify AA on `#F1EEE7`/`#FBF9F4` before locking the exact value; do not regress the outdoor-readability work `MUTED` already did |
| Border/hairline | Vetro glass border (translucent white) | `#DED9CE` — 1px hairline, "draw a line, not a box" |
| **The one accent** | `AppColors.Y` safety orange `#FF7A2E` — already documented as "the one accent," used at ~120 call sites, scarce by discipline | `#C03221` stamp red — same scarcity discipline already exists in this codebase under a different color, so the *practice* transfers even though the hue changes |
| Radius | Vetro: 20px glass corners. `AppRack.cellRadius`: 12px (Cassetta, "machined") | `2px` — DESIGN.md literal value; see Context for why the prior 6px rejection doesn't apply here |
| Display type | Sora | Archivo Narrow, 500/600/700, +2% tracking |
| Body type | Manrope | Archivo, 400/500/600 |
| Mono (codes, timestamps, status) | — (not a distinct role today) | IBM Plex Mono 400/500 |
| Blur/glass material | `VetroGlass` (`BackdropFilter`, real per-frame cost — see its own doc comment) | Retired entirely. Flat sheets only. |

Punch-clock-specific dark tokens (`punchGround`, `stopLight`/`stopDark`) are unaffected — they're
already documented as theme-invariant and stay that way; only the *border/glass* treatment around
them moves from Vetro glass to a flat hairline.

## Architecture

Three layers, in dependency order:

1. **Theme tokens** (`AppColors`, `AppRack`, `app_text_styles.dart`, `app_theme.dart`'s
   `ColorScheme`/`TextTheme`). Any widget reading `Theme.of(context)` — which is most of the app,
   since this is a Material 3 re-skin, not a custom kit — picks this up automatically with zero
   per-screen changes.
2. **Shared widget layer** (`lib/core/widgets/*.dart`). Two groups:
   - Vetro widgets (`vetro_glass.dart`, `vetro_card.dart`, `vetro_button.dart`,
     `vetro_compartment_tile.dart`, `vetro_map_card.dart`) — retired, replaced by flat
     equivalents. Whether call sites migrate to the *existing* `AppCard`/`AppButton`/etc. (which
     already exist alongside Vetro per the grep results — both systems currently coexist even at
     the widget layer) or those widgets themselves get restyled in place is a plan-time decision,
     not a design-time one — the visual target is identical either way.
   - Already-Cassetta widgets (`AppButton`, `AppCard`, `AppFab`, `AppSearchBar`, `AppStepper`,
     `AppTabs`, `AppToast`, `AppToggle`, `Badge`, `BottomNav`, `CompartmentSheet`, `EmptyState`,
     `ErrorState`, `ListRow`, `PermissionPurposeSheet`, `QuickAction`, `RowIconTile`,
     `ScreenHeader`) — restyled to the new tokens (mostly automatic via layer 1, corner-radius
     and shadow specifics need direct touch since those are hardcoded in a few of these, e.g.
     `AppRack.freeShape`/`insetShape` usage).
3. **Screens** (77 files needing a direct `Vetro*`/`context.vetro` swap, plus spot-checks on the
   remainder). Mechanical, one-shape-of-change work — matches this project's own "batch small
   same-shape work into one dispatch" convention for the implementation plan, grouped by module
   directory (`admin/*`, `rapportino/*`, `ticket/*`, etc.) rather than one task per file.

## Testing

`alchemist` golden tests for: the 5 shell tabs (Dashboard, Ticket, Timbra, Calendario, Altro) at
their default state, plus one representative screen per module (a detail screen for each
`admin/*` submodule, the rapportino editor, the ticket detail screen, login). Captured fresh
against the new system — there's no useful "before" snapshot once every screen changes in the
same pass. This becomes the regression net for future changes, not a diff for this one.

Beyond goldens: a manual click-through of all 5 shell tabs plus every golden-covered screen before
calling the migration done, since a golden test catches *regression* after this lands, not
whether the initial migration itself looks right.

## Open items for the implementation plan (not this spec)

- Exact batching of the 77-screen sweep into plan tasks (by module directory).
- Whether Vetro call sites migrate onto existing `AppCard`/`AppButton`/etc., or those get renamed/
  merged — an implementation-plan-time call, not a design-time one (visual result is identical).
- Exact AA contrast re-verification numbers for the muted-text token on the new paper/sheet
  surfaces (flagged in the token table above — must not regress `AppColors.MUTED`'s own
  documented outdoor-readability fix).
