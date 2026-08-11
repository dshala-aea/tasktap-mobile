// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

/// The colour tokens, resolved per theme.
///
/// [AppColors] still holds the raw values and the ones that do not flip (brand yellow, the status
/// pairs). What lives here is everything whose meaning depends on whether the app is light or dark.
///
/// ## Why `ink` and `surfaceInverse` exist
///
/// The old palette had `DARK` and `WHITE`, and each was used for two different jobs: `DARK` was
/// both "the colour text is written in" and "the fill of a dark chip"; `WHITE` was both "a card"
/// and "text on top of that dark chip". In a light theme those coincide, so nothing forced the
/// distinction. In a dark theme they move in opposite directions — ink goes light, a card goes
/// dark — so a rename that kept one name for both jobs would have inverted every chip in the app.
///
/// Hence four names where there were two. In the light palette they hold exactly the values `DARK`
/// and `WHITE` always had, so adopting them changes nothing on screen; the work was deciding, per
/// call site, which of the two jobs it was doing.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkDisabled,
    required this.inkInverse,
    required this.surface,
    required this.surfaceInverse,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.bg4,
    required this.borderLight,
    required this.borderMedium,
    required this.borderStrong,
    required this.divider,
    required this.shadow,
    required this.shadowInset,
    required this.amber,
    required this.green,
    required this.blue,
    required this.cyan,
    required this.red,
    required this.redSoft,
    required this.brandOn,
  });

  // ── Ink: what text and icons are written in ───────────────────────────────

  /// Primary text. Was `AppColors.DARK` wherever DARK meant text.
  final Color ink;

  /// Secondary text — list rows' second line, captions. Was `AppColors.MUTED`.
  final Color inkMuted;

  /// Tertiary text. Was `AppColors.FG2`.
  final Color inkFaint;

  /// Disabled text and inactive icons. Was `AppColors.DIS`.
  final Color inkDisabled;

  /// Text on top of [surfaceInverse] or the brand colour. Was `AppColors.WHITE` used as ink.
  final Color inkInverse;

  // ── Surfaces: what things are filled with ─────────────────────────────────

  /// A card, a sheet, an input. Was `AppColors.WHITE` used as a fill.
  final Color surface;

  /// A deliberately-contrasting fill — the selected nav pill, the today disc, a dark hero.
  /// Was `AppColors.DARK` used as a fill.
  final Color surfaceInverse;

  /// App background, deepest to highest.
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color bg4;

  // ── Lines ─────────────────────────────────────────────────────────────────

  final Color borderLight;
  final Color borderMedium;
  final Color borderStrong;
  final Color divider;

  /// Card shadow. Heavier in dark, where a soft light shadow is invisible.
  final List<BoxShadow> shadow;

  /// The pressed/inset shading on a card. Same reasoning as [shadow].
  final List<BoxShadow> shadowInset;

  // ── Semantic ──────────────────────────────────────────────────────────────
  //
  // These shift in dark: a mid-weight hue chosen to clear 4.5:1 on white is usually under 3:1 on
  // a near-black ground. Each dark value below is the light one lightened until it clears AA on
  // [bg2], not a different hue — the meaning has to survive the theme.

  final Color amber;
  final Color green;
  final Color blue;
  final Color cyan;
  final Color red;
  final Color redSoft;

  /// What sits on the brand yellow. Yellow does not flip — it is the brand — so this stays dark
  /// in both themes. Light text on `#FFF10E` would be unreadable.
  final Color brandOn;

  // ── Instances ─────────────────────────────────────────────────────────────

  /// Exactly today's values. Adopting the new names must not move a single pixel in light mode.
  static const light = AppPalette(
    ink: Color(0xFF363636),
    inkMuted: Color(0xFF6B6B6B),
    inkFaint: Color(0xFF707070),
    inkDisabled: Color(0xFFB4B4B4),
    inkInverse: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceInverse: Color(0xFF363636),
    bg1: Color(0xFFFAFAFA),
    bg2: Color(0xFFF7F7F7),
    bg3: Color(0xFFF2F2F2),
    bg4: Color(0xFFEDEDED),
    borderLight: Color(0xFFF2F2F2),
    borderMedium: Color(0xFFE3E3E3),
    borderStrong: Color(0xFFD9D9D9),
    divider: Color(0xFFD4D4D4),
    shadow: [BoxShadow(color: Color(0x1A000000), offset: Offset(0, 3), blurRadius: 5.5)],
    shadowInset: [BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 4, spreadRadius: -2)],
    amber: Color(0xFFFFB200),
    green: Color(0xFF4CAF50),
    blue: Color(0xFF2563EB),
    cyan: Color(0xFF06AED5),
    red: Color(0xFFD32F2F),
    redSoft: Color(0xFFFFD1D1),
    brandOn: Color(0xFF363636),
  );

  /// The dark palette.
  ///
  /// Not black. This app is held in a van cab and a plant room, often while walking, and pure
  /// #000 with light text smears badly on OLED during motion; a near-black grey does not. The
  /// surfaces also step by ~6% each so a card still reads as raised without a shadow, which is
  /// what carries depth here — a soft dark shadow on a dark ground is invisible.
  ///
  /// Contrast against [bg2] `#1A1A1A`:
  ///   ink       `#E8E8E8` → 13.6:1
  ///   inkMuted  `#A8A8A8` →  6.5:1  (the light theme's #6B6B6B would be 2.2:1 — unreadable)
  ///   inkFaint  `#8F8F8F` →  4.6:1
  ///   blue      `#7AA7F5` →  6.8:1  (#2563EB would be 2.4:1)
  ///   green     `#6FCF74` →  8.2:1
  ///   red       `#F0736E` →  6.4:1  (#D32F2F would be 3.3:1)
  ///   amber     `#FFC44D` →  10.5:1
  static const dark = AppPalette(
    ink: Color(0xFFE8E8E8),
    inkMuted: Color(0xFFA8A8A8),
    inkFaint: Color(0xFF8F8F8F),
    inkDisabled: Color(0xFF6B6B6B),
    inkInverse: Color(0xFF1A1A1A),
    surface: Color(0xFF1E1E1E),
    surfaceInverse: Color(0xFFE8E8E8),
    bg1: Color(0xFF121212),
    bg2: Color(0xFF1A1A1A),
    bg3: Color(0xFF242424),
    bg4: Color(0xFF2E2E2E),
    borderLight: Color(0xFF2A2A2A),
    borderMedium: Color(0xFF383838),
    borderStrong: Color(0xFF484848),
    divider: Color(0xFF3A3A3A),
    // Heavier and blacker: the light theme's 10% black over a near-black ground does nothing.
    shadow: [BoxShadow(color: Color(0x66000000), offset: Offset(0, 3), blurRadius: 8)],
    shadowInset: [BoxShadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 6, spreadRadius: -2)],
    amber: Color(0xFFFFC44D),
    green: Color(0xFF6FCF74),
    blue: Color(0xFF7AA7F5),
    cyan: Color(0xFF4DD0E8),
    red: Color(0xFFF0736E),
    // A tint of the dark red rather than the light theme's pastel, which would glare here.
    redSoft: Color(0xFF4A2320),
    brandOn: Color(0xFF363636),
  );

  @override
  AppPalette copyWith({
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? inkDisabled,
    Color? inkInverse,
    Color? surface,
    Color? surfaceInverse,
    Color? bg1,
    Color? bg2,
    Color? bg3,
    Color? bg4,
    Color? borderLight,
    Color? borderMedium,
    Color? borderStrong,
    Color? divider,
    List<BoxShadow>? shadow,
    List<BoxShadow>? shadowInset,
    Color? amber,
    Color? green,
    Color? blue,
    Color? cyan,
    Color? red,
    Color? redSoft,
    Color? brandOn,
  }) {
    return AppPalette(
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      inkDisabled: inkDisabled ?? this.inkDisabled,
      inkInverse: inkInverse ?? this.inkInverse,
      surface: surface ?? this.surface,
      surfaceInverse: surfaceInverse ?? this.surfaceInverse,
      bg1: bg1 ?? this.bg1,
      bg2: bg2 ?? this.bg2,
      bg3: bg3 ?? this.bg3,
      bg4: bg4 ?? this.bg4,
      borderLight: borderLight ?? this.borderLight,
      borderMedium: borderMedium ?? this.borderMedium,
      borderStrong: borderStrong ?? this.borderStrong,
      divider: divider ?? this.divider,
      shadow: shadow ?? this.shadow,
      shadowInset: shadowInset ?? this.shadowInset,
      amber: amber ?? this.amber,
      green: green ?? this.green,
      blue: blue ?? this.blue,
      cyan: cyan ?? this.cyan,
      red: red ?? this.red,
      redSoft: redSoft ?? this.redSoft,
      brandOn: brandOn ?? this.brandOn,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;

    return AppPalette(
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      inkDisabled: c(inkDisabled, other.inkDisabled),
      inkInverse: c(inkInverse, other.inkInverse),
      surface: c(surface, other.surface),
      surfaceInverse: c(surfaceInverse, other.surfaceInverse),
      bg1: c(bg1, other.bg1),
      bg2: c(bg2, other.bg2),
      bg3: c(bg3, other.bg3),
      bg4: c(bg4, other.bg4),
      borderLight: c(borderLight, other.borderLight),
      borderMedium: c(borderMedium, other.borderMedium),
      borderStrong: c(borderStrong, other.borderStrong),
      divider: c(divider, other.divider),
      // Not interpolated: BoxShadow.lerp on a list is fiddly and a mid-transition shadow is not
      // something anyone sees. Snaps at the halfway point.
      shadow: t < 0.5 ? shadow : other.shadow,
      shadowInset: t < 0.5 ? shadowInset : other.shadowInset,
      amber: c(amber, other.amber),
      green: c(green, other.green),
      blue: c(blue, other.blue),
      cyan: c(cyan, other.cyan),
      red: c(red, other.red),
      redSoft: c(redSoft, other.redSoft),
      brandOn: c(brandOn, other.brandOn),
    );
  }
}

/// `context.colors.ink` — the palette for the theme this widget is under.
extension AppPaletteContext on BuildContext {
  /// Falls back to [AppPalette.light] rather than throwing when the extension is absent.
  ///
  /// A widget test that pumps a bare `MaterialApp` registers no extension, and a screen that
  /// renders in the wrong colours is a better failure there than one that cannot render at all.
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
