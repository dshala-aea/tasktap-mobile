# Il Documento — Screen Sweep (Plan 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every remaining direct `Vetro*`/`context.vetro` call site (53 files) with the
Documento-styled shared widgets Plan 1 already shipped, then retire the Vetro definition files
entirely now that nothing references them.

**Architecture:** Two new small flat-Documento widgets (`AppCompartmentTile`, `AppMapCard`) fill
the two gaps Plan 1's shared-widget layer didn't cover, mirroring `AppCard`'s existing shape. The
53 files then get the same mechanical transformation Plan 1's own Task 4 already validated and
reviewed clean, batched by feature area (never one subagent per file — same batching discipline
Plan 1 used). The final task deletes the 6 Vetro-definition files, deferred here from Plan 1
because deleting them earlier would have broken every one of these 53 files.

**Tech Stack:** Flutter, the token/widget layer Plan 1 already shipped (no new dependencies).

**Spec:** Plan 1's own spec, `docs/superpowers/specs/2026-09-03-il-documento-mobile-restyle-design.md`
— this plan is that spec's Architecture point 3 ("screens" scope), explicitly deferred there
until Plan 1's target widget APIs existed to sweep toward.

## Global Constraints

- Token names stay the same; only what they resolve to changes (Plan 1's own established rule).
- `AppColors.Y` (`#C03221`, the brand accent) is the ONE theme-invariant exception — safe as a raw
  constant. Everything else (fill/border colors) MUST read through `context.colors.*` (the
  `AppPalette` `BuildContext` extension, `app_palette.dart:338,343`) — NEVER a raw `AppColors.*`
  constant for anything but `Y`. This exact bug (reading a theme-invariant constant where a
  theme-flipping token was required) was caught and fixed twice during Plan 1 (`AppCard`,
  `app_toast.dart`/`error_state.dart`) — do not reintroduce it here.
- No `BackdropFilter`/blur/gradient anywhere after this plan, in any of the 53 files.
- `lib/core/theme/status_colors.dart` and `lib/core/widgets/app_toast.dart`/
  `lib/core/widgets/error_state.dart` are explicitly OUT of this plan's scope — `status_colors.dart`
  reads `context.vetro` for semantic status tints (good/warn/bad), which Plan 1 deliberately left
  untouched pending a future dedicated status-color redesign; `app_toast.dart`/`error_state.dart`
  already correctly read `context.vetro.statusGood/Warn/Bad` per Plan 1's own plan-mandated
  exception — do not touch any of these three files in this plan.
- `lib/core/theme/app_theme.dart`'s `AppVetroPalette` `ThemeExtension` registration stays until
  Task 11 (the final task) — every other file in this plan depends on `context.vetro` resolving
  correctly until it's swept.

---

### Task 1: Build `AppCompartmentTile` and `AppMapCard`

**Files:**
- Create: `lib/core/widgets/app_compartment_tile.dart`
- Create: `lib/core/widgets/app_map_card.dart`
- Test: `test/core/widgets/app_compartment_tile_test.dart`
- Test: `test/core/widgets/app_map_card_test.dart`

**Interfaces:**
- Produces: `AppCompartmentTile({required IconData icon, required String label, required
  VoidCallback onTap})` — identical constructor shape to `VetroCompartmentTile`, so the 3 call
  sites (Task 4 batch) are a pure rename, no prop changes.
- Produces: `AppMapCard({required String address})` — identical constructor shape to
  `VetroMapCard`, so its 2 call sites (Task 4 batch) are a pure rename.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/widgets/app_compartment_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_compartment_tile.dart';

void main() {
  testWidgets('AppCompartmentTile has no BackdropFilter and calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AppCompartmentTile(
            icon: Icons.build,
            label: 'Materiali',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.byType(AppCompartmentTile));
    expect(tapped, isTrue);
  });
}
```

```dart
// test/core/widgets/app_map_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_map_card.dart';

void main() {
  testWidgets('AppMapCard has no BackdropFilter/gradient and shows the address', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: AppMapCard(address: 'Via Roma 1, Milano')),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Via Roma 1, Milano'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/widgets/app_compartment_tile_test.dart test/core/widgets/app_map_card_test.dart`
Expected: FAIL — neither file exists yet.

- [ ] **Step 3: Write `AppCompartmentTile`**

```dart
// dart format width=100
// lib/core/widgets/app_compartment_tile.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_rack.dart';

/// Flat Documento replacement for the old `VetroCompartmentTile` — same interface, so every call
/// site swaps one name for the other with no other changes. Shared across Ticket detail,
/// Rapportino, and Altro (same three screens `VetroCompartmentTile`'s own doc comment named).
class AppCompartmentTile extends StatelessWidget {
  const AppCompartmentTile({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Clamped for the same reason the old widget clamped it: the grid's fixed childAspectRatio
    // sizes this tile to a constant cell that doesn't grow with text, so an unclamped large
    // accessibility text size would overflow a 2-line label.
    final systemScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final clampedScaler = TextScaler.linear(systemScale > 1.3 ? 1.3 : systemScale);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRack.freeShape,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRack.freeShape,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: AppColors.Y),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
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

- [ ] **Step 4: Write `AppMapCard`**

```dart
// dart format width=100
// lib/core/widgets/app_map_card.dart
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_rack.dart';
import '../theme/app_spacing.dart';
import '../utils/maps_launcher.dart';
import 'app_card.dart';

/// Flat Documento replacement for the old `VetroMapCard` — same interface (one `address` prop),
/// so its 2 call sites (Ticket detail, Cantiere detail) swap one name for the other with no other
/// changes. Still not a real map SDK — a flat pin panel plus a single external maps launch,
/// exactly what the old widget's own doc comment already scoped it as.
class AppMapCard extends StatelessWidget {
  const AppMapCard({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              border: Border(bottom: BorderSide(color: context.colors.borderLight)),
            ),
            child: const SizedBox(
              height: 84,
              child: Center(child: Icon(LucideIcons.mapPin, size: 28, color: AppColors.Y)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _NavigaButton(address: address),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigaButton extends StatelessWidget {
  const _NavigaButton({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.Y,
      borderRadius: AppRack.insetShape,
      child: InkWell(
        borderRadius: AppRack.insetShape,
        onTap: () => openMapsForAddress(address),
        child: const ConstrainedBox(
          constraints: BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Naviga',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
```

(Verify `AppRack.freeShape`/`AppRack.insetShape` and `AppCard`'s exact `padding` parameter name
against their current definitions before pasting this verbatim — both were established by Plan 1
and should not have drifted, but confirm rather than assume.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/core/widgets/app_compartment_tile_test.dart test/core/widgets/app_map_card_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_compartment_tile.dart lib/core/widgets/app_map_card.dart \
        test/core/widgets/app_compartment_tile_test.dart test/core/widgets/app_map_card_test.dart
git commit -m "feat(widgets): add AppCompartmentTile/AppMapCard, flat Documento replacements"
```

---

### Task 2 through Task 10: The screen sweep (batched by area)

**Interfaces:**
- Consumes: `AppCard`, `AppButton`/`AppButtonVariant`, `AppBottomNav`, `AppCompartmentTile`,
  `AppMapCard` (Task 1), and the full Task-4-established transformation table below.
- Produces: no public API changes to any screen — this is a pure material-layer swap, screens keep
  their existing behavior/navigation/state management untouched.

**The transformation table** (apply exactly, in every file in every batch below — this is Plan 1's
own Task 4 table, already reviewed clean, extended with the two rows marked NEW for this plan):

| Find | Replace with |
|---|---|
| `context.vetro.tint` | `AppColors.Y` |
| `context.vetro.tintStrong` | `AppColors.Y` (no second gradient stop — flat fill) |
| `context.vetro.glassFill` | `context.colors.surface` |
| `context.vetro.glassBorder` | `context.colors.borderLight` |
| `context.vetro.hairline` | `context.colors.borderLight` |
| `context.vetro.statusGood`/`statusWarn`/`statusBad` | unchanged — out of scope, see Global Constraints |
| `AppVetroColors.blurSigma` (and any `ImageFilter.blur(...)` using it) | delete the blur entirely — remove the `BackdropFilter`/`ClipRRect` wrapper, keep only what it wrapped |
| `VetroGlass(...)`/`VetroCard(...)` as a direct call | replace with `AppCard(...)` — map its `padding`/`child` params directly; `AppCard`'s constructor already matches this shape (Plan 1, Task 2) |
| `VetroButton(...)` as a direct call | replace with `AppButton(...)` — map its variant/label/onPressed params to `AppButton`'s equivalent named params (check `AppButton`'s constructor signature directly before mapping — Plan 1, Task 2) |
| `VetroCompartmentTile(...)` | **NEW**: replace with `AppCompartmentTile(...)` — identical params, pure rename (Task 1) |
| `VetroMapCard(...)` | **NEW**: replace with `AppMapCard(...)` — identical params, pure rename (Task 1) |
| Any `LinearGradient(colors: [context.vetro.tint, context.vetro.tintStrong])` | replace the whole `gradient:` property with `color: AppColors.Y` on the same `BoxDecoration` |
| `import '../../../core/theme/app_vetro_palette.dart';` (or equivalent relative path) | remove once no `context.vetro`/`AppVetroColors`/`AppVetroPalette` reference remains in the file |
| `import '.../vetro_glass.dart';` / `.../vetro_card.dart';` / `.../vetro_button.dart';` / `.../vetro_compartment_tile.dart';` / `.../vetro_map_card.dart';` | remove once the corresponding call is gone from the file |

After each batch's files are edited, run (from the mobile repo root):

```bash
grep -rn "context\.vetro\|VetroGlass(\|VetroCard(\|VetroButton(\|VetroCompartmentTile(\|VetroMapCard(\|AppVetroColors\|AppVetroPalette" <batch's files, space-separated>
```

Expected: zero output for every file in that batch (any hits mean a reference was missed, not that
the grep is wrong — re-check the file).

**Batches** (grouped by feature area; each is ONE dispatch, ONE diff review — not one subagent per
file, per this skill's batching guidance for same-shape mechanical work):

- [ ] **Task 2 — Admin batch A (6 files):** `lib/features/admin/cantieri/admin_cantiere_detail_screen.dart`, `lib/features/admin/cantieri/admin_cantiere_form_screen.dart`, `lib/features/admin/commesse/admin_commessa_detail_screen.dart`, `lib/features/admin/contracts/admin_contract_detail_screen.dart`, `lib/features/admin/contracts/admin_contract_form_screen.dart`, `lib/features/admin/customers/admin_customer_detail_screen.dart`
- [ ] **Task 3 — Admin batch B (7 files):** `lib/features/admin/customers/admin_customer_form_screen.dart`, `lib/features/admin/locations/admin_location_detail_screen.dart`, `lib/features/admin/locations/admin_location_form_screen.dart`, `lib/features/admin/magazzini/admin_magazzino_detail_screen.dart`, `lib/features/admin/magazzini/admin_magazzino_form_screen.dart`, `lib/features/admin/materiali/admin_materiale_detail_screen.dart`, `lib/features/admin/materiali/admin_materiale_form_screen.dart`
- [ ] **Task 4 — Admin batch C (7 files):** `lib/features/admin/prodotti/admin_prodotto_detail_screen.dart`, `lib/features/admin/prodotti/admin_prodotto_form_screen.dart`, `lib/features/admin/reports/admin_report_detail_screen.dart`, `lib/features/admin/schedules/admin_schedule_detail_screen.dart`, `lib/features/admin/schedules/admin_schedule_form_screen.dart`, `lib/features/admin/schedules/admin_schedule_list_screen.dart`, `lib/features/admin/squadre/admin_squadra_detail_screen.dart`
- [ ] **Task 5 — Admin batch D + Agenda (3 files):** `lib/features/admin/squadre/admin_squadra_form_screen.dart`, `lib/features/agenda/agenda_form_screen.dart`, `lib/features/agenda/agenda_list_screen.dart`
- [ ] **Task 6 — Altro + Calendario (7 files):** `lib/features/altro/altro_hub_screen.dart` (uses `AppCompartmentTile` per Task 1's interface — confirm this file is one of the 3 named call sites), `lib/features/altro/i_miei_dati_screen.dart`, `lib/features/altro/impostazioni_screen.dart`, `lib/features/altro/notifiche_screen.dart`, `lib/features/calendario/calendario_screen.dart`, `lib/features/calendario/views/mese_view.dart`, `lib/features/calendario/views/settimana_view.dart`
- [ ] **Task 7 — Cantiere + Dashboard (4 files):** `lib/features/cantiere/cantiere_detail_screen.dart`, `lib/features/dashboard/dashboard_screen.dart`, `lib/features/dashboard/id_plate_hero_comp.dart`, `lib/features/dashboard/work_queue_section.dart`
- [ ] **Task 8 — Magazzino + Rapportino (8 files):** `lib/features/magazzino/magazzino_screen.dart`, `lib/features/rapportino/rapportini_list_screen.dart`, `lib/features/rapportino/rapportino_form_screen.dart` (uses `AppCompartmentTile`, per Task 1's interface), `lib/features/rapportino/rapportino_view_screen.dart`, `lib/features/rapportino/steps/step_dettagli.dart`, `lib/features/rapportino/steps/step_materiali_fold.dart`, `lib/features/rapportino/steps/step_ore.dart`, `lib/features/rapportino/steps/step_riepilogo.dart`
- [ ] **Task 9 — Ticket (5 files):** `lib/features/ticket/steps/step_assegnazione.dart`, `lib/features/ticket/steps/step_cliente_sede.dart`, `lib/features/ticket/steps/step_riepilogo_ticket.dart`, `lib/features/ticket/ticket_detail_screen.dart` (uses BOTH `AppCompartmentTile` AND `AppMapCard`, per Task 1's interfaces — this file has the heaviest reference count of the whole sweep, 12 in the original grounding pass; give this file extra care, re-verify its actual current Vetro usage line-by-line rather than assuming the table covers every instance), `lib/features/ticket/ticket_list_screen.dart`
- [ ] **Task 10 — Timbra + core + auth screens (6 files):** `lib/features/timbra/cantiere_timbra_screen.dart` (13 references in the original grounding pass — the heaviest single file, same "extra care" note as Task 9's ticket_detail_screen.dart), `lib/features/timbra/timbra_screen.dart`, `lib/core/scanner/barcode_scan_sheet.dart`, `lib/core/security/biometric_lock.dart`, `lib/presentation/screens/login/login_screen.dart`, `lib/presentation/screens/profilo/profilo_screen.dart`

For each batch task, the step structure is identical:

- [ ] **Step 1: Read each file's actual current Vetro usage**

Do not trust this plan's file list alone — grep each file in the batch for the exact table-row
patterns above and read the surrounding code before editing, since exact line numbers were not
captured per-file in this plan (unlike Plan 1's Task 4, which had them — this plan's grounding
pass captured file-level reference counts, not line numbers, given the larger scope).

- [ ] **Step 2: Apply the transformation table**

Apply every matching row from the table above to every file in this batch.

- [ ] **Step 3: Run the verification grep**

Run the grep command shown above the batch list, scoped to this batch's files. Expected: zero
output.

- [ ] **Step 4: Run each touched file's existing widget test, if one exists**

Run: `flutter test test/features/<matching path>/` for whichever of this batch's files have an
existing test directory — not every screen will have one; that's fine, note which don't rather than
inventing new test files for screens this plan doesn't otherwise touch behaviorally (this plan
changes material only, not behavior — existing tests, if any, should need zero assertion changes
unless they assert on a specific `Color`/`Gradient` value, matching Plan 1's Task 4 precedent for
when a pre-existing test legitimately needs updating).

- [ ] **Step 5: Commit**

```bash
git add <this batch's files>
git commit -m "feat(screens): <batch name> — flat Documento material, no more Vetro"
```

---

### Task 11: Retire the Vetro widget/theme files

**Files:**
- Delete: `lib/core/widgets/vetro_glass.dart`, `lib/core/widgets/vetro_card.dart`,
  `lib/core/widgets/vetro_button.dart`, `lib/core/widgets/vetro_compartment_tile.dart`,
  `lib/core/widgets/vetro_map_card.dart`, `lib/core/theme/app_vetro_palette.dart`
- Modify: `lib/core/theme/app_theme.dart` (remove the `AppVetroPalette` extension registration)

**Interfaces:**
- Consumes: confirmation from Tasks 2-10 that nothing outside `status_colors.dart`/
  `app_toast.dart`/`error_state.dart` (explicitly out of scope, Global Constraints) references
  these files anymore.
- Produces: nothing — pure deletion, no other file changes.

- [ ] **Step 1: Confirm zero remaining references outside the explicitly-scoped exceptions**

```bash
grep -rln "context\.vetro\|VetroGlass\|VetroCard\|VetroButton\|VetroCompartmentTile\|VetroMapCard\|AppVetroColors\|AppVetroPalette" lib/
```

Expected: only `lib/core/theme/status_colors.dart`, `lib/core/widgets/app_toast.dart`,
`lib/core/widgets/error_state.dart`, and the 6 Vetro-definition files themselves. Any other file in
the output means a Task 2-10 batch missed something — stop and fix that batch's file, do not delete
the Vetro files while a real (non-exempted) reference still exists.

- [ ] **Step 2: Delete the 5 widget files and the palette file**

```bash
git rm lib/core/widgets/vetro_glass.dart lib/core/widgets/vetro_card.dart \
       lib/core/widgets/vetro_button.dart lib/core/widgets/vetro_compartment_tile.dart \
       lib/core/widgets/vetro_map_card.dart lib/core/theme/app_vetro_palette.dart
```

- [ ] **Step 3: Remove the `AppVetroPalette` registration from `app_theme.dart`**

Find and remove the line registering `AppVetroPalette` in the `ThemeData.extensions` list (or
equivalent) inside `buildAppTheme()` — read the file first to get its exact current form, since
Plan 1 did not touch this specific line. `status_colors.dart`/`app_toast.dart`/`error_state.dart`
still call `context.vetro` — if `AppVetroPalette` is removed from the theme's extensions entirely,
`context.vetro` (however that extension getter is implemented) will throw or return a fallback at
runtime for those 3 files. **Before removing the registration, re-verify**: if those 3 files
genuinely still need a working `context.vetro`, this task cannot fully retire `AppVetroPalette` —
report this as a real plan conflict (a ruling, not a silent skip) rather than deleting something 3
files still depend on. The likely correct resolution: `status_colors.dart` should be checked first
— if it can be trivially repointed to read the semantic status colors from `AppPalette`/
`context.colors` instead (a different token, not `context.vetro`), that closes the gap within this
task's scope; if it can't be done trivially, park it with a ruling and leave `AppVetroPalette`
registered with only `status_colors.dart` depending on it, noting this as a known residual for a
future plan.

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: no errors (a few `unused_import` warnings are possible if a batch task left a stray
import — fix any that surface here).

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: all pass, no regressions.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(theme): retire the Vetro widget/theme files — Il Documento sweep complete"
```

---

## Self-review notes (per this skill's own required step)

**Spec coverage:** All 53 files from the current grep-verified sweep scope are assigned to exactly
one batch (Tasks 2-10: 6+7+7+3+7+4+8+5+6 = 53), each file appearing once — cross-checked against
the grounding grep's file list directly, no duplicates, no omissions. `status_colors.dart` is
explicitly named as out-of-scope rather than silently omitted (Global Constraints). Task 1 (new
widgets) and Task 11 (retirement) cover the spec's remaining two structural requirements.

**Placeholder scan:** The batch tasks intentionally do not hand-list every file's exact line
numbers (unlike Plan 1's Task 4) — flagged explicitly in each batch's Step 1 as a real, stated gap
("grounding pass captured file-level reference counts, not line numbers, given the larger scope"),
with an explicit instruction for what to do about it (grep and read before editing), not a vague
"add appropriate changes." This is a conscious plan-scale tradeoff, not an oversight.

**Type consistency:** `AppCompartmentTile`/`AppMapCard` (Task 1) use the exact constructor
signatures their respective 3 and 2 call sites (Tasks 6, 8, 9) are told to expect. The
transformation table (used identically by Tasks 2-10) is Plan 1's own Task 4 table, already
validated by that plan's review cycle, plus two new rows for the two widgets Task 1 adds — no
invented syntax, no renamed tokens.
