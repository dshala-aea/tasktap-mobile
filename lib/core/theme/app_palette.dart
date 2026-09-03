// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

/// The colour tokens, resolved per theme.
///
/// [AppColors] still holds the raw values and the ones that do not flip (brand accent, the status
/// pairs). What lives here is everything whose meaning depends on whether the app is light or dark.
///
/// Repointed 2026-09-03 for the Il Documento world (see DESIGN.md): every field below now holds
/// its Il Documento value (light and dark), verified via the WCAG relative-luminance contrast
/// formula — see `test/core/theme/app_palette_contrast_test.dart`. Field names are unchanged from
/// the Cassetta palette this replaces, so every `context.colors.X` call site across the app needed
/// zero edits for this repoint.
///
/// ## Why `ink` and `surfaceInverse` exist
///
/// The old palette had `DARK` and `WHITE`, and each was used for two different jobs: `DARK` was
/// both "the colour text is written in" and "the fill of a dark chip"; `WHITE` was both "a card"
/// and "text on top of that dark chip". In a light theme those coincide, so nothing forced the
/// distinction. In a dark theme they move in opposite directions — ink goes light, a card goes
/// dark — so a rename that kept one name for both jobs would have inverted every chip in the app.
///
/// Hence four names where there were two — a distinction the Il Documento repoint above kept.
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
    required this.labelCard,
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

  /// Text on top of [surfaceInverse] or the brand colour. Was `AppColors.WHITE` used as ink; now
  /// `AppColors.INV` (the same near-white paper tone as [surface]/[labelCard]), since Il
  /// Documento's `surfaceInverse` is still a dark fill in light mode and needs a light ink on top
  /// of it — same job, new value.
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

  /// Card shadow. Empty in both themes — DESIGN.md bans floating-card shadows ("no floating
  /// cards... when in doubt, draw a line, not a box"). A hairline border does the job a shadow
  /// used to.
  final List<BoxShadow> shadow;

  /// The pressed/inset shading on a card. Empty for the same reason as [shadow].
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

  /// What sits on the brand accent. The accent does not flip — it is the brand — so this stays
  /// the same value in both themes.
  ///
  /// Was dark ink in Cassetta: safety orange was too light for white text to clear AA. Stamp red
  /// (Il Documento's accent) is darker/more saturated — white-on-stamp clears 5.37:1 — so this is
  /// near-white here instead, matching `AppButton`'s primary variant, which already hardcodes
  /// `Colors.white` as its foreground.
  final Color brandOn;

  // ── Rack materials ────────────────────────────────────────────────────────
  //
  // The van. This is the only warm colour in the palette, and that is the point: every neutral
  // above is a true grey, so the label card reads as *material* against the app's chrome rather
  // than as another step on the background ramp. railSurface/railHighlight (the anodized rail
  // extrusion), silhouette (a shadow board's cut line), and ledge (a cell's graphite pull bar)
  // were this group's other members — all retired with the van-racking metaphor they belonged to;
  // see rack.dart, empty_state.dart, and app_fab.dart's own doc comments.

  /// The printed card in the label window: the surface a cell's content is actually read off.
  ///
  /// Equals [surface] in each theme for the Il Documento world — the warm/neutral distinction
  /// that motivated a separate value no longer applies, since `surface`/`bg1` are already warm
  /// paper tones here (`#FBF9F4`/`#F1EEE7`), not neutral grey like Cassetta's `#FFFFFF`/`#FAFAFA`.
  /// Kept as its own field rather than folded into [surface] because the two still name different
  /// jobs — a sheet/input vs. a cell — even though they currently share a value.
  final Color labelCard;

  // ── Instances ─────────────────────────────────────────────────────────────

  /// The light palette. Il Documento's paper-and-ink world (see DESIGN.md).
  ///
  /// Every value here is either verified via the WCAG relative-luminance contrast formula (see
  /// `test/core/theme/app_palette_contrast_test.dart`) or, for the semantic status colours, kept
  /// unchanged from Cassetta — status hues are not part of DESIGN.md's ink/accent/surface system.
  ///
  /// [inkInverse] is `AppColors.INV` (`#FBF9F4`, the same near-white as [surface]), not the darker
  /// value a literal "ink" reading would suggest: it is text laid on top of [surfaceInverse], which
  /// is a *dark* fill in light mode (it deliberately equals [ink]'s own value), so the ink on top
  /// of it has to stay light. Confirmed against two independent checks: `AppColors.INV` is
  /// documented as the Il Documento repoint of the old `inkInverse`/`WHITE` role, and this is the
  /// only value that keeps both "inverse ink reads on the inverse surface" and "inkInverse flips,
  /// so it cannot serve a surface that does not" (`app_palette_test.dart`) passing — the alternative
  /// (reusing [ink]'s own dark value) collapses [inkInverse] onto [surfaceInverse] and produces
  /// invisible text on `AppButton.dark`.
  static const light = AppPalette(
    ink: Color(0xFF22252E),
    inkMuted: Color(0xFF5E6878),
    inkFaint: Color(0xFF5E6878),
    inkDisabled: Color(0xFFB1ACA0),
    inkInverse: Color(0xFFFBF9F4),
    surface: Color(0xFFFBF9F4),
    surfaceInverse: Color(0xFF22252E),
    bg1: Color(0xFFF1EEE7),
    bg2: Color(0xFFF1EEE7),
    bg3: Color(0xFFEDEAE3),
    bg4: Color(0xFFEDEAE3),
    borderLight: Color(0xFFDED9CE),
    borderMedium: Color(0xFFDED9CE),
    borderStrong: Color(0xFFDED9CE),
    divider: Color(0xFFDED9CE),
    // Empty — DESIGN.md bans floating-card shadows ("draw a line, not a box").
    shadow: [],
    shadowInset: [],
    amber: Color(0xFFFFB200),
    green: Color(0xFF4CAF50),
    blue: Color(0xFF2563EB),
    cyan: Color(0xFF06AED5),
    red: Color(0xFFD32F2F),
    redSoft: Color(0xFFFFD1D1),
    brandOn: Color(0xFFFBF9F4),
    labelCard: Color(0xFFFBF9F4),
  );

  /// The dark palette.
  ///
  /// Not black. This app is held in a van cab and a plant room, often while walking, and pure
  /// #000 with light text smears badly on OLED during motion; a near-black grey does not. The
  /// surfaces still step apart (`bg1` → `bg2` → `bg3` → `bg4`) so a raised layer reads as raised
  /// without a shadow, since DESIGN.md bans card shadows outright rather than just needing a
  /// heavier one here.
  ///
  /// DESIGN.md defines no dark theme. Each ink-role value below is the light palette's own value
  /// lightened until it clears AA on the new [bg2] (`#1E1F24`), same hue family, same derivation
  /// this file already used for Cassetta's dark palette — not a second design language:
  ///   ink       `#EEECE8` → 13.94:1
  ///   inkMuted  `#8D96A5` →  5.51:1  (the light theme's `#5E6878` would be under 3:1 here)
  ///   inkFaint  `#8D96A5` →  5.51:1  (consolidated onto [inkMuted]'s value, same as light)
  ///   blue      `#7AA7F5` →  6.8:1   (unchanged from Cassetta's dark value)
  ///   green     `#6FCF74` →  8.2:1   (unchanged)
  ///   red       `#F0736E` →  6.4:1   (unchanged)
  ///   amber     `#FFC44D` → 10.5:1   (unchanged)
  ///
  /// Known residual: stamp red used directly as *text* (not a filled chip with white text on top)
  /// only clears 2.91:1 on this [bg2] — below AA. Not currently reachable (the one permanently-dark
  /// surface, punch-clock, is out of scope for this repoint) but would matter if a future
  /// dark-mode screen ever renders the accent as text colour rather than a filled chip.
  static const dark = AppPalette(
    ink: Color(0xFFEEECE8),
    inkMuted: Color(0xFF8D96A5),
    inkFaint: Color(0xFF8D96A5),
    inkDisabled: Color(0xFF6B6B6B),
    inkInverse: Color(0xFF1E1F24),
    surface: Color(0xFF1E1F24),
    surfaceInverse: Color(0xFFEEECE8),
    bg1: Color(0xFF17181C),
    bg2: Color(0xFF1E1F24),
    bg3: Color(0xFF272930),
    bg4: Color(0xFF30333B),
    borderLight: Color(0xFF383B42),
    borderMedium: Color(0xFF383B42),
    borderStrong: Color(0xFF383B42),
    divider: Color(0xFF383B42),
    // Empty — DESIGN.md bans floating-card shadows ("draw a line, not a box").
    shadow: [],
    shadowInset: [],
    amber: Color(0xFFFFC44D),
    green: Color(0xFF6FCF74),
    blue: Color(0xFF7AA7F5),
    cyan: Color(0xFF4DD0E8),
    red: Color(0xFFF0736E),
    // A tint of the dark red rather than the light theme's pastel, which would glare here.
    redSoft: Color(0xFF4A2320),
    brandOn: Color(0xFFFBF9F4),
    labelCard: Color(0xFF1E1F24),
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
    Color? labelCard,
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
      labelCard: labelCard ?? this.labelCard,
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
      labelCard: c(labelCard, other.labelCard),
    );
  }
}

/// `context.colors.ink` — the palette for the theme this widget is under.
extension AppPaletteContext on BuildContext {
  /// Falls back to [AppPalette.light] rather than throwing when the extension is absent.
  ///
  /// A widget test that pumps a bare `MaterialApp` registers no extension, and a screen that
  /// renders in the wrong colours is a better failure there than one that cannot render at all.
  AppPalette get colors => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
