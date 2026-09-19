# Il Documento — Theme + Shared Widget Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire Vetro (glass/blur/gradient) at the theme-token and shared-widget layer, replacing it
with DESIGN.md's "Il Documento" flat paper system, so every screen built on `Theme.of(context)`
and the shared `lib/core/widgets/*` components inherits the new look automatically.

**Architecture:** This is Plan 1 of 2 for the mobile restyle. Grounding done during plan-writing
(not assumed from the spec) found that Vetro is not a separate, optional layer sitting beside the
Cassetta-named shared widgets — `AppCard`, `AppButton`, `AppBottomNav`, and 15 other files in
`lib/core/widgets/` already delegate internally to `VetroGlass`/`context.vetro`, wearing
Cassetta-era names. Fixing this widget layer (plus the theme tokens it reads) is therefore the
single highest-leverage change: it cascades to every screen using these shared widgets for free,
with zero screen-level code change. Only screens that bypass these shared widgets and call a raw
`Vetro*` widget or `context.vetro` directly (51 of ~89 screen files, re-counted precisely via
`grep` during plan-writing — not the spec's rougher "77 screens referencing Vetro in any way")
need a further, separate sweep. That sweep is **Plan 2**, written after this plan ships, because
its exact instructions depend on the target widget APIs this plan produces (e.g. what replaces
`VetroCompartmentTile` doesn't exist to reference until Task 4 below creates it).

**Tech Stack:** Flutter, Material 3 theme extensions, `alchemist` (golden tests, new dependency).

**Spec:** `docs/superpowers/specs/2026-09-03-il-documento-mobile-restyle-design.md`

## Global Constraints

- Token **names** stay the same; only what they resolve to changes — this codebase's own
  established pattern (`AppColors.Y`'s doc comment: "repointing what those resolve to carries the
  whole app's ... discipline over to the new hue without touching call sites"). Do not rename
  `AppColors.Y`, `AppRack.cellRadius`, etc. — repoint their values.
- Radius: `AppRack.cellRadius` → **2px** (was 12px), `AppRack.insetRadius` stays derived
  (`cellRadius / 1.5` → 1.33px, round to **1px** in practice — Flutter radii are doubles, but
  round the *visual* target when it matters, e.g. `BorderRadius.circular`).
- No `BackdropFilter`/blur/gradient anywhere in the shared widget layer after this plan — DESIGN.md
  Rules: "No floating cards... forms, not frames... draw a line, not a box."
- The one accent color is stamp red `#C03221` — used exactly where `AppColors.Y` (safety orange)
  was the one accent before. Scarcity discipline carries over unchanged, only the hue changes.
- Muted/secondary text: `#5E6878` (computed during plan-writing — see Task 1's own contrast-ratio
  verification; do not reuse the spec's placeholder `hsl(218 12% 44%)`/`#636D7E`, which clears the
  AA floor by only 0.01 on the desk background — too close to the edge for the safety margin this
  codebase's own `MUTED` doc comment establishes as its bar).
- Bottom nav **position/shape stays the floating pill** (not flattened to a flush bar) — its
  clearance math (`AppRack.navBarHeight`/`navGap`, `context.navClearance`) is real, tested
  infrastructure consumed by ~9 detail screens for FAB placement; only its **material** changes
  (Vetro glass/gradient → flat Documento sheet). This is a deliberate, narrower scope than the
  brainstorm mockup's literal flush-bar sketch — the mockup illustrated the *palette/material*
  direction, not a nav-shape mandate, and reversing the pill's proven clearance system is separate,
  higher-risk work not asked for here. If this reads as a real regression once built, that's a
  Plan 2 (or Plan 3) discussion, not a silent call to make now.
- Punch-clock (Timbra) dark, theme-invariant surfaces (`AppColors.punchGround`, `stopLight`/
  `stopDark`) are **out of scope** for this plan — untouched.

---

### Task 1: Theme tokens — `AppColors`, `AppRack`, `AppTextStyles`

**Files:**
- Modify: `lib/core/theme/app_colors.dart`
- Modify: `lib/core/theme/app_rack.dart:25` (`cellRadius`)
- Modify: `lib/core/theme/app_text_styles.dart`
- Test: `test/core/theme/app_colors_contrast_test.dart` (new file)

**Interfaces:**
- Produces: every `AppColors.*` / `AppRack.cellRadius` / `AppRack.insetRadius` / `AppTextStyles.*`
  call site in the app picks up the new values automatically — no other file changes for this task.

Exact verified values (computed via WCAG relative-luminance formula during plan-writing, not
estimated):

| Token | Old | New | Contrast vs. `#F1EEE7` (desk) | vs. `#FBF9F4` (sheet) |
|---|---|---|---|---|
| `Y` (the one accent) | `#FF7A2E` | `#C03221` | 4.87:1 | 5.37:1 |
| `YDark` (pressed) | `#D9600F` | `#9D2A1B` | — | — |
| `YSoft` (translucent, 20% alpha) | `0x33FF7A2E` | `0x33C03221` | — | — |
| `DARK` (primary ink) | `#363636` | `#22252E` | 13.21:1 | 14.55:1 |
| `CHARCOAL` | `#2B2A24` | `#22252E` (consolidated — see note) | 13.21:1 | 14.55:1 |
| `MUTED` (secondary text) | `#6B6B6B` | `#5E6878` | 4.86:1 | 5.35:1 |
| `FG2` | `#707070` | `#5E6878` (consolidated — see note) | 4.86:1 | 5.35:1 |
| `DIS` (disabled) | `#B4B4B4` | `#B1ACA0` | n/a (disabled text is AA-exempt) | n/a |
| `INV` | `#F2F2F2` | `#FBF9F4` | — | — |
| `BG1` (page ground) | `#FAFAFA` | `#F1EEE7` | — | — |
| `BG2` | `#F7F7F7` | `#F1EEE7` (consolidated — see note) | — | — |
| `BG3` (input/muted fill) | `#F2F2F2` | `#EDEAE3` | 12.74:1 (vs ink) | — |
| `BG4` | `#EDEDED` | `#EDEAE3` (consolidated — see note) | 12.74:1 (vs ink) | — |
| `BL`/`BM`/`BS`/`DIV` (borders/dividers) | 3 greys | `#DED9CE` (all four collapse to one hairline value) | — | — |

Notes on consolidation: DESIGN.md defines one ink, one accent, one border weight ("hairlines do
the work... when in doubt, draw a line, not a box") — Cassetta's four-step background and
three-step border scale don't have a DESIGN.md equivalent, so they collapse onto DESIGN.md's
actual two named surfaces (`desk`/`sheet`) plus its one named `--muted` fill and one named
`--border`. This is a deliberate flattening, not an oversight — matches DESIGN.md's own explicit
"Rules" section, not a compromise.

`AppColors.surface`/`AppCard`'s sheet fill is `#FBF9F4` — a NEW alias needed since no existing
token currently means "sheet, not desk." Add it:

```dart
  /// The sheet surface — a card, a form panel, an input fill's raised state. Distinct from [BG1]
  /// (the page ground/desk) — DESIGN.md's two named surfaces, not previously distinguished in
  /// this token set (BG1-4 were four steps of the same ground).
  static const Color SHEET = Color(0xFFFBF9F4);
```

- [ ] **Step 1: Write the failing contrast test**

```dart
// test/core/theme/app_colors_contrast_test.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';

// WCAG relative luminance: linearize each 0.0-1.0 sRGB channel (Color.r/.g/.b are already
// 0.0-1.0 doubles as of the Flutter Color API this app's pinned SDK ships), then weight-sum.
double _linearize(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppColors AA contrast on the new paper surfaces', () {
    test('MUTED clears 4.5:1 on BG1 (desk)', () {
      expect(_contrast(AppColors.MUTED, AppColors.BG1), greaterThanOrEqualTo(4.5));
    });

    test('MUTED clears 4.5:1 on SHEET', () {
      expect(_contrast(AppColors.MUTED, AppColors.SHEET), greaterThanOrEqualTo(4.5));
    });

    test('DARK (ink) clears 4.5:1 on BG1', () {
      expect(_contrast(AppColors.DARK, AppColors.BG1), greaterThanOrEqualTo(4.5));
    });

    test('Y (stamp red) clears 4.5:1 on BG1 when used as text/icon', () {
      expect(_contrast(AppColors.Y, AppColors.BG1), greaterThanOrEqualTo(4.5));
    });

    test('white clears 4.5:1 on Y (button foreground)', () {
      expect(_contrast(Colors.white, AppColors.Y), greaterThanOrEqualTo(4.5));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_colors_contrast_test.dart`
Expected: FAIL — `AppColors.SHEET` doesn't exist yet, and the old `Y`/`MUTED` values don't clear
the new surfaces' contrast floor (old `MUTED` `#6B6B6B` on new `BG1` `#F1EEE7` — verify this
actually fails at today's values as part of confirming the test is real, not vacuous).

- [ ] **Step 3: Apply the token values**

In `lib/core/theme/app_colors.dart`, replace each `Color` constant's value per the table above
(keep every doc comment, class structure, and the "Legacy aliases" section unchanged — only the
hex/alpha literals inside the already-existing `static const Color X = Color(0x...)` lines
change). Add the new `SHEET` constant (shown above) in the `// ── Surfaces` section, directly
after `BG4`. Update `BL`/`BM`/`BS`/`DIV` to all read `Color(0xFFDED9CE)`.

In `lib/core/theme/app_rack.dart:25`, change:
```dart
  static const double cellRadius = 12;
```
to:
```dart
  static const double cellRadius = 2;
```
(Update the class doc comment above it — delete the "settled at the validated number" paragraph
describing the 6px-vs-12px history; replace with: `/// 2px — DESIGN.md's literal "near-square,
paper" radius. See the Il Documento restyle plan's Global Constraints for why the app's earlier
6px rejection (under Cassetta's machined-metal reading) doesn't apply here (different visual
premise — square reads as a form sheet, not a manufacturing defect).`)

In `lib/core/theme/app_text_styles.dart`, every `fontFamily: 'Inter'` becomes `fontFamily:
'Archivo'` for body/label styles (`bodyLarge`/`bodyMedium`/`bodySmall`/`labelLarge`/`labelMedium`/
`labelSmall`/`caption`), and `fontFamily: 'Archivo Narrow'` for display/heading styles
(`displayLarge`/`displayMedium`/`headlineLarge`/`headlineMedium`/`titleLarge`/`titleMedium`/
`kpi`). Update the class doc comment's "Display / titles → Sora... Body / labels → Manrope" to
"Display / titles → Archivo Narrow. Body / labels → Archivo." Add the Google Fonts package
dependency if not already present (check `pubspec.yaml` for `google_fonts:` — if absent, add
`google_fonts: ^6.2.1` and load `Archivo`/`Archivo Narrow`/`IBM Plex Mono` via
`GoogleFonts.archivoTextTheme()`-style helpers rather than bundling font assets, matching whatever
pattern `pubspec.yaml` already uses for Sora/Manrope — check `pubspec.yaml`'s `fonts:` section for
the existing asset-bundling approach and mirror it exactly for Archivo/Archivo Narrow/IBM Plex
Mono if fonts are currently bundled as assets rather than via `google_fonts`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/app_colors_contrast_test.dart`
Expected: PASS — all 5 assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_colors.dart lib/core/theme/app_rack.dart lib/core/theme/app_text_styles.dart test/core/theme/app_colors_contrast_test.dart
git commit -m "feat(theme): repoint tokens to Il Documento palette/type/radius"
```

---

### Task 1b: `AppPalette` — repoint the theme-extension most widgets actually read

**Added after Task 1 shipped.** Task 1's implementer found, correctly, that `AppColors` is not
what most of the app reads for color — `context.colors` (used pervasively by `AppButton`,
`AppCard`, and nearly everything else) resolves through `lib/core/theme/app_palette.dart`'s
`AppPalette`, a **separate, hand-duplicated** token set (`AppPalette.light`/`.dark`, a
`ThemeExtension`). Task 1 only repointed `AppColors`; this task repoints `AppPalette`, which is
what actually cascades to the app. Without this task, Task 2's `AppCard`/`AppButton` rewrite would
show stamp red on the primary button (reads `AppColors.Y` directly) while every secondary/dark/
ghost/danger variant and every `AppCard` border still shows old Cassetta colors (reads
`context.colors.*` → unrepointed `AppPalette`) — a visibly broken, half-migrated state.

**Files:**
- Modify: `lib/core/theme/app_palette.dart`
- Test: `test/core/theme/app_palette_contrast_test.dart` (new file)

**Interfaces:**
- Produces: `AppPalette.light`/`AppPalette.dark`'s field VALUES change; field NAMES and the
  `ThemeExtension` shape are unchanged — every `context.colors.X` call site across the app needs
  zero edits.

DESIGN.md defines no dark theme. Rather than leave dark mode broken or invent an unrelated look,
the dark palette below was derived the same way this file's own existing dark palette was
originally derived (documented in its own doc comments): lighten each light-mode ink-role color
until it clears AA on the new dark ground, keep the same hue family, don't invent a second design
language for dark mode. All values below were computed and verified via the WCAG contrast formula
during plan-writing — trust them, don't re-derive.

Real correction made in this pass, beyond a mechanical repoint: `brandOn` (text on the brand
accent fill) was dark ink in Cassetta because safety orange was too light for white text to clear
AA on. Stamp red is darker/more saturated — white-on-stamp clears 5.37:1 (verified) — so `brandOn`
becomes near-white here, not dark ink. This also matches Task 2's `AppButton` code, which already
hardcodes `Colors.white` as the primary variant's foreground; this task makes `AppPalette.brandOn`
consistent with that rather than leaving a token that disagrees with the code that (in the
concrete case) doesn't even read it.

Also real: DESIGN.md's Rules explicitly ban card shadows ("no floating cards... draw a line, not a
box") — `shadow`/`shadowInset` become empty lists, not just recolored.

| Field | Light (new) | Dark (new) | Note |
|---|---|---|---|
| `ink` | `#22252E` | `#EEECE8` | dark clears 13.94:1 on `bg2` dark |
| `inkMuted` | `#5E6878` | `#8D96A5` | dark clears 5.51:1 on `bg2` dark |
| `inkFaint` | `#5E6878` | `#8D96A5` | consolidated onto `inkMuted`'s value — DESIGN.md has no third text tier (same consolidation Task 1 already applied to `AppColors.FG2`) |
| `inkDisabled` | `#B1ACA0` | `#6B6B6B` (unchanged from today's dark value — disabled text is AA-exempt, no need to re-derive) |
| `inkInverse` | `#22252E` | `#1E1F24` | text on `surfaceInverse` — same value as the new `ink`/`bg2`-dark pairing in each theme |
| `surface` | `#FBF9F4` | `#1E1F24` | the sheet |
| `surfaceInverse` | `#22252E` | `#EEECE8` | a deliberately-contrasting fill; equals `ink`'s value in each theme, same relationship the current light palette already has (`ink`==`surfaceInverse` conceptually swapped) |
| `bg1` | `#F1EEE7` | `#17181C` | desk / deepest dark ground |
| `bg2` | `#F1EEE7` | `#1E1F24` | consolidated onto `bg1` in light (DESIGN.md has two NAMED surfaces, not four steps — same consolidation Task 1 applied) |
| `bg3` | `#EDEAE3` | `#272930` | muted fill |
| `bg4` | `#EDEAE3` | `#30333B` | consolidated onto `bg3` in light |
| `borderLight`/`borderMedium`/`borderStrong`/`divider` | `#DED9CE` (all four collapse to one hairline) | `#383B42` (all four collapse to one hairline) | DESIGN.md: "hairlines do the work... draw a line, not a box" |
| `shadow` | `[]` | `[]` | DESIGN.md bans floating-card shadows |
| `shadowInset` | `[]` | `[]` | same |
| `amber`/`green`/`blue`/`cyan`/`red`/`redSoft` | **unchanged** from current light values | **unchanged** from current dark values | semantic status colors are not part of DESIGN.md's ink/accent/surface system — same "leave untouched" decision Task 1 already made for `AppColors.RED`/`GREEN`/`BLUE`/`CYAN`/`AMBER` |
| `brandOn` | `#FBF9F4` | `#FBF9F4` | same value in both themes — the brand accent itself doesn't flip with theme, so neither does its foreground (see correction note above) |
| `labelCard` | `#FBF9F4` | `#1E1F24` | equals `surface` in each theme — the warm/neutral distinction that motivated a separate `labelCard` no longer applies, since Il Documento's `surface`/`bg1` are already warm paper tones, not neutral grey (unlike Cassetta's `#FFFFFF`/`#FAFAFA`) |

Known residual, not fixed by this task: stamp red used directly as **text** (not a button fill
with white text on top) only clears 2.91:1 on the new dark `bg2` — below AA. This doesn't
currently matter (punch-clock, the one permanently-dark surface in the app, is out of scope for
this whole plan) but would matter if a future dark-mode screen ever renders the accent as text
color rather than a filled chip. Noted here rather than silently left for someone to discover via
a failed contrast check later.

- [ ] **Step 1: Write the failing contrast test**

```dart
// test/core/theme/app_palette_contrast_test.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

double _linearize(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppPalette AA contrast — light', () {
    test('ink clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.light.ink, AppPalette.light.bg2), greaterThanOrEqualTo(4.5));
    });
    test('inkMuted clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.light.inkMuted, AppPalette.light.bg2), greaterThanOrEqualTo(4.5));
    });
    test('inkMuted clears 4.5:1 on surface', () {
      expect(_contrast(AppPalette.light.inkMuted, AppPalette.light.surface), greaterThanOrEqualTo(4.5));
    });
    test('brandOn clears 4.5:1 on the brand accent (0xFFC03221)', () {
      expect(_contrast(AppPalette.light.brandOn, const Color(0xFFC03221)), greaterThanOrEqualTo(4.5));
    });
    test('shadow and shadowInset are empty — DESIGN.md bans floating-card shadows', () {
      expect(AppPalette.light.shadow, isEmpty);
      expect(AppPalette.light.shadowInset, isEmpty);
    });
  });

  group('AppPalette AA contrast — dark', () {
    test('ink clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.dark.ink, AppPalette.dark.bg2), greaterThanOrEqualTo(4.5));
    });
    test('inkMuted clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.dark.inkMuted, AppPalette.dark.bg2), greaterThanOrEqualTo(4.5));
    });
    test('brandOn clears 4.5:1 on the brand accent (0xFFC03221)', () {
      expect(_contrast(AppPalette.dark.brandOn, const Color(0xFFC03221)), greaterThanOrEqualTo(4.5));
    });
    test('shadow and shadowInset are empty — DESIGN.md bans floating-card shadows', () {
      expect(AppPalette.dark.shadow, isEmpty);
      expect(AppPalette.dark.shadowInset, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_palette_contrast_test.dart`
Expected: FAIL — current `AppPalette.light`/`.dark` still hold Cassetta values, `shadow`/
`shadowInset` are non-empty, `brandOn` doesn't clear AA against the new stamp-red accent yet.

- [ ] **Step 3: Apply the token values**

In `lib/core/theme/app_palette.dart`, replace every field's value in both `static const light`
and `static const dark` per the table above (keep the class structure, `copyWith`, `lerp`, and the
`AppPaletteContext` extension completely unchanged — only the literal values inside the two
`static const` instances change). Update the class-level and per-field doc comments that describe
*why* a value is what it is (e.g. `brandOn`'s doc comment currently says light text would be
unreadable on the brand fill — that's no longer true, replace it with the corrected reasoning from
this task's own notes above). Do not touch `shadow`'s/`shadowInset`'s doc comments' explanation of
*why dark needs heavier shadows* — replace both with a comment explaining they're empty now
because DESIGN.md bans card shadows entirely, not because dark/light need different weights.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/app_palette_contrast_test.dart`
Expected: PASS — all assertions.

Then run the full suite: `flutter test`. Task 1's 9 AppPalette-driven failures (documented in its
report) should now pass, since this task is exactly what those failures were waiting on. If any
of those 9 still fail, read the actual assertion — it may be pinned to an old literal value that
also needs updating (matching the same "old-value pin" pattern Task 1's implementer already fixed
5 instances of), not a sign this task's token values are wrong.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_palette.dart test/core/theme/app_palette_contrast_test.dart
git commit -m "feat(theme): repoint AppPalette to Il Documento — the layer context.colors actually reads"
```

---

### Task 2: `AppCard` and `AppButton` — retire their Vetro dependency

**Files:**
- Modify: `lib/core/widgets/app_card.dart`
- Modify: `lib/core/widgets/app_button.dart`
- Test: `test/core/widgets/app_card_test.dart` (extend if it exists, else create)
- Test: `test/core/widgets/app_button_test.dart` (extend if it exists, else create)

**Interfaces:**
- Consumes: `AppColors.SHEET`, `AppColors.Y` (Task 1).
- Produces: `AppCard`'s and `AppButton`'s public constructors/parameters are **unchanged** — every
  existing call site across the app (33+ `AppCard(...)` sites, every `AppButton(...)`/
  `.secondary`/`.dark`/`.ghost`/`.danger` site) needs zero edits. Only what's inside `build()`
  changes.

`AppCard` currently wraps `VetroGlass` (blur, translucent fill, `context.vetro` border). Replace
with a flat `DecoratedBox`:

```dart
// lib/core/widgets/app_card.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';

/// The app's general-purpose container — a flat Documento sheet.
///
/// Public API unchanged — every `AppCard(child: …)` call site across the app means "a block of
/// content" exactly as before; only the material changed (flat sheet + hairline, not glass/blur).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
    this.strapped = false,
    this.flush = true,
  });

  const AppCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding,
    this.borderColor,
    this.backgroundColor,
    this.strapped = false,
    this.flush = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Overrides the sheet's border colour. [strapped] wins when both are set.
  final Color? borderColor;

  final Color? backgroundColor;

  /// Selected, priority, or still-needs-finishing — turns the border stamp-red. Not for a
  /// live/running state: that's `LiveDot`, a different mark.
  final bool strapped;

  /// No longer consulted (kept for call-site compatibility — see the pre-existing `flush` field
  /// on this widget before this change; it already did nothing).
  final bool flush;

  static const EdgeInsets _defaultPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);
  static const _radius = AppRack.freeShape;

  @override
  Widget build(BuildContext context) {
    final border = strapped ? AppColors.Y : (borderColor ?? const Color(0xFFDED9CE));
    final content = Padding(padding: padding ?? _defaultPadding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.SHEET,
        borderRadius: _radius,
        border: Border.all(color: border, width: 1),
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: _radius,
              child: InkWell(borderRadius: _radius, onTap: onTap, child: content),
            ),
    );
  }
}
```

`AppButton`'s only Vetro dependency is its `primary` variant's gradient fill
(`context.vetro.tint`/`tintStrong`) — every other variant already reads plain `AppColors`/
`context.colors` tokens. Replace `_bg`/`_gradient` in `lib/core/widgets/app_button.dart`:

```dart
  /// Solid fill for every variant, including [primary] — DESIGN.md has no gradient fills
  /// ("no glassy gradients"). [primary] is now a flat [AppColors.Y] fill, matching every other
  /// variant's flat-fill treatment.
  Color _bg(BuildContext context) => switch (variant) {
    AppButtonVariant.primary => AppColors.Y,
    AppButtonVariant.secondary => context.colors.bg3,
    AppButtonVariant.dark => context.colors.surfaceInverse,
    AppButtonVariant.ghost => Colors.transparent,
    AppButtonVariant.danger => context.colors.redSoft,
  };

  // _gradient removed entirely — no variant paints a gradient anymore. Remove the `Gradient?
  // _gradient(BuildContext context)` method and its two call sites in `build()`:
  //   `gradient: enabled ? _gradient(context) : null,` → delete this line
  //   `color: enabled ? (_gradient(context) == null ? _bg(context) : null) : bgDisabled,` →
  //     becomes `color: enabled ? _bg(context) : bgDisabled,`
```

Also add `import '../theme/app_colors.dart';` to `app_button.dart` if not already present (check
first — `context.colors.*` calls suggest an existing palette import; `AppColors.Y` is a different,
possibly-not-yet-imported class).

- [ ] **Step 1: Write/extend the failing tests**

```dart
// test/core/widgets/app_card_test.dart — add this test to the existing file, or create it with
// this single test if the file doesn't exist yet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';

void main() {
  testWidgets('AppCard renders a flat sheet, no BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppCard(child: Text('hi')))),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = decoratedBox.decoration as BoxDecoration;
    expect(decoration.color, AppColors.SHEET);
    expect(decoration.gradient, isNull);
  });
}
```

```dart
// test/core/widgets/app_button_test.dart — add this test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';

void main() {
  testWidgets('AppButton primary variant has no gradient fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AppButton(label: 'Salva', onPressed: () {}))),
    );

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = decoratedBox.decoration as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.color, AppColors.Y);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/widgets/app_card_test.dart test/core/widgets/app_button_test.dart`
Expected: FAIL — `AppCard` still renders `BackdropFilter`/`VetroGlass`; `AppButton` primary still
paints a gradient.

- [ ] **Step 3: Apply the widget rewrites**

Replace `lib/core/widgets/app_card.dart`'s full contents with the code shown above. Apply the
`_bg`/`_gradient` edit to `lib/core/widgets/app_button.dart` as shown, removing the now-dead
`_gradient` method and its two `build()` call sites, and updating the `_bg` doc comment (the old
one references "the real fill is `_gradient`" — delete that sentence, it's no longer true).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/widgets/app_card_test.dart test/core/widgets/app_button_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/app_card.dart lib/core/widgets/app_button.dart test/core/widgets/app_card_test.dart test/core/widgets/app_button_test.dart
git commit -m "feat(widgets): AppCard/AppButton render flat Documento sheets, no more glass/gradient"
```

---

### Task 3: `AppBottomNav` — flat material, stamp-red active state, same clearance math

**Files:**
- Modify: `lib/core/widgets/bottom_nav.dart`
- Test: `test/core/widgets/bottom_nav_test.dart` (extend if it exists, else create)

**Interfaces:**
- Consumes: `AppColors.Y` (Task 1, the brand accent — theme-invariant, same legitimate exception
  `AppButton`'s primary variant already uses, confirmed correct in Task 2's review),
  `context.colors.surface`/`context.colors.borderLight` (Task 1b's `AppPalette`, theme-flipping —
  see the correction note below), `AppRack.cellRadius` (Task 1).
- Produces: `AppBottomNav`'s constructor and `defaultItems`/`wideBreakpoint` are unchanged —
  `HomeShell` (the only consumer) needs zero edits.

**Correction made during Task 2's fix-loop, applies here too:** the original version of this
task's code (below) used `AppColors.SHEET` and a hardcoded border hex directly — the same
theme-invariant-constant-instead-of-theme-flipping-token bug Task 2's review caught and fixed in
`AppCard`. `AppColors.SHEET` is `surface`'s LIGHT-mode value only; reading it directly means the
bottom nav would render a bright cream bar even in dark mode, a live regression given this app has
a real, persisted dark-mode toggle (`main.dart`, confirmed in Task 2's review). Already fixed in
the code below — `context.colors.surface`/`context.colors.borderLight`, not the raw constants.

Per the Global Constraints: keep the floating pill's position/shape/clearance math exactly as-is
(`_buildBar`/`_buildRail`'s `Padding`/`SafeArea`/`AppRack.navBarHeight` structure, and
`NavClearance`/`FabSafeBottom` in `app_rack.dart` are untouched by this task). Only the material
inside the pill changes: drop the `BackdropFilter`/`ClipRRect`/glass-fill `DecoratedBox` for a
flat sheet, and drop the active tab's gradient for a flat stamp-red fill.

In `_buildBar` (and identically in `_buildRail`), replace:

```dart
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: AppVetroColors.blurSigma,
                  sigmaY: AppVetroColors.blurSigma,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: v.glassFill,
                    border: Border.all(color: v.glassBorder, width: 0.5),
                  ),
```

with:

```dart
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: context.colors.surface,
              border: Border.all(color: context.colors.borderLight, width: 1),
            ),
            child: Builder(
              builder: (context) {
                return
```

(Remove the matching closing `)` for the deleted `RepaintBoundary`/`ClipRRect`/`BackdropFilter`
nesting — three fewer closing parens/braces than before; also delete `import 'dart:ui';` if
nothing else in the file uses `ImageFilter` after this change, and remove the `v` parameter
threading — `_buildBar`/`_buildRail` no longer need `AppVetroPalette v` since nothing reads it;
simplify their signatures to drop that parameter and update `build()`'s two call sites
accordingly.)

In `_NavTab.build()`, replace the active-tab gradient:

```dart
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppVetroColors.tint, AppVetroColors.tintStrong],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
```

with:

```dart
          decoration: BoxDecoration(
            color: active ? AppColors.Y : null,
            borderRadius: BorderRadius.circular(12),
          ),
```

Remove the now-unused `import '../theme/app_vetro_palette.dart';` and add
`import '../theme/app_colors.dart';` if not already present. The `_NavTab.item.icon`/`label`
white-on-active-pill color logic is unchanged (stamp red is dark enough — 5.65:1, per Task 1's
computed white-on-`Y` contrast — that white text/icon on it still clears AA).

- [ ] **Step 1: Write/extend the failing test**

```dart
// test/core/widgets/bottom_nav_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';

void main() {
  testWidgets('AppBottomNav has no BackdropFilter and active tab is a flat fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/bottom_nav_test.dart`
Expected: FAIL — `BackdropFilter` is still present.

- [ ] **Step 3: Apply the rewrite**

Apply the edits above to `lib/core/widgets/bottom_nav.dart`.

- [ ] **Step 4: Run test to verify it passes, plus a manual check**

Run: `flutter test test/core/widgets/bottom_nav_test.dart` — Expected: PASS.

Also run the app (`flutter run`) and visually confirm the nav pill still clears the same distance
from the bottom edge and a FAB on a detail screen (e.g. the ticket detail screen) still sits above
it without overlap — this task deliberately did not touch `AppRack.navBarHeight`/`navGap`, so this
should be unchanged, but confirm rather than assume given the surrounding widget was rewritten.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/bottom_nav.dart test/core/widgets/bottom_nav_test.dart
git commit -m "feat(widgets): AppBottomNav renders a flat sheet, stamp-red active state"
```

---

### Task 4: Remaining shared widgets — batch (mechanical, same-shape change)

**Files (all in `lib/core/widgets/` unless noted):**
`app_fab.dart`, `app_search_bar.dart`, `app_stepper.dart`, `app_tabs.dart`, `app_toast.dart`,
`app_toggle.dart`, `badge.dart`, `compartment_sheet.dart`, `empty_state.dart`, `error_state.dart`,
`list_row.dart`, `permission_purpose_sheet.dart`, `quick_action.dart`, `row_icon_tile.dart`,
`screen_header.dart`.

**Interfaces:**
- Consumes: `AppColors.Y`, `AppColors.SHEET`, `AppRack.freeShape`/`insetShape` (Task 1).
- Produces: no public API changes to any of these 15 widgets — every call site across the app
  needs zero edits.

This is one dispatch, one diff review — not 15 separate tasks — because every file needs the
identical mechanical transformation, verified line-by-line during plan-writing (exact line numbers
below, from the current repo state):

**The transformation table (apply exactly, in every file below):**

| Find | Replace with |
|---|---|
| `context.vetro.tint` | `AppColors.Y` |
| `context.vetro.tintStrong` | `AppColors.Y` (no second gradient stop — flat fill, both references collapse to the one accent) |
| `context.vetro.glassFill` | `context.colors.surface` (theme-flipping — NOT `AppColors.SHEET`, which is light-mode-only; see the correction note above Task 3) |
| `context.vetro.glassBorder` | `context.colors.borderLight` |
| `context.vetro.hairline` | `context.colors.borderLight` |
| `context.vetro.statusGood`/`statusWarn`/`statusBad` | unchanged — these are semantic status colors, not part of the Vetro material system; leave as-is (they'll be redefined in a later, separate task if DESIGN.md's status-chip treatment needs them touched — out of scope here per this plan's Task 4 boundary) |
| `AppVetroColors.blurSigma` (and any `ImageFilter.blur(...)` using it) | delete the blur entirely — remove the `BackdropFilter`/`ClipRRect` wrapper, keep only what it wrapped |
| `VetroGlass(...)` as a direct call | replace with a `DecoratedBox(decoration: BoxDecoration(color: context.colors.surface, borderRadius: <same radius the VetroGlass call used>, border: Border.all(color: context.colors.borderLight)), child: <same child>)` |
| `VetroCard(...)` as a direct call | same replacement as `VetroGlass` above (VetroCard is a thin wrapper) |
| Any `LinearGradient(colors: [context.vetro.tint, context.vetro.tintStrong])` | replace the whole `gradient:` property with `color: AppColors.Y` on the same `BoxDecoration` |
| `import '../theme/app_vetro_palette.dart';` | remove (once no `context.vetro`/`AppVetroColors`/`AppVetroPalette` reference remains in the file) |
| `import 'vetro_glass.dart';` | remove (once no `VetroGlass(` call remains) |

Per-file notes (already-verified specifics beyond the generic table, from reading each file's
actual Vetro usage during plan-writing):

- **`app_fab.dart`** (lines 42, 50): gradient fill → flat `AppColors.Y`; shadow color
  `context.vetro.tint.withAlpha(90)` → `AppColors.Y.withAlpha(90)`. FAB keeps its shadow (it's a
  genuinely floating control, per this codebase's own `AppButton` doc comment distinguishing
  floating vs. static controls — DESIGN.md doesn't ban all shadow, only static in-flow ones).
- **`app_search_bar.dart`** (line 39): direct `VetroGlass(` call → flat sheet per the table.
- **`app_stepper.dart`** (line 133), **`app_tabs.dart`** (lines 229, 250, 262), **`app_toggle.dart`**
  (line 30), **`badge.dart`** (lines 85, 87), **`compartment_sheet.dart`** (line 84),
  **`quick_action.dart`** (line 44), **`row_icon_tile.dart`** (line 51): all straightforward
  `context.vetro.tint` → `AppColors.Y` per the table, no direct `VetroGlass`/gradient calls beyond
  that.
- **`app_toast.dart`** (lines 180, 190): reads `context.vetro` for its tone-color mapping
  (`_toneStyle`) — becomes `AppColors`-based; no `VetroGlass` call in this file (the toast card
  itself doesn't blur), so only the color-source change applies, not the material change.
- **`empty_state.dart`** (lines 39-198): defines `VetroStateCard`/`VetroStateIconBadge` as
  file-local classes (not the shared `vetro_card.dart`/`vetro_glass.dart`) — these two classes
  stay in this file (do not delete them, they're not part of Task 5's Vetro-file retirement) but
  get the same material rewrite: `VetroStateCard` wraps `VetroCard` internally → change that one
  internal line to construct the flat-sheet pattern directly instead of delegating to the (soon
  to be retired, per Task 5) `VetroCard` widget. `VetroStateIconBadge`'s `tint`/`tintBg` params are
  unchanged in shape, just fed `AppColors.Y`/`AppColors.Y.withAlpha(31)` from call sites instead of
  `v.tint`/`v.tint.withAlpha(31)`.
- **`error_state.dart`** (lines 20, 49-58): same `VetroStateCard`/`VetroStateIconBadge` pattern as
  `empty_state.dart` — imports those classes from `empty_state.dart` rather than redefining them
  (confirm this via the actual import at the top of the file before assuming; if it redefines
  them, apply the same fix as `empty_state.dart` locally instead).
- **`list_row.dart`** (line 60): `context.vetro.hairline` → the table's border replacement; the
  "leading stripe" strapped-state color (mentioned in the doc comment) → `AppColors.Y`.
- **`permission_purpose_sheet.dart`** (line 81): direct `VetroCard(` call → flat sheet per the
  table.
- **`screen_header.dart`** (lines 40-212): direct `VetroGlass(` call (line 71) for a header disc,
  plus a second, separately hand-rolled `BackdropFilter` (lines 200-212, "a real frosted bar, not
  a flat tint") — both need the blur-removal treatment from the table, not just the `VetroGlass`
  line.

- [ ] **Step 1: Write one representative failing test per pattern**

```dart
// test/core/widgets/shared_widgets_no_blur_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_fab.dart';
import 'package:tasktap_mobile/core/widgets/empty_state.dart';
import 'package:tasktap_mobile/core/widgets/screen_header.dart';

void main() {
  testWidgets('AppFab has no gradient fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(floatingActionButton: AppFab(onPressed: () {}, icon: const Icon(Icons.add)))),
    );
    final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    for (final box in decoratedBoxes) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration) expect(decoration.gradient, isNull);
    }
  });

  testWidgets('EmptyState has no BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EmptyState(icon: Icons.inbox, title: 'Nothing', message: 'Empty'))),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('ScreenHeader has no BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ScreenHeader(title: 'Test'))),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
```

(Check `EmptyState`'s and `ScreenHeader`'s actual required constructor parameters before running
this — read each file's constructor signature first if the params guessed above don't match; the
point of this test is the `BackdropFilter`/gradient assertion, not these exact param names.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/widgets/shared_widgets_no_blur_test.dart`
Expected: FAIL on the `BackdropFilter` assertions (both `EmptyState`'s and `ScreenHeader`'s
`VetroGlass`/blur calls are still present).

- [ ] **Step 3: Apply the transformation to all 15 files**

Apply the table above file-by-file, using each file's noted specifics. After all 15 files are
edited, run:

```bash
grep -rn "context\.vetro\|VetroGlass(\|VetroCard(\|AppVetroColors\|AppVetroPalette" lib/core/widgets/
```

Expected: zero output (except `vetro_glass.dart`/`vetro_card.dart`/`app_vetro_palette.dart`
themselves, which Task 5 retires next — everything else in `lib/core/widgets/` should be clean).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/widgets/shared_widgets_no_blur_test.dart`
Expected: PASS.

Also run the full existing widget test suite for these 15 files (`flutter test test/core/widgets/`)
to confirm no pre-existing test broke from the material change (a test asserting on a specific
`Color`/`Gradient` value from before this task would need updating — if any fail, update their
expected values to `AppColors.Y` (brand accent, theme-invariant) or `context.colors.surface`/
`.borderLight` (theme-flipping — assert against `AppPalette.light`/`.dark`, not `AppColors.SHEET`,
mirroring Task 2's `app_card_test.dart` fix), not skip them).

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/app_fab.dart lib/core/widgets/app_search_bar.dart lib/core/widgets/app_stepper.dart lib/core/widgets/app_tabs.dart lib/core/widgets/app_toast.dart lib/core/widgets/app_toggle.dart lib/core/widgets/badge.dart lib/core/widgets/compartment_sheet.dart lib/core/widgets/empty_state.dart lib/core/widgets/error_state.dart lib/core/widgets/list_row.dart lib/core/widgets/permission_purpose_sheet.dart lib/core/widgets/quick_action.dart lib/core/widgets/row_icon_tile.dart lib/core/widgets/screen_header.dart test/core/widgets/shared_widgets_no_blur_test.dart
git commit -m "feat(widgets): remaining shared widgets render flat Documento surfaces"
```

---

### Task 5: Retire the Vetro widget/theme files entirely

**Files:**
- Delete: `lib/core/widgets/vetro_glass.dart`, `lib/core/widgets/vetro_card.dart`,
  `lib/core/widgets/vetro_button.dart`, `lib/core/widgets/vetro_compartment_tile.dart`,
  `lib/core/widgets/vetro_map_card.dart`, `lib/core/theme/app_vetro_palette.dart`
- Modify: `lib/core/theme/app_theme.dart:71` (remove the `AppVetroPalette` extension registration)

**Interfaces:**
- Consumes: confirmation from Tasks 2-4 that nothing in `lib/core/widgets/` references these
  files anymore.
- Produces: nothing — this is pure deletion. Plan 2 (the 51-screen sweep) is what actually
  removes the remaining call sites in `lib/features/`/`lib/presentation/` that still call
  `VetroButton(`/`VetroCompartmentTile(`/`VetroMapCard(` directly or read `context.vetro` — this
  task cannot run until Plan 2 does, since deleting these files now would break the build. **This
  task's steps below are written for completeness but must be executed as the LAST task of Plan 2,
  not as part of this plan** — noted here, not silently dropped, so the two plans' dependency is
  explicit rather than assumed.

- [ ] **Step 1 (deferred to Plan 2): confirm zero remaining references**

```bash
grep -rln "context\.vetro\|VetroGlass\|VetroCard\|VetroButton\|VetroCompartmentTile\|VetroMapCard\|AppVetroColors\|AppVetroPalette" lib/
```
Expected (once Plan 2 lands): zero output.

- [ ] **Step 2 (deferred to Plan 2): delete the files**

```bash
git rm lib/core/widgets/vetro_glass.dart lib/core/widgets/vetro_card.dart lib/core/widgets/vetro_button.dart lib/core/widgets/vetro_compartment_tile.dart lib/core/widgets/vetro_map_card.dart lib/core/theme/app_vetro_palette.dart
```

- [ ] **Step 3 (deferred to Plan 2): remove the theme extension registration**

In `lib/core/theme/app_theme.dart:71`, change:
```dart
    extensions: <ThemeExtension<dynamic>>[p, isDark ? AppVetroPalette.dark : AppVetroPalette.light],
```
to:
```dart
    extensions: <ThemeExtension<dynamic>>[p],
```
Remove the now-unused `import 'app_vetro_palette.dart';` at the top of the file.

- [ ] **Step 4 (deferred to Plan 2): full build + test verification**

Run: `flutter analyze && flutter test`
Expected: 0 analyzer errors, full suite green — a lingering reference to a deleted file surfaces
as a compile error here, not a runtime one.

**This plan does NOT commit Task 5** — it stops after Task 6 (below) with the Vetro files still
present but fully unreferenced by anything in `lib/core/widgets/`. Plan 2 picks up from there.

---

### Task 6: Golden test infrastructure — `alchemist`, 5 shell tabs

**Files:**
- Modify: `pubspec.yaml` (add `alchemist` dev dependency)
- Create: `test/golden/goldens_config.dart` (alchemist config — CI vs. local golden separation)
- Create: `test/golden/shell_tabs_golden_test.dart`
- Create: `test/golden/goldens/` (directory — generated golden PNGs land here)

**Interfaces:**
- Consumes: Tasks 1-4's rendered output (the actual visual target this task snapshots).
- Produces: a `flutter test --update-goldens` / `flutter test` pair of commands the rest of the
  team (and Plan 2's own tasks) can extend with more screens.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`'s `dev_dependencies:` section, add:
```yaml
  alchemist: ^0.12.1
```
Run: `flutter pub get`

- [ ] **Step 2: Write the alchemist config**

```dart
// test/golden/goldens_config.dart
import 'package:alchemist/alchemist.dart';

/// Shared alchemist config: CI renders and compares against committed goldens; local runs
/// (developer machines) render but don't fail on mismatch, since local font rendering varies by
/// OS — matches alchemist's own documented CI-vs-local split, the reason this package was chosen
/// over golden_toolkit (see this plan's spec, Testing section).
AlchemistConfig goldenConfig() {
  return AlchemistConfig(
    platformGoldensConfig: const PlatformGoldensConfig(enabled: true),
    ciGoldensConfig: const CiGoldensConfig(enabled: true),
  );
}
```

- [ ] **Step 3: Write the failing golden test**

```dart
// test/golden/shell_tabs_golden_test.dart
import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';

import 'goldens_config.dart';

void main() {
  goldenTest(
    'AppBottomNav — all 5 tabs, each as active',
    fileName: 'bottom_nav_tabs',
    config: goldenConfig(),
    builder: () => GoldenTestGroup(
      children: [
        for (var i = 0; i < AppBottomNav.defaultItems.length; i++)
          GoldenTestScenario(
            name: AppBottomNav.defaultItems[i].label,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                bottomNavigationBar: AppBottomNav(currentIndex: i, onTap: (_) {}),
                body: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Generate the golden and verify it passes**

Run: `flutter test --update-goldens test/golden/shell_tabs_golden_test.dart` (generates the
baseline PNG under `test/golden/goldens/`)
Then: `flutter test test/golden/shell_tabs_golden_test.dart`
Expected: PASS — this confirms the harness itself works end to end, on real output from Tasks 1-3
(a flat sheet, stamp-red active tab — visually inspect the generated PNG at
`test/golden/goldens/bottom_nav_tabs.png` to confirm it actually looks right, not just that the
test mechanism runs).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock test/golden/
git commit -m "test(golden): add alchemist infra, bottom-nav golden as the first coverage"
```

(Per the spec's Testing section, this task establishes the harness with one real golden; the 5
shell TABS' full-screen goldens — Dashboard/Ticket/Timbra/Calendario/Altro as complete screens,
not just the nav bar — and the "one screen per module" goldens are Plan 2 work, once those
screens are actually on the new system.)

---

## Self-review notes (per this skill's own required step)

**Spec coverage:** Task 1 covers the token-mapping table. Tasks 2-5 cover the Architecture
section's "shared widget layer" (all ~18 files enumerated in the spec's grounding). Task 6 covers
Testing's golden-infra requirement. The spec's "screens" scope (Architecture point 3, 51 files
after this plan's own re-count) is explicitly NOT this plan — Plan 2, stated as such above, not a
silently-dropped requirement.

**Placeholder scan:** Task 5's steps are marked "deferred to Plan 2" rather than left vague or
silently included as if executable now — this is a real, load-bearing sequencing constraint
(deleting the Vetro files before their remaining call sites are gone breaks the build), not a
placeholder. Every other task has complete, concrete code.

**Type consistency:** `AppColors.SHEET` (Task 1) is a real token, but Tasks 2-4's widget code reads
it through the theme-flipping `context.colors.surface`/`.borderLight` (`AppPalette`, Task 1b), not
`AppColors.SHEET` directly — corrected globally post-Task-2 (see the note above Task 3); `SHEET`
itself is only read directly by Task 1's own contrast tests, which are theme-invariant by design.
`AppRack.freeShape`/`insetShape` (pre-existing, unchanged names, new radius value from Task 1) are
used consistently in Task 2's `AppCard` rewrite. `AppColors.Y` (existing name, new value) is used
consistently as "the one accent" across Tasks 2-4, matching the spec's token-mapping table.
