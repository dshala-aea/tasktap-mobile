// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

/// TaskTap design-system color tokens (v2 — matches DESIGN-SPEC.md).
/// Token names (Y, DARK, BG1, etc.) are intentional — they match DESIGN-SPEC.md verbatim.
abstract final class AppColors {
  // ── Brand ────────────────────────────────────────────────────────────────

  /// Y — brand yellow #FFF10E.
  static const Color Y = Color(0xFFFFF10E);

  /// YDark — darker yellow #E6D900.
  static const Color YDark = Color(0xFFE6D900);

  /// YSoft — translucent yellow rgba(255,241,14,0.20).
  static const Color YSoft = Color(0x33FFF10E);

  // ── Ink ─────────────────────────────────────────────────────────────────

  /// DARK #363636.
  static const Color DARK = Color(0xFF363636);

  /// CHARCOAL #292929.
  static const Color CHARCOAL = Color(0xFF292929);

  /// FG2 rgb(112,112,112).
  static const Color FG2 = Color(0xFF707070);

  /// MUTED rgb(107,107,107) — secondary text on light surfaces.
  ///
  /// Was `#908F8F`, which measured 3.23:1 on white and 2.88:1 on [BG3] — below the 4.5:1 WCAG AA
  /// floor for normal-size text. It is baked into [AppTextStyles.caption] and `labelSmall` and
  /// used directly in ~97 more places, so that single value was the app's largest source of
  /// unreadable text: nearly every list row's second line. This app is read outdoors, in direct
  /// sun, by someone who is not going to squint at it twice.
  ///
  /// `#6B6B6B` clears AA on both surfaces the app actually uses (5.33:1 on white, 4.76:1 on BG3).
  /// `#707070` — the obvious "reuse FG2" answer — passes on white but still fails at 4.42:1 on
  /// BG3, so it is not enough.
  static const Color MUTED = Color(0xFF6B6B6B);

  /// DIS rgb(180,180,180).
  static const Color DIS = Color(0xFFB4B4B4);

  /// INV rgb(242,242,242).
  static const Color INV = Color(0xFFF2F2F2);

  /// WHITE.
  static const Color WHITE = Color(0xFFFFFFFF);

  // ── Surfaces ─────────────────────────────────────────────────────────────

  /// BG1 rgb(250,250,250).
  static const Color BG1 = Color(0xFFFAFAFA);

  /// BG2 rgb(247,247,247).
  static const Color BG2 = Color(0xFFF7F7F7);

  /// BG3 rgb(242,242,242).
  static const Color BG3 = Color(0xFFF2F2F2);

  /// BG4 rgb(237,237,237).
  static const Color BG4 = Color(0xFFEDEDED);

  // ── Borders ──────────────────────────────────────────────────────────────

  /// BL rgb(242,242,242) — lightest border.
  static const Color BL = Color(0xFFF2F2F2);

  /// BM rgb(227,227,227).
  static const Color BM = Color(0xFFE3E3E3);

  /// BS rgb(217,217,217).
  static const Color BS = Color(0xFFD9D9D9);

  /// DIV rgb(212,212,212) — divider.
  static const Color DIV = Color(0xFFD4D4D4);

  // ── Semantic ─────────────────────────────────────────────────────────────

  /// AMBER rgb(255,178,0).
  static const Color AMBER = Color(0xFFFFB200);

  /// GREEN #4caf50.
  static const Color GREEN = Color(0xFF4CAF50);

  /// BLUE #2563eb.
  static const Color BLUE = Color(0xFF2563EB);

  /// CYAN #06AED5.
  static const Color CYAN = Color(0xFF06AED5);

  /// The one danger red, #D32F2F.
  ///
  /// This was #FF0000 while [error] — documented as "alias for RED" — was #D32F2F, so the app
  /// carried two different reds that each claimed to be the other. They met on screen: a form
  /// validation message in one, the delete icon beside it in the other.
  ///
  /// #D32F2F is the survivor because pure red fails AA on white (4.0:1 against 4.9:1), which put
  /// every destructive label using RED under the floor. [error] now genuinely aliases this.
  static const Color RED = Color(0xFFD32F2F);

  /// REDSOFT rgb(255,209,209).
  static const Color REDSOFT = Color(0xFFFFD1D1);

  // ── Punch clock (theme-invariant) ────────────────────────────────────────
  //
  // The timbratura screens are dark under both themes on purpose — they are read at arm's length
  // in a van cab at 6am and the giant clock is the whole screen. These are the values they need
  // and they do not belong in [AppPalette], which is for tokens that flip.

  /// The ground of the timbratura screens.
  ///
  /// Was written as a bare `Color(0xFF1A1A1A)` in eight places across two files. It happens to
  /// equal the dark palette's `bg2`, which made it look like a token when it is not one: this
  /// surface stays dark when the app is in light mode, so it must not follow the palette.
  static const Color punchGround = Color(0xFF1A1A1A);

  /// The end-shift disc gradient, light stop.
  ///
  /// The punch screens carried `#FF6B6B`/`#CC3333` and `#CC0000` — three more reds on top of the
  /// one [RED] the app had just been consolidated onto, and a different hue family besides, so
  /// "stop" on the clock screen was a visibly different colour from "delete" everywhere else.
  /// These two are [RED] lightened and darkened; they read as the same red because they are.
  static const Color stopLight = Color(0xFFE4564F);

  /// The end-shift disc gradient, dark stop. See [stopLight].
  static const Color stopDark = Color(0xFFA32222);

  // ── Shadows (documented; used via BoxShadow helpers) ─────────────────────

  /// SH — standard card shadow: 0 3px 5.5px rgba(0,0,0,0.10).
  static const List<BoxShadow> SH = [
    BoxShadow(
      color: Color(0x1A000000), // rgba(0,0,0,0.10)
      offset: Offset(0, 3),
      blurRadius: 5.5,
    ),
  ];

  /// SH_INSET — inset shadow: inset 0 2px 4px rgba(0,0,0,0.10).
  /// Flutter doesn't support CSS inset; approximate with inner shadow.
  static const List<BoxShadow> SH_INSET = [
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: -2,
    ),
  ];

  // ── Legacy aliases (keep screens compiling) ───────────────────────────────

  /// Primary brand yellow — alias for [Y].
  static const Color brand = Y;

  /// Foreground on brand yellow — near-black [DARK].
  static const Color onBrand = DARK;

  /// White surface.
  static const Color surface = WHITE;

  /// App background — alias for [BG1].
  static const Color background = BG1;

  /// Surface variant — alias for [BG2].
  static const Color surfaceVariant = BG2;

  /// Default border/outline — alias for [BM].
  static const Color outline = BM;

  /// Primary text — alias for [DARK].
  static const Color textPrimary = DARK;

  /// Secondary text — alias for [FG2].
  static const Color textSecondary = FG2;

  /// Disabled text — alias for [DIS].
  static const Color textDisabled = DIS;

  // ── Legacy status colors (kept for StatusBadge / ReportStato enum) ────────

  /// Bozza bg rgb(245,245,245).
  static const Color statusBozza = Color(0xFFF5F5F5);

  /// Bozza fg #666.
  static const Color onStatusBozza = Color(0xFF666666);

  /// Inviata bg rgb(220,232,255).
  static const Color statusInviato = Color(0xFFDCE8FF);

  /// Inviata fg #1d4ed8.
  static const Color onStatusInviato = Color(0xFF1D4ED8);

  /// Controllato bg AMBER (kept for backward compat).
  static const Color statusControllato = AMBER;

  /// Controllato fg black.
  static const Color onStatusControllato = Color(0xFF000000);

  /// Fatturato / Pagata bg rgb(218,242,224).
  static const Color statusFatturato = Color(0xFFDAF2E0);

  /// Fatturato / Pagata fg #1e7a3a.
  static const Color onStatusFatturato = Color(0xFF1E7A3A);

  /// Annullato bg rgb(255,220,220).
  static const Color statusAnnullato = Color(0xFFFFDCDC);

  /// Annullato fg #a00.
  static const Color onStatusAnnullato = Color(0xFFAA0000);

  // ── Semantic (kept for theme / screens) ───────────────────────────────────

  /// Error — alias for [RED], and now actually one.
  static const Color error = RED;

  /// On-error — white.
  static const Color onError = WHITE;

  /// Success — alias for [GREEN].
  static const Color success = GREEN;

  /// Warning — alias for [AMBER].
  static const Color warning = AMBER;

  /// Info — alias for [BLUE].
  static const Color info = BLUE;
}
