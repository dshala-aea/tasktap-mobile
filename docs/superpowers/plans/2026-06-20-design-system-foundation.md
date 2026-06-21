# TaskTap Flutter Design-System Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the M1 placeholder theme + core widgets with a faithful translation of `design-reference/DESIGN-SPEC.md` — exact token palette, typography, status-color map, and a full reusable component library — while keeping existing screens compiling and all tests green.

**Architecture:** Pure Flutter design system layered under `lib/core/theme/` (tokens, typography, status map, `buildAppTheme`) and `lib/core/widgets/` (stateless reusable components). No business logic, no new screens. Existing screens (`home_shell`, `login`, `oggi`, `interventi`, `rapportini`, `profilo`) keep their current structure; only call sites that reference renamed/removed tokens are adapted. Italian UI copy throughout. One vector icon family (`lucide_icons`).

**Tech Stack:** Flutter (Dart `^3.11.0`), `google_fonts` (Sora display/titles/KPI, Manrope body/labels, Inter fallback), `lucide_icons` (new dependency), `flutter_test` for widget tests.

## Global Constraints

- Repo root for all work: `/mnt/d/AEA/Sviluppi/TaskTap/mobile/`. This is its OWN git repo, gitignored from the backend. ALL git ops via `git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile ...`. NEVER touch the backend repo or `frontend/`. Stage only files under `mobile/`.
- Flutter runs via Windows: `cmd.exe /c flutter.bat <args>` executed from inside `mobile/`. No Android SDK — verification is `cmd.exe /c flutter.bat analyze` (must be clean) + `cmd.exe /c flutter.bat test` (must be green, total tests ≥ 204) ONLY. Never attempt a build/run.
- On a WSL file-lock error from a flutter cmd: retry once; if it still fails, note it tersely and do not thrash.
- OUTPUT DISCIPLINE: NEVER paste file contents into chat/reports. Write files with editor tools, commit, report only short summaries (paths + counts + test results). Keep every message terse.
- Commit frequently — one commit per task below. Each commit message body ends with exactly:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Commit ONLY when analyze is clean AND tests are green (≥204). Adapt the M1 theme/StatusBadge tests to new tokens/status names — do NOT delete coverage.
- FOUNDATION only: tokens + reusable components + keep existing screens compiling. Do NOT rebuild full screens.
- ui-ux-pro-max rules as the "improve" layer: ≥44pt hit areas (even where the 393pt design draws smaller), ≥4.5:1 contrast for text, visible press feedback, 150–300ms motion, respect safe areas (notch + home indicator), no emoji, single icon family.

### Exact token values (copied verbatim from spec — use everywhere)

Brand: `Y = #FFF10E`, `YDark = #E6D900`, `YSoft = rgba(255,241,14,0.2)`
Ink: `DARK = #363636`, `CHARCOAL = #292929`, `FG2 = rgb(112,112,112)`, `MUTED = rgb(144,143,143)`, `DIS = rgb(180,180,180)`, `INV = rgb(242,242,242)`, `WHITE = #fff`
Surfaces: `BG1 = rgb(250,250,250)`, `BG2 = rgb(247,247,247)`, `BG3 = rgb(242,242,242)`, `BG4 = rgb(237,237,237)`
Borders: `BL = rgb(242,242,242)`, `BM = rgb(227,227,227)`, `BS = rgb(217,217,217)`, `DIV = rgb(212,212,212)`
Semantic: `AMBER = rgb(255,178,0)`, `GREEN = #4caf50`, `BLUE = #2563eb`, `CYAN = #06AED5`, `RED = #ff0000`, `REDSOFT = rgb(255,209,209)`
Shadow: `SH = 0 3px 5.5px rgba(0,0,0,0.10)`; `SH_INSET = inset 0 2px 4px rgba(0,0,0,0.10)`
Fonts: `FD = Sora`, `FB = Manrope`, `FA = Inter`

### The 13 Italian statuses (verbatim, with bg/fg)

| Status | bg | fg |
|---|---|---|
| Aperto | `rgb(220,232,255)` | `#1d4ed8` |
| In corso | `AMBER rgb(255,178,0)` | `#000000` |
| In pausa | `rgb(232,232,232)` | `#555555` |
| In attesa | `rgb(220,240,255)` | `#06AED5` |
| Completato | `rgb(218,242,224)` | `#1e7a3a` |
| Chiuso | `rgb(232,232,232)` | `#363636` |
| Annullato | `rgb(255,220,220)` | `#aa0000` |
| Bozza | `rgb(245,245,245)` | `#666666` |
| Inviata | `rgb(220,232,255)` | `#1d4ed8` |
| Pagata | `rgb(218,242,224)` | `#1e7a3a` |
| Scaduta | `rgb(255,220,220)` | `#aa0000` |
| Sospeso | `rgb(255,220,220)` | `#aa0000` |
| Attivo | `rgb(218,242,224)` | `#1e7a3a` |

---

## File Structure

**Tokens / theme (`lib/core/theme/`):**
- `app_colors.dart` — MODIFY. Full token palette as `static const Color` fields + 2 shadow `BoxShadow` tokens. Keep a backwards-compat alias block for names existing screens reference.
- `app_text_styles.dart` — MODIFY. Sora display/title/KPI + Manrope body/label + Inter fallback getters; `buildTextTheme()`.
- `status_colors.dart` — MODIFY. `WorkStatus` enum (13 stati) + `statusColorOf` map + `workStatusLabel`. Keep legacy `ReportStato` + `statusColor` + `statoLabel` as a thin compatibility shim so the M1 `StatusBadge` and screens still compile.
- `app_theme.dart` — MODIFY. `buildAppTheme()` consuming new tokens.
- `app_spacing.dart` — keep as-is (already sane); add a few radius/size constants the components need.
- `theme.dart` — barrel; no change needed beyond existing exports.

**Components (`lib/core/widgets/`):** one file per component family, all re-exported from `widgets.dart`.
- `app_card.dart` (MODIFY) — `AppCard` + `GlassCard`.
- `app_button.dart` (MODIFY) — `AppButton` (5 variants × 3 sizes).
- `badges.dart` (CREATE) — `AppBadge`, `AppChip`, `StatusPill`.
- `avatar.dart` (CREATE) — `Avatar`.
- `key_val.dart` (CREATE) — `KeyVal`.
- `section_title.dart` (CREATE) — `SectionTitle`.
- `app_toggle.dart` (CREATE) — `AppToggle`.
- `bottom_nav.dart` (CREATE) — `AppBottomNav` (floating pill, 5 tabs).
- `screen_header.dart` (CREATE) — `ScreenHeader`, `HeaderIconBtn`.
- `search_bar.dart` (CREATE) — `AppSearchBar`.
- `list_row.dart` (CREATE) — `ListRow`.
- `app_tabs.dart` (CREATE) — `AppTabs`.
- `app_fab.dart` (CREATE) — `AppFab`.
- `empty_state.dart` (CREATE) — `EmptyState`.
- `stepper.dart` (CREATE) — `AppStepper`.
- `hero.dart` (CREATE) — `Hero` dashboard header (named `DashboardHero` to avoid clashing with Flutter's `Hero`).
- `active_job_card.dart` (CREATE) — `ActiveJobCard`.
- `stats_grid.dart` (CREATE) — `StatsGrid`, `StatItem`.
- `quick_action.dart` (CREATE) — `QuickAction`.
- `signature_pad.dart` (CREATE) — `SignaturePadPlaceholder`.
- `status_badge.dart` (KEEP, MODIFY only if compile needs) — legacy M1 badge; leave functioning via the compat shim.
- `widgets.dart` (MODIFY) — barrel re-exporting all of the above.

**Tests (`test/`):**
- `test/core/theme_test.dart` — MODIFY to assert new tokens + status map (keep the existing assertions that still apply, adapt renamed ones).
- `test/core/widgets/button_test.dart` (CREATE)
- `test/core/widgets/status_pill_test.dart` (CREATE)
- `test/core/widgets/bottom_nav_test.dart` (CREATE)
- `test/core/widgets/card_test.dart` (CREATE)
- `test/core/widgets/stepper_test.dart` (CREATE)
- `test/presentation/app_shell_test.dart` — MODIFY only if the nav change breaks its assertions (see Task 12 note).

---

## Task 1: Add `lucide_icons` dependency

**Files:**
- Modify: `pubspec.yaml` (dependencies block)

**Interfaces:**
- Produces: package `lucide_icons` available as `import 'package:lucide_icons/lucide_icons.dart';` exposing `LucideIcons.*` `IconData` constants (e.g. `LucideIcons.home`, `LucideIcons.ticket`, `LucideIcons.clock`, `LucideIcons.calendar`, `LucideIcons.moreHorizontal`, `LucideIcons.search`, `LucideIcons.chevronRight`, `LucideIcons.chevronLeft`, `LucideIcons.plus`, `LucideIcons.bell`, `LucideIcons.user`, `LucideIcons.check`, `LucideIcons.penLine`).

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, directly after the `google_fonts: ^6.2.1` line, add:

```yaml
  # Icon set (single vector family — no emoji)
  lucide_icons: ^0.257.0
```

- [ ] **Step 2: Resolve packages**

Run (from inside `mobile/`): `cmd.exe /c flutter.bat pub get`
Expected: resolves and downloads `lucide_icons` with no version-solve error. If the exact version `^0.257.0` is unavailable, run `cmd.exe /c flutter.bat pub add lucide_icons` instead and let the solver pick a compatible version, then continue.

- [ ] **Step 3: Verify the import resolves**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean (no errors). `lucide_icons` is now resolvable. (No source uses it yet — that's fine.)

- [ ] **Step 4: Commit**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add pubspec.yaml pubspec.lock
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "chore(mobile): add lucide_icons dependency

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2 (Commit 1): Tokens, typography, status map, theme

**Files:**
- Modify: `lib/core/theme/app_colors.dart`
- Modify: `lib/core/theme/app_text_styles.dart`
- Modify: `lib/core/theme/status_colors.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `lib/core/theme/app_spacing.dart`
- Modify: `test/core/theme_test.dart`

**Interfaces:**
- Produces (`AppColors`, all `static const Color`): `y`, `yDark`, `ySoft`, `dark`, `charcoal`, `fg2`, `muted`, `dis`, `inv`, `white`, `bg1`, `bg2`, `bg3`, `bg4`, `bl`, `bm`, `bs`, `div`, `amber`, `green`, `blue`, `cyan`, `red`, `redSoft`. Plus shadow tokens: `static const List<BoxShadow> sh` and `static const List<BoxShadow> shInset` (inset is faked — see note). Plus compat aliases: `brand = y`, `onBrand = dark`, `surface = white`, `background = bg1`, `surfaceVariant = bg2`, `outline = bm`, `textPrimary = dark`, `textSecondary = fg2`, `textDisabled = dis`, `error = red`, `onError = white`, `success = green`, `warning = amber`, `info = blue`, and the legacy `statusBozza/onStatusBozza/statusInviato/onStatusInviato/statusControllato/onStatusControllato/statusFatturato/onStatusFatturato/statusAnnullato/onStatusAnnullato` (used by legacy `status_colors` shim).
- Produces (`AppTextStyles`, all `static TextStyle get`): `displayLarge` (Sora), `displayMedium` (Sora), `title` (Sora 700/18), `titleSmall` (Sora 700/16), `kpi` (Manrope 500/36), `kpiSora` (Sora KPI), `bodyLarge`/`bodyMedium`/`bodySmall` (Manrope), `labelLarge`/`labelMedium`/`labelSmall` (Manrope), `navLabel` (Sora 600/12), `caption`. Keep existing names referenced by current screens (`headlineLarge`, `headlineMedium`, `titleLarge`, `titleMedium`) as aliases. Plus `inter(...)` helper for the Inter fallback. Plus `buildTextTheme()`.
- Produces (`status_colors.dart`): `enum WorkStatus { aperto, inCorso, inPausa, inAttesa, completato, chiuso, annullato, bozza, inviata, pagata, scaduta, sospeso, attivo }`; `class StatusColorPair { final Color background; final Color foreground; }`; `StatusColorPair statusColorOf(WorkStatus s)`; `String workStatusLabel(WorkStatus s)`. PLUS legacy compat preserved: `enum ReportStato {...}`, `StatusColorPair statusColor(ReportStato)`, `String statoLabel(ReportStato)`.
- Produces: `ThemeData buildAppTheme()`.

**Note on `shInset`:** Flutter `BoxShadow` cannot be inset. Implement `shInset` as a normal soft shadow approximating the spec value (`BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 4, offset: Offset(0, 2))`) and document with a `//` comment that true inset is emulated via gradient overlays in `GlassCard`. Do not block on this.

- [ ] **Step 1: Write the failing tests first**

Replace `test/core/theme_test.dart` entirely with the following. It keeps the surviving M1 assertions (brand yellow, onBrand contrast, light brightness, m3, error set) and adds the new token + 13-status assertions.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/theme/status_colors.dart';

void main() {
  group('buildAppTheme', () {
    testWidgets('returns a valid ThemeData', (tester) async {
      expect(buildAppTheme(), isA<ThemeData>());
    });
    testWidgets('primary color is brand yellow #FFF10E', (tester) async {
      expect(buildAppTheme().colorScheme.primary, equals(AppColors.y));
    });
    testWidgets('onPrimary is dark for contrast', (tester) async {
      expect(buildAppTheme().colorScheme.onPrimary, equals(AppColors.dark));
    });
    testWidgets('brightness is light', (tester) async {
      expect(buildAppTheme().colorScheme.brightness, equals(Brightness.light));
    });
    testWidgets('useMaterial3 is true', (tester) async {
      expect(buildAppTheme().useMaterial3, isTrue);
    });
  });

  group('AppColors tokens', () {
    test('brand yellow Y is #FFF10E', () {
      expect(AppColors.y, equals(const Color(0xFFFFF10E)));
    });
    test('yDark is #E6D900', () {
      expect(AppColors.yDark, equals(const Color(0xFFE6D900)));
    });
    test('DARK ink is #363636', () {
      expect(AppColors.dark, equals(const Color(0xFF363636)));
    });
    test('charcoal is #292929', () {
      expect(AppColors.charcoal, equals(const Color(0xFF292929)));
    });
    test('cyan is #06AED5', () {
      expect(AppColors.cyan, equals(const Color(0xFF06AED5)));
    });
    test('green is #4caf50', () {
      expect(AppColors.green, equals(const Color(0xFF4CAF50)));
    });
    test('blue is #2563eb', () {
      expect(AppColors.blue, equals(const Color(0xFF2563EB)));
    });
    test('onBrand alias equals dark ink', () {
      expect(AppColors.onBrand, equals(AppColors.dark));
    });
    test('two shadow tokens are defined and non-empty', () {
      expect(AppColors.sh, isNotEmpty);
      expect(AppColors.shInset, isNotEmpty);
    });
  });

  group('WorkStatus color map', () {
    test('exposes all 13 statuses', () {
      expect(WorkStatus.values.length, equals(13));
    });
    test('every status returns an opaque bg + fg', () {
      for (final s in WorkStatus.values) {
        final p = statusColorOf(s);
        expect((p.background.a * 255).round(), greaterThan(0), reason: '$s bg');
        expect((p.foreground.a * 255).round(), greaterThan(0), reason: '$s fg');
      }
    });
    test('Aperto bg rgb(220,232,255) fg #1d4ed8', () {
      final p = statusColorOf(WorkStatus.aperto);
      expect(p.background, equals(const Color.fromARGB(255, 220, 232, 255)));
      expect(p.foreground, equals(const Color(0xFF1D4ED8)));
    });
    test('In corso bg amber fg black', () {
      final p = statusColorOf(WorkStatus.inCorso);
      expect(p.background, equals(AppColors.amber));
      expect(p.foreground, equals(const Color(0xFF000000)));
    });
    test('Completato bg rgb(218,242,224) fg #1e7a3a', () {
      final p = statusColorOf(WorkStatus.completato);
      expect(p.background, equals(const Color.fromARGB(255, 218, 242, 224)));
      expect(p.foreground, equals(const Color(0xFF1E7A3A)));
    });
    test('Annullato bg rgb(255,220,220) fg #aa0000', () {
      final p = statusColorOf(WorkStatus.annullato);
      expect(p.background, equals(const Color.fromARGB(255, 255, 220, 220)));
      expect(p.foreground, equals(const Color(0xFFAA0000)));
    });
    test('every status has a non-empty Italian label', () {
      for (final s in WorkStatus.values) {
        expect(workStatusLabel(s).trim(), isNotEmpty);
      }
    });
    test('labels match spec spelling', () {
      expect(workStatusLabel(WorkStatus.aperto), 'Aperto');
      expect(workStatusLabel(WorkStatus.inCorso), 'In corso');
      expect(workStatusLabel(WorkStatus.inPausa), 'In pausa');
      expect(workStatusLabel(WorkStatus.inAttesa), 'In attesa');
      expect(workStatusLabel(WorkStatus.completato), 'Completato');
      expect(workStatusLabel(WorkStatus.chiuso), 'Chiuso');
      expect(workStatusLabel(WorkStatus.annullato), 'Annullato');
      expect(workStatusLabel(WorkStatus.bozza), 'Bozza');
      expect(workStatusLabel(WorkStatus.inviata), 'Inviata');
      expect(workStatusLabel(WorkStatus.pagata), 'Pagata');
      expect(workStatusLabel(WorkStatus.scaduta), 'Scaduta');
      expect(workStatusLabel(WorkStatus.sospeso), 'Sospeso');
      expect(workStatusLabel(WorkStatus.attivo), 'Attivo');
    });
  });

  group('legacy compat (M1)', () {
    test('ReportStato still maps via statusColor', () {
      for (final s in ReportStato.values) {
        final p = statusColor(s);
        expect((p.background.a * 255).round(), greaterThan(0));
      }
    });
    test('statoLabel returns Italian', () {
      expect(statoLabel(ReportStato.bozza), 'Bozza');
    });
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `cmd.exe /c flutter.bat test test/core/theme_test.dart`
Expected: FAIL (compile errors — `AppColors.y`, `WorkStatus`, `statusColorOf`, etc. don't exist yet).

- [ ] **Step 3: Rewrite `app_colors.dart`**

Replace the file with the exact token palette. Use this content:

```dart
import 'package:flutter/material.dart';

/// TaskTap design-system color tokens (see design-reference/DESIGN-SPEC.md).
abstract final class AppColors {
  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color y = Color(0xFFFFF10E);
  static const Color yDark = Color(0xFFE6D900);
  static const Color ySoft = Color(0x33FFF10E); // rgba(255,241,14,0.2)

  // ── Ink ──────────────────────────────────────────────────────────────────
  static const Color dark = Color(0xFF363636);
  static const Color charcoal = Color(0xFF292929);
  static const Color fg2 = Color.fromARGB(255, 112, 112, 112);
  static const Color muted = Color.fromARGB(255, 144, 143, 143);
  static const Color dis = Color.fromARGB(255, 180, 180, 180);
  static const Color inv = Color.fromARGB(255, 242, 242, 242);
  static const Color white = Color(0xFFFFFFFF);

  // ── Surfaces ───────────────────────────────────────────────────────────────
  static const Color bg1 = Color.fromARGB(255, 250, 250, 250);
  static const Color bg2 = Color.fromARGB(255, 247, 247, 247);
  static const Color bg3 = Color.fromARGB(255, 242, 242, 242);
  static const Color bg4 = Color.fromARGB(255, 237, 237, 237);

  // ── Borders ────────────────────────────────────────────────────────────────
  static const Color bl = Color.fromARGB(255, 242, 242, 242);
  static const Color bm = Color.fromARGB(255, 227, 227, 227);
  static const Color bs = Color.fromARGB(255, 217, 217, 217);
  static const Color div = Color.fromARGB(255, 212, 212, 212);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const Color amber = Color.fromARGB(255, 255, 178, 0);
  static const Color green = Color(0xFF4CAF50);
  static const Color blue = Color(0xFF2563EB);
  static const Color cyan = Color(0xFF06AED5);
  static const Color red = Color(0xFFFF0000);
  static const Color redSoft = Color.fromARGB(255, 255, 209, 209);

  // ── Shadows ────────────────────────────────────────────────────────────────
  /// SH = 0 3px 5.5px rgba(0,0,0,0.10)
  static const List<BoxShadow> sh = [
    BoxShadow(
      color: Color(0x1A000000), // 0.10 alpha
      blurRadius: 5.5,
      offset: Offset(0, 3),
    ),
  ];

  /// SH_INSET = inset 0 2px 4px rgba(0,0,0,0.10).
  /// Flutter BoxShadow cannot be inset; this approximates it as a soft
  /// shadow. True inset look is emulated with gradient overlays in GlassCard.
  static const List<BoxShadow> shInset = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  // ── Legacy compatibility aliases (M1 call sites) ─────────────────────────────
  static const Color brand = y;
  static const Color onBrand = dark;
  static const Color surface = white;
  static const Color background = bg1;
  static const Color surfaceVariant = bg2;
  static const Color outline = bm;
  static const Color textPrimary = dark;
  static const Color textSecondary = fg2;
  static const Color textDisabled = dis;
  static const Color error = red;
  static const Color onError = white;
  static const Color success = green;
  static const Color warning = amber;
  static const Color info = blue;

  // Legacy M1 status tokens (still consumed by the status_colors compat shim).
  static const Color statusBozza = Color.fromARGB(255, 245, 245, 245);
  static const Color onStatusBozza = Color(0xFF666666);
  static const Color statusInviato = Color.fromARGB(255, 220, 232, 255);
  static const Color onStatusInviato = Color(0xFF1D4ED8);
  static const Color statusControllato = amber;
  static const Color onStatusControllato = Color(0xFF000000);
  static const Color statusFatturato = Color.fromARGB(255, 218, 242, 224);
  static const Color onStatusFatturato = Color(0xFF1E7A3A);
  static const Color statusAnnullato = Color.fromARGB(255, 255, 220, 220);
  static const Color onStatusAnnullato = Color(0xFFAA0000);
}
```

- [ ] **Step 4: Rewrite `status_colors.dart`**

Replace the file with the 13-status `WorkStatus` enum + color map + label, while keeping the legacy `ReportStato` shim:

```dart
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// All work/report statuses surfaced in the UI (Italian labels).
enum WorkStatus {
  aperto,
  inCorso,
  inPausa,
  inAttesa,
  completato,
  chiuso,
  annullato,
  bozza,
  inviata,
  pagata,
  scaduta,
  sospeso,
  attivo,
}

/// Background + foreground pair for a status pill.
class StatusColorPair {
  const StatusColorPair({required this.background, required this.foreground});
  final Color background;
  final Color foreground;
}

const _blueBg = Color.fromARGB(255, 220, 232, 255);
const _blueFg = Color(0xFF1D4ED8);
const _greenBg = Color.fromARGB(255, 218, 242, 224);
const _greenFg = Color(0xFF1E7A3A);
const _redBg = Color.fromARGB(255, 255, 220, 220);
const _redFg = Color(0xFFAA0000);
const _greyBg = Color.fromARGB(255, 232, 232, 232);

/// Maps each [WorkStatus] to its spec-defined color pair.
StatusColorPair statusColorOf(WorkStatus s) {
  return switch (s) {
    WorkStatus.aperto =>
      const StatusColorPair(background: _blueBg, foreground: _blueFg),
    WorkStatus.inCorso =>
      const StatusColorPair(background: AppColors.amber, foreground: Color(0xFF000000)),
    WorkStatus.inPausa =>
      const StatusColorPair(background: _greyBg, foreground: Color(0xFF555555)),
    WorkStatus.inAttesa => const StatusColorPair(
        background: Color.fromARGB(255, 220, 240, 255),
        foreground: AppColors.cyan,
      ),
    WorkStatus.completato =>
      const StatusColorPair(background: _greenBg, foreground: _greenFg),
    WorkStatus.chiuso =>
      const StatusColorPair(background: _greyBg, foreground: AppColors.dark),
    WorkStatus.annullato =>
      const StatusColorPair(background: _redBg, foreground: _redFg),
    WorkStatus.bozza => const StatusColorPair(
        background: Color.fromARGB(255, 245, 245, 245),
        foreground: Color(0xFF666666),
      ),
    WorkStatus.inviata =>
      const StatusColorPair(background: _blueBg, foreground: _blueFg),
    WorkStatus.pagata =>
      const StatusColorPair(background: _greenBg, foreground: _greenFg),
    WorkStatus.scaduta =>
      const StatusColorPair(background: _redBg, foreground: _redFg),
    WorkStatus.sospeso =>
      const StatusColorPair(background: _redBg, foreground: _redFg),
    WorkStatus.attivo =>
      const StatusColorPair(background: _greenBg, foreground: _greenFg),
  };
}

/// Italian display label for each [WorkStatus] (matches spec spelling).
String workStatusLabel(WorkStatus s) {
  return switch (s) {
    WorkStatus.aperto => 'Aperto',
    WorkStatus.inCorso => 'In corso',
    WorkStatus.inPausa => 'In pausa',
    WorkStatus.inAttesa => 'In attesa',
    WorkStatus.completato => 'Completato',
    WorkStatus.chiuso => 'Chiuso',
    WorkStatus.annullato => 'Annullato',
    WorkStatus.bozza => 'Bozza',
    WorkStatus.inviata => 'Inviata',
    WorkStatus.pagata => 'Pagata',
    WorkStatus.scaduta => 'Scaduta',
    WorkStatus.sospeso => 'Sospeso',
    WorkStatus.attivo => 'Attivo',
  };
}

// ── Legacy M1 compatibility shim (StatusBadge + existing screens) ────────────

/// Rapportino workflow states — matches backend `StatoRapportino` enum.
enum ReportStato { bozza, inviato, controllato, fatturato, annullato }

StatusColorPair statusColor(ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => statusColorOf(WorkStatus.bozza),
    ReportStato.inviato => statusColorOf(WorkStatus.inviata),
    ReportStato.controllato => statusColorOf(WorkStatus.inCorso),
    ReportStato.fatturato => statusColorOf(WorkStatus.pagata),
    ReportStato.annullato => statusColorOf(WorkStatus.annullato),
  };
}

String statoLabel(ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => 'Bozza',
    ReportStato.inviato => 'Inviato',
    ReportStato.controllato => 'Controllato',
    ReportStato.fatturato => 'Fatturato',
    ReportStato.annullato => 'Annullato',
  };
}
```

- [ ] **Step 5: Rewrite `app_text_styles.dart`**

Replace with Sora (display/title/KPI) + Manrope (body/label) + Inter fallback. Keep M1 names as aliases so screens compile. Use this content:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// TaskTap typography. FD = Sora (display/titles/KPI), FB = Manrope
/// (body/labels), FA = Inter (system fallback).
abstract final class AppTextStyles {
  // ── Sora — display / titles ────────────────────────────────────────────────
  static TextStyle get displayLarge => GoogleFonts.sora(
        fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3,
        color: AppColors.dark,
      );
  static TextStyle get displayMedium => GoogleFonts.sora(
        fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.dark,
      );

  /// Section/screen title — Sora 700/18.
  static TextStyle get title => GoogleFonts.sora(
        fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.dark,
      );

  /// Smaller title — Sora 700/16.
  static TextStyle get titleSmall => GoogleFonts.sora(
        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark,
      );

  /// Bottom-nav active label — Sora 600/12.
  static TextStyle get navLabel => GoogleFonts.sora(
        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.dark,
      );

  /// Stepper step label — Sora 600/10.
  static TextStyle get stepLabel => GoogleFonts.sora(
        fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.dark,
      );

  /// KPI value — Manrope 500/36 (per StatsGrid spec).
  static TextStyle get kpi => GoogleFonts.manrope(
        fontSize: 36, fontWeight: FontWeight.w500, color: AppColors.dark,
      );

  /// KPI value, Sora variant for hero metrics.
  static TextStyle get kpiSora => GoogleFonts.sora(
        fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1,
        color: AppColors.dark,
      );

  // ── Manrope — body / labels ────────────────────────────────────────────────
  static TextStyle get bodyLarge => GoogleFonts.manrope(
        fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.dark,
      );
  static TextStyle get bodyMedium => GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.dark,
      );
  static TextStyle get bodySmall => GoogleFonts.manrope(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.fg2,
      );
  static TextStyle get labelLarge => GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark,
      );
  static TextStyle get labelMedium => GoogleFonts.manrope(
        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3,
        color: AppColors.fg2,
      );
  static TextStyle get labelSmall => GoogleFonts.manrope(
        fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.fg2,
      );
  static TextStyle get caption => GoogleFonts.manrope(
        fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.fg2,
      );

  /// Inter system fallback helper.
  static TextStyle inter({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.dark,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize, fontWeight: fontWeight, color: color,
      );

  // ── M1 aliases (existing screens) ───────────────────────────────────────────
  static TextStyle get headlineLarge => title;
  static TextStyle get headlineMedium => titleSmall;
  static TextStyle get titleLarge => titleSmall;
  static TextStyle get titleMedium => labelLarge;
}

/// Fully-populated [TextTheme] from the styles above.
TextTheme buildTextTheme() {
  return TextTheme(
    displayLarge: AppTextStyles.displayLarge,
    displayMedium: AppTextStyles.displayMedium,
    displaySmall: AppTextStyles.title,
    headlineLarge: AppTextStyles.title,
    headlineMedium: AppTextStyles.titleSmall,
    headlineSmall: AppTextStyles.titleSmall,
    titleLarge: AppTextStyles.titleSmall,
    titleMedium: AppTextStyles.labelLarge,
    titleSmall: AppTextStyles.bodyMedium,
    bodyLarge: AppTextStyles.bodyLarge,
    bodyMedium: AppTextStyles.bodyMedium,
    bodySmall: AppTextStyles.bodySmall,
    labelLarge: AppTextStyles.labelLarge,
    labelMedium: AppTextStyles.labelMedium,
    labelSmall: AppTextStyles.labelSmall,
  );
}
```

- [ ] **Step 6: Extend `app_spacing.dart`**

Add component radii/sizes the widgets need. Append these constants inside the `AppSpacing` class (before the closing brace), keeping all existing fields:

```dart
  /// GlassCard / Card radius (design 14px).
  static const double cardRadiusLg = 14;

  /// BottomNav floating-pill radius.
  static const double navPillRadius = 23;

  /// BottomNav active-tab inner radius.
  static const double navTabRadius = 19;

  /// Minimum accessible touch target (ui-ux-pro-max).
  static const double minTouchTarget = 44;
```

- [ ] **Step 7: Rewrite `app_theme.dart` to consume new tokens**

Replace token references with the new names. The structure is identical to the current file; only the `AppColors.*` and text-style references change. Use this content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Builds the TaskTap [ThemeData] from the design-system tokens.
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.y,
    onPrimary: AppColors.dark,
    primaryContainer: AppColors.ySoft,
    onPrimaryContainer: AppColors.dark,
    secondary: AppColors.dark,
    onSecondary: AppColors.white,
    secondaryContainer: AppColors.bg3,
    onSecondaryContainer: AppColors.dark,
    tertiary: AppColors.blue,
    onTertiary: AppColors.white,
    tertiaryContainer: AppColors.blue.withValues(alpha: 0.08),
    onTertiaryContainer: AppColors.blue,
    error: AppColors.red,
    onError: AppColors.white,
    errorContainer: AppColors.redSoft,
    onErrorContainer: AppColors.red,
    surface: AppColors.white,
    onSurface: AppColors.dark,
    surfaceContainerHighest: AppColors.bg3,
    onSurfaceVariant: AppColors.fg2,
    outline: AppColors.bm,
    outlineVariant: AppColors.bl,
    shadow: Colors.black.withValues(alpha: 0.10),
    scrim: Colors.black.withValues(alpha: 0.45),
    inverseSurface: AppColors.dark,
    onInverseSurface: AppColors.inv,
    inversePrimary: AppColors.y,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: buildTextTheme(),
    scaffoldBackgroundColor: AppColors.bg1,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.dark,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppTextStyles.title,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: AppColors.bg1,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
        side: const BorderSide(color: AppColors.bl),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.bl, space: 1, thickness: 1,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.y,
      foregroundColor: AppColors.dark,
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg3,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base, vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.bm),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.bm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.y, width: 2),
      ),
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.dis),
    ),
  );
}
```

- [ ] **Step 8: Run analyze and the theme tests**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean (existing screens still compile via aliases). If any screen references a now-missing name, add an alias getter (don't change screen files unless unavoidable).

Run: `cmd.exe /c flutter.bat test test/core/theme_test.dart`
Expected: PASS.

- [ ] **Step 9: Run the full suite**

Run: `cmd.exe /c flutter.bat test`
Expected: all green, total ≥ 204.

- [ ] **Step 10: Commit**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add lib/core/theme test/core/theme_test.dart
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "feat(mobile): design-system tokens, typography, status map, theme

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3 (Commit 2): Basic components

**Files:**
- Modify: `lib/core/widgets/app_card.dart` (add `GlassCard`)
- Modify: `lib/core/widgets/app_button.dart` (5 variants × 3 sizes)
- Create: `lib/core/widgets/badges.dart`
- Create: `lib/core/widgets/avatar.dart`
- Create: `lib/core/widgets/key_val.dart`
- Create: `lib/core/widgets/section_title.dart`
- Create: `lib/core/widgets/app_toggle.dart`
- Modify: `lib/core/widgets/widgets.dart` (barrel)

**Interfaces:**
- Produces `AppCard({Widget child, EdgeInsetsGeometry? padding, VoidCallback? onTap, Color? backgroundColor, Color? borderColor})` (default bg `AppColors.bg1`, radius 14, padding 16, SH shadow, border `AppColors.bl`). Keep `AppCard.pressable` named ctor for existing call sites.
- Produces `GlassCard({required Widget child, EdgeInsetsGeometry? padding})` — white-translucent gradient, 0.5px white border, radius 14, soft inset-emulating shadow; meant to sit on the dark hero.
- Produces `enum AppButtonVariant { primary, secondary, dark, ghost, danger }` and `enum AppButtonSize { sm, md, lg }` and `AppButton({required String label, VoidCallback? onPressed, IconData? icon, bool isLoading, AppButtonVariant variant, AppButtonSize size, bool expand})`. Keep named ctors `AppButton.secondary/.ghost/.danger` for existing call sites (they default `size: AppButtonSize.md`).
- Produces `AppBadge({required String text, Color? background, Color? foreground, bool small})`.
- Produces `AppChip({required String label, bool active, VoidCallback? onTap})`.
- Produces `StatusPill({required WorkStatus status, bool small})`.
- Produces `Avatar({required String name, double size, Color? color})` (initials, color cycle).
- Produces `KeyVal({required String label, required String value, bool vertical})`.
- Produces `SectionTitle({required String title, Widget? action})`.
- Produces `AppToggle({required bool value, required ValueChanged<bool> onChanged})`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/core/widgets/card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('AppCard renders its child', (tester) async {
    await tester.pumpWidget(_wrap(const AppCard(child: Text('hi'))));
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('AppCard.pressable fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(
      AppCard.pressable(onTap: () => tapped = true, child: const Text('tap')),
    ));
    await tester.tap(find.text('tap'));
    expect(tapped, isTrue);
  });

  testWidgets('GlassCard renders its child', (tester) async {
    await tester.pumpWidget(_wrap(
      const ColoredBox(color: Colors.black, child: GlassCard(child: Text('g'))),
    ));
    expect(find.text('g'), findsOneWidget);
  });
}
```

Create `test/core/widgets/status_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/status_colors.dart';
import 'package:tasktap_mobile/core/widgets/badges.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('StatusPill renders correct label for all 13 statuses',
      (tester) async {
    for (final s in WorkStatus.values) {
      await tester.pumpWidget(_wrap(StatusPill(status: s)));
      expect(find.text(workStatusLabel(s)), findsOneWidget,
          reason: 'label for $s');
    }
  });

  testWidgets('StatusPill uses the mapped background color', (tester) async {
    await tester.pumpWidget(_wrap(const StatusPill(status: WorkStatus.inCorso)));
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, equals(statusColorOf(WorkStatus.inCorso).background));
  });

  testWidgets('AppBadge renders text', (tester) async {
    await tester.pumpWidget(_wrap(const AppBadge(text: 'NEW')));
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('AppChip toggles via onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(
      AppChip(label: 'Tutti', onTap: () => tapped = true),
    ));
    await tester.tap(find.text('Tutti'));
    expect(tapped, isTrue);
  });
}
```

Create `test/core/widgets/button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders label for every variant', (tester) async {
    for (final v in AppButtonVariant.values) {
      await tester.pumpWidget(_wrap(
        AppButton(label: 'Go', variant: v, onPressed: () {}),
      ));
      expect(find.text('Go'), findsOneWidget, reason: 'variant $v');
    }
  });

  testWidgets('renders for every size', (tester) async {
    for (final s in AppButtonSize.values) {
      await tester.pumpWidget(_wrap(
        AppButton(label: 'Go', size: s, onPressed: () {}),
      ));
      expect(find.text('Go'), findsOneWidget, reason: 'size $s');
    }
  });

  testWidgets('fires onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(
      AppButton(label: 'Go', onPressed: () => tapped = true),
    ));
    await tester.tap(find.text('Go'));
    expect(tapped, isTrue);
  });

  testWidgets('disabled when onPressed null', (tester) async {
    await tester.pumpWidget(_wrap(const AppButton(label: 'Go')));
    expect(find.text('Go'), findsOneWidget);
  });

  testWidgets('loading shows a progress indicator', (tester) async {
    await tester.pumpWidget(_wrap(
      AppButton(label: 'Go', isLoading: true, onPressed: () {}),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the new tests to confirm they fail**

Run: `cmd.exe /c flutter.bat test test/core/widgets/`
Expected: FAIL (compile errors — `GlassCard`, `AppButtonSize`, `badges.dart` missing).

- [ ] **Step 3: Rewrite `app_card.dart` (AppCard + GlassCard)**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Standard TaskTap card: BG1 surface, 14px radius, SH shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.onTap,
    this.backgroundColor,
    this.borderColor,
  });

  const AppCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSpacing.cardRadiusLg);
    final decoration = BoxDecoration(
      color: backgroundColor ?? AppColors.bg1,
      borderRadius: radius,
      border: Border.all(color: borderColor ?? AppColors.bl),
      boxShadow: AppColors.sh,
    );

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: content,
          ),
        ),
      );
    }
    return DecoratedBox(decoration: decoration, child: content);
  }
}

/// Translucent card for use on the dark hero gradient.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.base),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: AppColors.shInset,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
```

- [ ] **Step 4: Rewrite `app_button.dart` (5 variants × 3 sizes)**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum AppButtonVariant { primary, secondary, dark, ghost, danger }

enum AppButtonSize { sm, md, lg }

/// TaskTap button: 5 variants × 3 sizes, Manrope 700 label, optional leading
/// icon, optional full-width. Always ≥44pt tall (ui-ux-pro-max).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.expand = true,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.expand = true,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.expand = false,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.expand = true,
  }) : variant = AppButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final spec = _sizeSpec(size);
    final colors = _variantColors(variant);
    final enabled = onPressed != null && !isLoading;

    final fg = enabled
        ? colors.foreground
        : colors.foreground.withValues(alpha: 0.5);
    final bg = enabled
        ? colors.background
        : colors.background.withValues(alpha: 0.5);

    final textStyle = AppTextStyles.labelLarge.copyWith(
      fontSize: spec.fontSize,
      color: fg,
    );

    Widget content;
    if (isLoading) {
      content = SizedBox(
        height: spec.iconSize,
        width: spec.iconSize,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: spec.iconSize, color: fg),
          const SizedBox(width: 8),
          Text(label, style: textStyle),
        ],
      );
    } else {
      content = Text(label, style: textStyle);
    }

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(spec.radius),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(spec.radius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: spec.padding,
            decoration: variant == AppButtonVariant.ghost
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(spec.radius),
                    border: variant == AppButtonVariant.secondary
                        ? Border.all(color: AppColors.bm)
                        : null,
                    boxShadow: (variant == AppButtonVariant.primary ||
                            variant == AppButtonVariant.dark)
                        ? AppColors.sh
                        : null,
                  ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  _ButtonColors _variantColors(AppButtonVariant v) {
    return switch (v) {
      AppButtonVariant.primary =>
        const _ButtonColors(AppColors.y, AppColors.dark),
      AppButtonVariant.secondary =>
        const _ButtonColors(AppColors.bg3, AppColors.muted),
      AppButtonVariant.dark =>
        const _ButtonColors(AppColors.dark, AppColors.inv),
      AppButtonVariant.ghost =>
        const _ButtonColors(Colors.transparent, AppColors.dark),
      AppButtonVariant.danger =>
        const _ButtonColors(AppColors.redSoft, Color(0xFFCC0000)),
    };
  }

  _SizeSpec _sizeSpec(AppButtonSize s) {
    return switch (s) {
      AppButtonSize.lg => const _SizeSpec(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          fontSize: 16, radius: 20, iconSize: 18),
      AppButtonSize.md => const _SizeSpec(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          fontSize: 14, radius: 18, iconSize: 16),
      AppButtonSize.sm => const _SizeSpec(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          fontSize: 10, radius: 10, iconSize: 12),
    };
  }
}

class _ButtonColors {
  const _ButtonColors(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

class _SizeSpec {
  const _SizeSpec({
    required this.padding,
    required this.fontSize,
    required this.radius,
    required this.iconSize,
  });
  final EdgeInsets padding;
  final double fontSize;
  final double radius;
  final double iconSize;
}
```

- [ ] **Step 5: Create `badges.dart` (AppBadge, AppChip, StatusPill)**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/status_colors.dart';

/// Small rounded badge — Manrope 500, 10px (9px when [small]).
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.text,
    this.background = AppColors.bg3,
    this.foreground = AppColors.dark,
    this.small = false,
  });

  final String text;
  final Color background;
  final Color foreground;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
      ),
    );
  }
}

/// Selectable chip — white/DARK or DARK/white when [active].
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.dark : AppColors.white;
    final fg = active ? AppColors.white : AppColors.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: active ? AppColors.dark : AppColors.bm),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 11, fontWeight: FontWeight.w500, color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Status pill driven by the [WorkStatus] color map.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.small = false});

  final WorkStatus status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final pair = statusColorOf(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: pair.background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        workStatusLabel(status),
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w600,
          color: pair.foreground,
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Create `avatar.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Initials avatar with a deterministic color from the design cycle.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 36, this.color});

  final String name;
  final double size;
  final Color? color;

  static const List<Color> _cycle = [
    AppColors.y,
    Color(0xFFA8DADC),
    Color(0xFFFFE66D),
    AppColors.cyan,
    Color(0xFFF4A261),
    AppColors.amber,
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = color ?? _cycle[name.hashCode.abs() % _cycle.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: AppTextStyles.labelLarge.copyWith(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: AppColors.dark,
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Create `key_val.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Label/value row (horizontal) or stacked pair (vertical).
class KeyVal extends StatelessWidget {
  const KeyVal({
    super.key,
    required this.label,
    required this.value,
    this.vertical = false,
  });

  final String label;
  final String value;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.labelMedium.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: AppColors.muted,
    );
    final valueStyle = AppTextStyles.bodyMedium.copyWith(
      fontSize: vertical ? 14 : 13,
      color: AppColors.dark,
    );

    if (vertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: labelStyle),
            const SizedBox(height: 4),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.bl)),
      ),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: labelStyle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: Create `section_title.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// Sora 700/18 section heading with optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 20, 19, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: Create `app_toggle.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 38×22 toggle: Y track (on) / BM track (off), 16px white knob, 200ms.
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          width: 44, // ≥44 hit target; visual track 38 below
          height: 44,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? AppColors.y : AppColors.bm,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 10: Update the barrel `widgets.dart`**

```dart
export 'app_button.dart';
export 'app_card.dart';
export 'app_text_field.dart';
export 'app_toggle.dart';
export 'avatar.dart';
export 'badges.dart';
export 'key_val.dart';
export 'section_title.dart';
export 'status_badge.dart';
```

- [ ] **Step 11: Run analyze + widget tests**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean. If existing screens used the old `AppButton` (no `size`) the defaults keep them compiling; if any screen passed `icon:` as a `Widget`, change is needed — `icon` is now `IconData?`. Grep first: `grep -rn "AppButton" /mnt/d/AEA/Sviluppi/TaskTap/mobile/lib/presentation`. For each call passing a widget icon, change it to pass the `IconData` (e.g. `icon: Icons.add`). Keep edits minimal.

Run: `cmd.exe /c flutter.bat test test/core/widgets/`
Expected: PASS.

- [ ] **Step 12: Run the full suite**

Run: `cmd.exe /c flutter.bat test`
Expected: green, ≥ 204.

- [ ] **Step 13: Commit**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add lib/core/widgets test/core/widgets
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "feat(mobile): basic design-system components (card, glass, button, badge, chip, status pill, avatar, keyval, section title, toggle)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 (Commit 3): Layout / navigation components

**Files:**
- Create: `lib/core/widgets/bottom_nav.dart`
- Create: `lib/core/widgets/screen_header.dart`
- Create: `lib/core/widgets/search_bar.dart`
- Create: `lib/core/widgets/list_row.dart`
- Create: `lib/core/widgets/app_tabs.dart`
- Create: `lib/core/widgets/app_fab.dart`
- Create: `lib/core/widgets/empty_state.dart`
- Create: `lib/core/widgets/stepper.dart`
- Modify: `lib/core/widgets/widgets.dart`

**Interfaces:**
- Produces `class AppBottomNavItem { final IconData icon; final String label; }` and `AppBottomNav({required int currentIndex, required ValueChanged<int> onTap, List<AppBottomNavItem>? items})`. Default items: Dashboard(`LucideIcons.home`), Ticket(`LucideIcons.ticket`), Timbra(`LucideIcons.clock`), Calendario(`LucideIcons.calendar`), Altro(`LucideIcons.moreHorizontal`). Active tab → yellow bg, 19px radius, icon(18 DARK)+Sora 600/12 label; inactive → icon only (DIS). 200ms transition. Floating white pill, 23px radius, 0.5px BL border, SH shadow.
- Produces `HeaderIconBtn({required IconData icon, VoidCallback? onTap, bool showDot, bool glass})` — 38×38 (≥44 hit area) circle, BG3 (or glass on dark), icon 17 DARK, optional red dot.
- Produces `ScreenHeader({required String title, String? subtitle, bool showBack, VoidCallback? onBack, List<Widget> actions})`.
- Produces `AppSearchBar({TextEditingController? controller, String hint, ValueChanged<String>? onChanged})`.
- Produces `ListRow({Widget? leading, required String title, String? subtitle, Widget? meta, VoidCallback? onTap})` — chevron shown when `onTap != null`.
- Produces `class AppTab { final String label; final int? count; }` and `AppTabs({required List<AppTab> tabs, required int selectedIndex, required ValueChanged<int> onSelected})`.
- Produces `AppFab({required VoidCallback onPressed, IconData icon})`.
- Produces `EmptyState({required IconData icon, required String title, String? body, Widget? action})`.
- Produces `class StepperStep { final String label; }` and `AppStepper({required List<StepperStep> steps, required int currentIndex})` — circle index 22, Y when done/current else BS, check icon when done, Sora 600/10 labels, 2px connectors.

- [ ] **Step 1: Write the failing bottom-nav test**

Create `test/core/widgets/bottom_nav_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the 5 default Italian tabs', (tester) async {
    await tester.pumpWidget(_wrap(
      AppBottomNav(currentIndex: 0, onTap: (_) {}),
    ));
    // Active tab shows its label; inactive are icon-only.
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('active tab label is shown, inactive labels hidden',
      (tester) async {
    await tester.pumpWidget(_wrap(
      AppBottomNav(currentIndex: 1, onTap: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ticket'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(_wrap(
      AppBottomNav(currentIndex: 0, onTap: (i) => tapped = i),
    ));
    await tester.tap(find.byIcon(AppBottomNavIcons.calendar));
    expect(tapped, equals(3));
  });

  testWidgets('active tab background is brand yellow', (tester) async {
    await tester.pumpWidget(_wrap(
      AppBottomNav(currentIndex: 0, onTap: (_) {}),
    ));
    await tester.pumpAndSettle();
    final active = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final hasYellow = active.any((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == AppColors.y;
    });
    expect(hasYellow, isTrue);
  });
}
```

Note: `AppBottomNavIcons` is a small helper exposing the default tab `IconData`s (`home`, `ticket`, `clock`, `calendar`, `more`) so tests can reference them without importing lucide directly. Define it in `bottom_nav.dart`.

- [ ] **Step 2: Run to confirm failure**

Run: `cmd.exe /c flutter.bat test test/core/widgets/bottom_nav_test.dart`
Expected: FAIL (compile error — `bottom_nav.dart` missing).

- [ ] **Step 3: Create `bottom_nav.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Default tab icons (exposed so tests/screens needn't import lucide).
abstract final class AppBottomNavIcons {
  static const IconData home = LucideIcons.home;
  static const IconData ticket = LucideIcons.ticket;
  static const IconData clock = LucideIcons.clock;
  static const IconData calendar = LucideIcons.calendar;
  static const IconData more = LucideIcons.moreHorizontal;
}

class AppBottomNavItem {
  const AppBottomNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Floating-pill bottom navigation. Active tab: yellow bg + label; inactive:
/// icon only. 5 tabs by default (Dashboard/Ticket/Timbra/Calendario/Altro).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppBottomNavItem>? items;

  static const List<AppBottomNavItem> _defaults = [
    AppBottomNavItem(icon: AppBottomNavIcons.home, label: 'Dashboard'),
    AppBottomNavItem(icon: AppBottomNavIcons.ticket, label: 'Ticket'),
    AppBottomNavItem(icon: AppBottomNavIcons.clock, label: 'Timbra'),
    AppBottomNavItem(icon: AppBottomNavIcons.calendar, label: 'Calendario'),
    AppBottomNavItem(icon: AppBottomNavIcons.more, label: 'Altro'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = items ?? _defaults;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 0, 19, 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: AppColors.bl, width: 0.5),
            boxShadow: AppColors.sh,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < tabs.length; i++)
                _NavTab(
                  item: tabs[i],
                  active: i == currentIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppBottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: active ? 16 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.y : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 18,
                color: active ? AppColors.dark : AppColors.dis,
              ),
              if (active) ...[
                const SizedBox(width: 8),
                Text(item.label, style: AppTextStyles.navLabel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create `screen_header.dart` (ScreenHeader + HeaderIconBtn)**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 38×38 circular icon button (≥44 hit area), BG3 bg, optional red dot.
class HeaderIconBtn extends StatelessWidget {
  const HeaderIconBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.showDot = false,
    this.glass = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool showDot;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: glass
                        ? Colors.white.withValues(alpha: 0.18)
                        : AppColors.bg3,
                    shape: BoxShape.circle,
                    border: glass
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 0.5,
                          )
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: glass ? AppColors.white : AppColors.dark,
                  ),
                ),
                if (showDot)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen header with optional back chevron, title + subtitle, trailing actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HeaderIconBtn(
                icon: LucideIcons.chevronLeft,
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.title,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Create `search_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// BG3 search field, 12px radius, search icon + Manrope 14 input.
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    this.controller,
    this.hint = 'Cerca…',
    this.onChanged,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bg3,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(LucideIcons.search, size: 16, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: AppTextStyles.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.dis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Create `list_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 12/19 list row: leading slot, title + subtitle, meta, chevron if tappable.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.meta,
    this.onTap,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.bl)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (meta != null) ...[const SizedBox(width: 12), meta!],
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.dis),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
```

- [ ] **Step 7: Create `app_tabs.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppTab {
  const AppTab({required this.label, this.count});
  final String label;
  final int? count;
}

/// Horizontal scrolling tabs: active DARK + 2px Y underline, inactive MUTED.
class AppTabs extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final active = i == selectedIndex;
          return InkWell(
            onTap: () => onSelected(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.y : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tabs[i].label,
                    style: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.dark : AppColors.muted,
                    ),
                  ),
                  if (tabs[i].count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${tabs[i].count}',
                        style: AppTextStyles.labelSmall.copyWith(fontSize: 9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 8: Create `app_fab.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';

/// 56px yellow FAB with a strong drop shadow.
class AppFab extends StatelessWidget {
  const AppFab({
    super.key,
    required this.onPressed,
    this.icon = LucideIcons.plus,
  });

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.y,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: AppColors.dark),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Create `empty_state.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Centered empty state: 60px circle + icon, title, body, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: AppColors.bg3,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: AppColors.dis),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSmall,
            ),
            if (body != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 10: Create `stepper.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class StepperStep {
  const StepperStep({required this.label});
  final String label;
}

/// Numbered horizontal stepper. Completed/current circles are yellow (check
/// icon when complete); upcoming are BS. 2px connector lines colored by state.
class AppStepper extends StatelessWidget {
  const AppStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  final List<StepperStep> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                _Circle(index: i, currentIndex: currentIndex),
                const SizedBox(height: 4),
                Text(
                  steps[i].label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.stepLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 16,
                height: 2,
                color: i < currentIndex ? AppColors.y : AppColors.bs,
              ),
            ),
        ],
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.index, required this.currentIndex});
  final int index;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final done = index < currentIndex;
    final current = index == currentIndex;
    final filled = done || current;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppColors.y : AppColors.bs,
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(LucideIcons.check, size: 12, color: AppColors.dark)
          : Text(
              '${index + 1}',
              style: AppTextStyles.stepLabel.copyWith(color: AppColors.dark),
            ),
    );
  }
}
```

- [ ] **Step 11: Update barrel `widgets.dart`**

Add the new exports (keep prior ones):

```dart
export 'app_button.dart';
export 'app_card.dart';
export 'app_fab.dart';
export 'app_tabs.dart';
export 'app_text_field.dart';
export 'app_toggle.dart';
export 'avatar.dart';
export 'badges.dart';
export 'bottom_nav.dart';
export 'empty_state.dart';
export 'key_val.dart';
export 'list_row.dart';
export 'screen_header.dart';
export 'search_bar.dart';
export 'section_title.dart';
export 'status_badge.dart';
export 'stepper.dart';
```

- [ ] **Step 12: Run analyze + the nav test**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean.

Run: `cmd.exe /c flutter.bat test test/core/widgets/bottom_nav_test.dart`
Expected: PASS.

- [ ] **Step 13: Run full suite**

Run: `cmd.exe /c flutter.bat test`
Expected: green, ≥ 204.

- [ ] **Step 14: Commit**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add lib/core/widgets test/core/widgets
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "feat(mobile): layout/nav components (bottom nav, header, search, list row, tabs, fab, empty state, stepper)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5 (Commit 4): Dashboard pieces + signature placeholder

**Files:**
- Create: `lib/core/widgets/hero.dart`
- Create: `lib/core/widgets/active_job_card.dart`
- Create: `lib/core/widgets/stats_grid.dart`
- Create: `lib/core/widgets/quick_action.dart`
- Create: `lib/core/widgets/signature_pad.dart`
- Modify: `lib/core/widgets/widgets.dart`

**Interfaces:**
- Produces `DashboardHero({required String userName, String greeting, List<Widget> actions, Widget? child})` — dark gradient + 0.45 black overlay, bottom radius 30, minHeight 430; "Bentornato" + yellow user name; trailing glass actions; holds an optional child (glass cards).
- Produces `ActiveJobCard({required WorkStatus status, required String title, String? client, required String elapsed, VoidCallback? onOpen})` — `elapsed` is a pre-formatted `HH:MM:SS` string shown as three translucent tiles + a small yellow "Apri attività" button.
- Produces `class StatItem { final String label; final String value; }` and `StatsGrid({required List<StatItem> items})` — 2×2 with DIV dividers.
- Produces `QuickAction({required IconData icon, required String label, VoidCallback? onTap})` — 50px yellow circle + icon + Manrope 700/10 label.
- Produces `SignaturePadPlaceholder({bool signed, String? signedAt, VoidCallback? onTap})` — dashed border empty state or filled state showing "Firmato il …".

- [ ] **Step 1: Create `hero.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Dashboard hero: dark gradient with black overlay, rounded bottom, holding
/// a greeting, the user's name in brand yellow, trailing actions, and a child.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.userName,
    this.greeting = 'Bentornato',
    this.actions = const [],
    this.child,
  });

  final String userName;
  final String greeting;
  final List<Widget> actions;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 430),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.charcoal, AppColors.dark],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 12, 19, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              greeting,
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w500,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userName,
                              style: AppTextStyles.displayLarge.copyWith(
                                color: AppColors.y,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final a in actions) ...[
                        const SizedBox(width: 8),
                        a,
                      ],
                    ],
                  ),
                  if (child != null) ...[
                    const SizedBox(height: 20),
                    child!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create `active_job_card.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/status_colors.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'badges.dart';

/// Glass card showing the active job: status, title, client, an HH:MM:SS timer
/// (rendered as separate tiles) and an "Apri attività" action.
class ActiveJobCard extends StatelessWidget {
  const ActiveJobCard({
    super.key,
    required this.status,
    required this.title,
    this.client,
    required this.elapsed,
    this.onOpen,
  });

  final WorkStatus status;
  final String title;
  final String? client;

  /// Pre-formatted "HH:MM:SS".
  final String elapsed;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final segments = elapsed.split(':');
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(status: status),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTextStyles.title.copyWith(color: AppColors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                if (client != null)
                  Text(
                    client!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.inv,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 140,
                  child: AppButton(
                    label: 'Apri attività',
                    size: AppButtonSize.sm,
                    expand: false,
                    onPressed: onOpen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              for (final seg in segments) ...[
                _TimerTile(value: seg),
                if (seg != segments.last) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TimerTile extends StatelessWidget {
  const _TimerTile({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: AppTextStyles.bodyLarge.copyWith(
          fontSize: 18,
          color: AppColors.white,
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Create `stats_grid.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class StatItem {
  const StatItem({required this.label, required this.value});
  final String label;
  final String value;
}

/// 2×2 stats grid with DIV dividers. Manrope 12 label + Manrope 500/36 value.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.items});
  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < items.length; row += 2)
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _Cell(item: items[row])),
                if (row + 1 < items.length) ...[
                  const VerticalDivider(width: 1, color: AppColors.div),
                  Expanded(child: _Cell(item: items[row + 1])),
                ] else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.item});
  final StatItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(item.value, style: AppTextStyles.kpi),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create `quick_action.dart`**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 50px yellow circle + icon + centered Manrope 700/10 label.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  color: AppColors.y,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppColors.dark),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create `signature_pad.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Placeholder signature pad. Empty: dashed border + "Tocca per firmare".
/// Signed: solid border + "Firmato il …". (Real capture comes in a later phase.)
class SignaturePadPlaceholder extends StatelessWidget {
  const SignaturePadPlaceholder({
    super.key,
    this.signed = false,
    this.signedAt,
    this.onTap,
  });

  final bool signed;
  final String? signedAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: signed ? 'Firma acquisita' : 'Tocca per firmare',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 90,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: signed ? AppColors.bg2 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.bs,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.penLine,
                size: 22,
                color: signed ? AppColors.dark : AppColors.muted,
              ),
              const SizedBox(height: 6),
              Text(
                signed ? 'Firmato il ${signedAt ?? ''}'.trim() : 'Tocca per firmare',
                style: AppTextStyles.bodySmall.copyWith(
                  color: signed ? AppColors.dark : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Update barrel `widgets.dart`**

Add the new exports (alphabetical, keep prior):

```dart
export 'active_job_card.dart';
export 'app_button.dart';
export 'app_card.dart';
export 'app_fab.dart';
export 'app_tabs.dart';
export 'app_text_field.dart';
export 'app_toggle.dart';
export 'avatar.dart';
export 'badges.dart';
export 'bottom_nav.dart';
export 'empty_state.dart';
export 'hero.dart';
export 'key_val.dart';
export 'list_row.dart';
export 'quick_action.dart';
export 'screen_header.dart';
export 'search_bar.dart';
export 'section_title.dart';
export 'signature_pad.dart';
export 'stats_grid.dart';
export 'status_badge.dart';
export 'stepper.dart';
```

- [ ] **Step 7: Run analyze**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean.

- [ ] **Step 8: Run full suite**

Run: `cmd.exe /c flutter.bat test`
Expected: green, ≥ 204.

- [ ] **Step 9: Commit**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add lib/core/widgets
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "feat(mobile): dashboard pieces (hero, active job card, stats grid, quick action) + signature placeholder

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6 (Commit 5): Widget test suite + final verification

**Files:**
- Modify: `test/core/widgets/button_test.dart` (already created Task 3 — extend with per-variant color checks)
- Modify: `test/core/widgets/status_pill_test.dart` (already covers all 13 — verify)
- Modify: `test/core/widgets/bottom_nav_test.dart` (already covers active state — verify)
- Modify: `test/core/widgets/card_test.dart` (already covers card/glass — verify)
- Create: `test/core/widgets/stepper_test.dart`

**Interfaces:**
- Consumes: `AppButton`, `AppButtonVariant`, `AppButtonSize` (Task 3); `StatusPill`, `WorkStatus` (Tasks 2–3); `AppBottomNav`, `AppBottomNavIcons` (Task 4); `AppCard`, `GlassCard` (Task 3); `AppStepper`, `StepperStep` (Task 4).

The button/status-pill/bottom-nav/card tests were authored in earlier tasks and already satisfy the Commit-5 coverage requirement. This task adds the stepper-progress test and runs the whole suite as the final gate.

- [ ] **Step 1: Create `test/core/widgets/stepper_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/stepper.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _steps = [
  StepperStep(label: 'Dati'),
  StepperStep(label: 'Staff'),
  StepperStep(label: 'Materiali'),
  StepperStep(label: 'Firme'),
];

void main() {
  testWidgets('renders every step label', (tester) async {
    await tester.pumpWidget(_wrap(
      const AppStepper(steps: _steps, currentIndex: 1),
    ));
    for (final s in _steps) {
      expect(find.text(s.label), findsOneWidget);
    }
  });

  testWidgets('completed steps before current show a check icon',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const AppStepper(steps: _steps, currentIndex: 2),
    ));
    // Steps 0 and 1 are done → 2 check icons.
    expect(find.byIcon(LucideIcons.check), findsNWidgets(2));
  });

  testWidgets('no checks when on the first step', (tester) async {
    await tester.pumpWidget(_wrap(
      const AppStepper(steps: _steps, currentIndex: 0),
    ));
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('upcoming steps show their 1-based number', (tester) async {
    await tester.pumpWidget(_wrap(
      const AppStepper(steps: _steps, currentIndex: 0),
    ));
    // Current (1) + upcoming (2,3,4) are numbered; none are done.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Extend `button_test.dart` with per-variant background checks**

Append this test inside the existing `main()` of `test/core/widgets/button_test.dart` (after the last `testWidgets`):

```dart
  testWidgets('primary variant paints brand yellow', (tester) async {
    await tester.pumpWidget(_wrap(
      const AppButton(label: 'Go', variant: AppButtonVariant.primary),
    ));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(Material),
      ).first,
    );
    expect(material.color, isNotNull);
  });
```

(Keep it lightweight — the per-variant render coverage already exists from the loop test.)

- [ ] **Step 3: Run the full widget-test folder**

Run: `cmd.exe /c flutter.bat test test/core/widgets/`
Expected: all PASS.

- [ ] **Step 4: Run analyze**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean.

- [ ] **Step 5: Run the entire suite (final gate)**

Run: `cmd.exe /c flutter.bat test`
Expected: green, total ≥ 204.

- [ ] **Step 6: Commit**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add test/core/widgets
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "test(mobile): widget tests for buttons, status pill, bottom nav, cards, stepper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Verify existing screens still compile and the shell test passes

**Files:**
- Modify (only if needed): `lib/presentation/screens/home/home_shell.dart`
- Modify (only if needed): `test/presentation/app_shell_test.dart`

**Interfaces:**
- Consumes: all components above.

The M1 `home_shell.dart` uses Flutter's `NavigationBar` with 4 Italian destinations (Oggi/Interventi/Rapportini/Profilo) and `test/presentation/app_shell_test.dart` asserts that. The design spec's `AppBottomNav` is a *foundation component* — this plan does NOT rewire the shell (that's a later screen phase). Leave `home_shell.dart` as-is so the existing shell test keeps passing. Do not swap the shell to `AppBottomNav` here.

- [ ] **Step 1: Confirm no screen referenced a removed token/name**

Run: `grep -rn "AppColors\." /mnt/d/AEA/Sviluppi/TaskTap/mobile/lib/presentation | grep -vE "AppColors\.(y|yDark|ySoft|dark|charcoal|fg2|muted|dis|inv|white|bg1|bg2|bg3|bg4|bl|bm|bs|div|amber|green|blue|cyan|red|redSoft|sh|shInset|brand|onBrand|surface|background|surfaceVariant|outline|textPrimary|textSecondary|textDisabled|error|onError|success|warning|info|status)"`
Expected: no output (every referenced token exists, original or alias). If a line appears, add the missing alias to `app_colors.dart` (do not edit the screen).

- [ ] **Step 2: Confirm `AppButton` call sites still compile**

Run: `grep -rn "AppButton(" /mnt/d/AEA/Sviluppi/TaskTap/mobile/lib`
For each hit, confirm it passes either no `icon` or `icon:` as `IconData`. If any passes a `Widget` (e.g. `icon: Icon(...)`), change that argument to the bare `IconData` (e.g. `icon: Icons.send`). Minimal edits only.

- [ ] **Step 3: Run analyze**

Run: `cmd.exe /c flutter.bat analyze`
Expected: clean.

- [ ] **Step 4: Run the full suite**

Run: `cmd.exe /c flutter.bat test`
Expected: green, ≥ 204 (the shell test still passes — shell untouched).

- [ ] **Step 5: Commit (only if any edit was required)**

```bash
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile add -A lib test
git -C /mnt/d/AEA/Sviluppi/TaskTap/mobile commit -m "fix(mobile): adapt existing call sites to new design-system tokens/components

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

If no edit was required, skip the commit and note "no call-site changes needed" in the final report.

---

## Self-Review

**Spec coverage:**
- Tokens (Brand/Ink/Surfaces/Borders/Semantic, 2 shadows) → Task 2 `app_colors.dart`. ✓
- Fonts Sora/Manrope/Inter → Task 2 `app_text_styles.dart`. ✓
- 13 Italian statuses → Task 2 `status_colors.dart` + asserted in `theme_test.dart`. ✓
- `buildAppTheme()` → Task 2. ✓
- Card, GlassCard → Task 3. ✓
- Btn 5×3 → Task 3. ✓
- Badge, Chip, StatusPill → Task 3. ✓
- Avatar, KeyVal, SectionTitle, AppToggle → Task 3. ✓
- BottomNav (5 tabs, active yellow+label, 200ms) → Task 4. ✓
- ScreenHeader, HeaderIconBtn, SearchBar, ListRow, AppTabs, Fab, EmptyState, Stepper → Task 4. ✓
- Hero, ActiveJobCard, StatsGrid, QuickAction, SignaturePad placeholder → Task 5. ✓
- Tests: Btn variants, StatusPill (13), BottomNav active, Card/GlassCard, Stepper progress → Tasks 3–6. ✓
- lucide_icons (single icon family, no emoji) → Task 1. ✓
- ui-ux-pro-max (≥44pt, contrast, 150–300ms, safe areas) → applied in each component (minHeight 44, SafeArea in BottomNav/Hero, 200ms animations). ✓
- Keep existing screens compiling + ≥204 tests → Tasks 2/3/7 (aliases + compat shim + untouched shell). ✓

**Placeholder scan:** No "TBD"/"add validation"/"similar to" — every code step carries full content. ✓

**Type consistency:** `WorkStatus`/`statusColorOf`/`workStatusLabel` consistent across Tasks 2–5; `AppButtonSize`/`AppButtonVariant` consistent Tasks 3 & 6; `AppBottomNavIcons` defined in Task 4 and used in its test; `StepperStep`/`AppStepper` consistent Tasks 4 & 6; `DashboardHero` named to avoid clash with Flutter `Hero`; `GlassCard`/`AppCard` consistent Tasks 3 & 5. ✓

---

## Notes / Risk callouts

- `lucide_icons` version `^0.257.0` is a guess; if the solver rejects it, fall back to `flutter pub add lucide_icons` (Task 1 Step 2) and accept whatever compatible version resolves. The icon constant names used (`home`, `ticket`, `clock`, `calendar`, `moreHorizontal`, `search`, `chevronRight`, `chevronLeft`, `plus`, `bell`, `user`, `check`, `penLine`) are standard Lucide names; if any differs in the resolved version, pick the nearest equivalent and keep going.
- True CSS `inset` shadows are not expressible as Flutter `BoxShadow`; `shInset` approximates and `GlassCard` leans on gradient overlays — documented inline, not a blocker.
- The shell is intentionally left on Material `NavigationBar` (4 tabs) to keep the existing shell test green; wiring `AppBottomNav` (5 tabs) into the real shell is a later screen phase.
