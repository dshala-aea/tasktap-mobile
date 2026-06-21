# Design System Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build all basic design-system component widgets in `lib/core/widgets/` matching DESIGN-SPEC.md Components section, with widget tests.

**Architecture:** Replace/extend existing AppButton/AppCard/StatusBadge stubs with spec-exact implementations. Add new widgets (GlassCard, Badge, Chip, StatusPill, Avatar, KeyVal, SectionTitle, AppToggle) as separate files. Export all from `widgets.dart`. Add `lucide_icons` dep.

**Tech Stack:** Flutter 3.x, Dart 3.11+, google_fonts (Sora/Manrope already present), lucide_icons (add), flutter_test for widget tests.

## Global Constraints

- Flutter command: `cmd.exe /c flutter.bat <args>` from `/mnt/d/AEA/Sviluppi/TaskTap/mobile/`
- No Android SDK; verify only with `analyze` and `test`
- Token names: AppColors.Y, DARK, BG1, BG3, BL, BM, BS, MUTED, REDSOFT, INV, AMBER, CHARCOAL, WHITE, etc.
- `statusColor(String stato)` from `lib/core/theme/status_colors.dart`
- `AppTextStyles.*` from `lib/core/theme/app_text_styles.dart`
- `AppColors.SH`, `AppColors.SH_INSET` for shadows
- ≥44pt hit areas, ≥4.5:1 contrast, 150–300ms motion, press feedback
- No emoji, lucide_icons or existing icon approach
- ONE commit at the end
- Do NOT build nav/layout/dashboard/screen components

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `pubspec.yaml` | Modify | Add `lucide_icons: ^0.3.4` |
| `lib/core/widgets/app_card.dart` | Modify | Add GlassCard, fix spec (BG1, 14px radius, pad 16) |
| `lib/core/widgets/app_button.dart` | Rewrite | 5 variants × 3 sizes, dark variant, icon, full-width, ≥44pt |
| `lib/core/widgets/badge.dart` | Create | Badge + Chip widgets |
| `lib/core/widgets/status_pill.dart` | Create | StatusPill driven by statusColor() |
| `lib/core/widgets/avatar.dart` | Create | Initials circle, color cycle, Manrope 700 |
| `lib/core/widgets/key_val.dart` | Create | KeyVal horizontal + vertical |
| `lib/core/widgets/section_title.dart` | Create | SectionTitle Sora 700/18 |
| `lib/core/widgets/app_toggle.dart` | Create | 38×22 toggle, Y/BM track, 200ms |
| `lib/core/widgets/widgets.dart` | Modify | Export all new files |
| `test/core/widgets/app_button_test.dart` | Create | AppButton variants × sizes |
| `test/core/widgets/status_pill_test.dart` | Create | StatusPill all 13 stati |
| `test/core/widgets/avatar_test.dart` | Create | Avatar initials, color cycle |
| `test/core/widgets/app_toggle_test.dart` | Create | Toggle state, animation |

---

### Task 1: Add lucide_icons dependency + update AppCard with GlassCard

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/widgets/app_card.dart`

**Interfaces:**
- Produces: `AppCard` (BG1, 14px radius, pad 16, SH shadow), `GlassCard` (white-translucent gradient, 0.5px white border, SH_INSET, 14px radius, optional onTap)

- [ ] Add `lucide_icons: ^0.3.4` to `pubspec.yaml` under dependencies
- [ ] Rewrite `app_card.dart` to use BG1 bg, 14px radius, default 16 padding, SH shadow; add GlassCard with white gradient + 0.5 border + SH_INSET

### Task 2: Rewrite AppButton — 5 variants × 3 sizes

**Files:**
- Modify: `lib/core/widgets/app_button.dart`

**Interfaces:**
- Produces: `AppButton({variant, size, label, onPressed, icon, fullWidth, isLoading})`
- `AppButtonVariant`: primary, secondary, dark, ghost, danger
- `AppButtonSize`: lg, md, sm
- Sizes: lg(vPad 14, hPad 24, fontSize 16, radius 20, iconSize 18), md(vPad 11, hPad 20, fontSize 14, radius 18, iconSize 16), sm(vPad 6, hPad 14, fontSize 10, radius 10, iconSize 12)
- Variants: primary(Y/DARK+SH), secondary(BG3/MUTED), dark(DARK/INV+SH), ghost(transparent/DARK), danger(REDSOFT/#c00)
- All: Manrope 700, ≥44pt hit area (minSize), optional leading icon, fullWidth option, press feedback

### Task 3: Badge + Chip

**Files:**
- Create: `lib/core/widgets/badge.dart`

**Interfaces:**
- Produces: `AppBadge({label, small})` — rounded 9px, Manrope 500/10 (sm 9), pad 3/9 (sm 2/7)
- Produces: `AppChip({label, active, onTap})` — white/DARK or DARK/white(active), 1px border, 5px radius, Manrope 500/11, pad 5/10

### Task 4: StatusPill

**Files:**
- Create: `lib/core/widgets/status_pill.dart`

**Interfaces:**
- Consumes: `statusColor(String)` from `status_colors.dart`
- Produces: `StatusPill({stato})` — AppBadge driven by statusColor(stato)

### Task 5: Avatar

**Files:**
- Create: `lib/core/widgets/avatar.dart`

**Interfaces:**
- Produces: `AppAvatar({name, size})` — initials circle, default size 36, color cycle [Y,#A8DADC,#FFE66D,#06AED5,#F4A261,#FFB200], DARK text, Manrope 700, fontSize size*0.36

### Task 6: KeyVal

**Files:**
- Create: `lib/core/widgets/key_val.dart`

**Interfaces:**
- Produces: `KeyVal({label, value, vertical})` — horizontal: Manrope 700/10 MUTED uppercase label (letterSpacing .3) + Manrope 13 DARK value (right, ellipsis), 10px vertical pad, bottom 1px BL divider. Vertical: label above value(14).

### Task 7: SectionTitle

**Files:**
- Create: `lib/core/widgets/section_title.dart`

**Interfaces:**
- Produces: `SectionTitle({title, action})` — Sora 700/18 DARK, pad 20/19/10 (top/h/bottom), optional right Widget action

### Task 8: AppToggle

**Files:**
- Create: `lib/core/widgets/app_toggle.dart`

**Interfaces:**
- Produces: `AppToggle({value, onChanged})` — 38×22 track, Y(on)/BM(off), 16 white knob, 200ms AnimatedContainer, ≥44pt hit area via GestureDetector

### Task 9: Update widgets.dart barrel

**Files:**
- Modify: `lib/core/widgets/widgets.dart`

**Interfaces:**
- Exports all new widget files

### Task 10: Widget tests

**Files:**
- Create: `test/core/widgets/app_button_test.dart`
- Create: `test/core/widgets/status_pill_test.dart`
- Create: `test/core/widgets/avatar_test.dart`
- Create: `test/core/widgets/app_toggle_test.dart`

**Interfaces:**
- Consumes all widgets above

Tests:
- AppButton: each variant renders, primary has Y bg, dark variant has DARK bg, danger has REDSOFT bg, sm/md/lg sizes via parameter, icon appears when provided, fullWidth stretches width, disabled when onPressed null
- StatusPill: all 13 stati render without error, each finds a Text widget
- Avatar: renders initials correctly (first+last initial), size parameter changes container, color cycles by name hash
- AppToggle: renders off state (BM), tap calls onChanged(true), renders on state (Y)
