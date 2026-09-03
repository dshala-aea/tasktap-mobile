// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

/// TaskTap design-system color tokens (v2 — matches DESIGN-SPEC.md).
/// Token names (Y, DARK, BG1, etc.) are intentional — they match DESIGN-SPEC.md verbatim.
abstract final class AppColors {
  // ── Brand ────────────────────────────────────────────────────────────────
  //
  // Recolored 2026-08-23 for the Cassetta world (see PRODUCT.md Brand Commitments):
  // safety orange replaces the old brand yellow. Token names kept as-is — Y/YDark/YSoft are
  // used at ~120 call sites as "the one accent", and repointing what they resolve to carries the
  // whole app's yellow-scarcity discipline over to the new hue without touching those call sites.

  /// Y — stamp red #C03221. The one accent: primary action, attention-required, selected.
  ///
  /// Repointed 2026-09-03 for the Il Documento world (see DESIGN.md) — Cassetta's safety orange
  /// gives way to a stamp/seal red, the one recurring color mark of a paper-and-ink system.
  /// `#C03221` clears 4.87:1 against `BG1` (desk, `#F1EEE7`) and 5.37:1 against `SHEET`
  /// (`#FBF9F4`) — both above the 4.5:1 AA floor this app holds itself to (see PRODUCT.md
  /// Accessibility & Inclusion). Values verified via the WCAG relative-luminance formula.
  static const Color Y = Color(0xFFC03221);

  /// YDark — darker stamp red, for pressed/gradient-adjacent states.
  static const Color YDark = Color(0xFF9D2A1B);

  /// YSoft — translucent stamp red rgba(192,50,33,0.20).
  static const Color YSoft = Color(0x33C03221);

  // ── Ink ─────────────────────────────────────────────────────────────────

  /// DARK #22252E — Il Documento's carbon ink.
  static const Color DARK = Color(0xFF22252E);

  /// CHARCOAL — consolidated onto the same carbon ink as [DARK] for the Il Documento world (see
  /// DESIGN.md): one ink, not a separate case-shell shade. 13.21:1 on `BG1`, 14.55:1 on `SHEET`.
  static const Color CHARCOAL = Color(0xFF22252E);

  /// FG2 — consolidated onto the same value as [MUTED] for the Il Documento world (see
  /// DESIGN.md): one secondary-text value, not a separate step. 4.86:1 on `BG1`, 5.35:1 on
  /// `SHEET`.
  static const Color FG2 = Color(0xFF5E6878);

  /// MUTED — secondary text on light surfaces, Il Documento's slate.
  ///
  /// Repointed 2026-09-03 for the Il Documento world (see DESIGN.md). `#5E6878` clears AA on
  /// both surfaces the app actually uses (4.86:1 on `BG1`/desk, 5.35:1 on `SHEET`). This app is
  /// read outdoors, in direct sun, by someone who is not going to squint at it twice.
  static const Color MUTED = Color(0xFF5E6878);

  /// DIS rgb(177,172,160) — disabled text is AA-exempt, no contrast floor applies.
  static const Color DIS = Color(0xFFB1ACA0);

  /// INV rgb(251,249,244) — repointed to [SHEET]'s value for the Il Documento world.
  static const Color INV = Color(0xFFFBF9F4);

  /// WHITE.
  static const Color WHITE = Color(0xFFFFFFFF);

  // ── Surfaces ─────────────────────────────────────────────────────────────

  /// BG1 rgb(241,238,231) — the desk. DESIGN.md's page ground for the Il Documento world.
  static const Color BG1 = Color(0xFFF1EEE7);

  /// BG2 — consolidated onto [BG1] for the Il Documento world (see DESIGN.md): the old four-step
  /// background scale collapses onto DESIGN.md's two named surfaces (desk/sheet).
  static const Color BG2 = Color(0xFFF1EEE7);

  /// BG3 rgb(237,234,227) — the muted fill. DESIGN.md's one named `--muted` (input/muted fill).
  /// 12.74:1 against ink.
  static const Color BG3 = Color(0xFFEDEAE3);

  /// BG4 — consolidated onto [BG3] for the Il Documento world (see DESIGN.md): same flattening
  /// as [BG2]/[BG1].
  static const Color BG4 = Color(0xFFEDEAE3);

  /// The sheet surface — a card, a form panel, an input fill's raised state. Distinct from [BG1]
  /// (the page ground/desk) — DESIGN.md's two named surfaces, not previously distinguished in
  /// this token set (BG1-4 were four steps of the same ground).
  static const Color SHEET = Color(0xFFFBF9F4);

  // ── Borders ──────────────────────────────────────────────────────────────
  //
  // BL/BM/BS/DIV consolidate onto one hairline value for the Il Documento world (see DESIGN.md):
  // "hairlines do the work... when in doubt, draw a line, not a box" — the old three-step border
  // scale doesn't have a DESIGN.md equivalent, so all four collapse onto its one named `--border`.

  /// BL rgb(222,217,206) — the one hairline border/divider value.
  static const Color BL = Color(0xFFDED9CE);

  /// BM — consolidated onto the same hairline value as [BL].
  static const Color BM = Color(0xFFDED9CE);

  /// BS — consolidated onto the same hairline value as [BL].
  static const Color BS = Color(0xFFDED9CE);

  /// DIV — consolidated onto the same hairline value as [BL]. Divider.
  static const Color DIV = Color(0xFFDED9CE);

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

  // ── Ink for surfaces that are dark under BOTH themes ─────────────────────
  //
  // The app keeps producing the same bug: a CHARCOAL bar, hero or panel — dark whatever the theme
  // — painted with `context.colors.inkInverse` or `inkMuted`, both of which flip. Four separate
  // sites had it (the dashboard hero's client line, the ticket form's AppBar, the rapportino
  // wizard's AppBar and signature dialog, the Totale ore card), and the totals card managed to be
  // wrong in *both* directions at once: `inkMuted` measures 1.9:1 on CHARCOAL in light mode, and
  // `inkInverse` goes near-black in dark mode.
  //
  // The fix is to stop reaching for a flipping token on a surface that does not flip. These two
  // do not flip either, and their names say what they are for.

  /// Primary text on a permanently dark surface. 15.9:1 on [CHARCOAL].
  static const Color onDark = WHITE;

  /// Secondary text on a permanently dark surface.
  ///
  /// White at 75%, which lands at 9.4:1 on [CHARCOAL] — clearly subordinate to [onDark] and still
  /// far above the floor. The muted greys are the trap here: they are tuned against the light
  /// theme's own backgrounds, not against a dark panel sitting inside it.
  static const Color onDarkMuted = Color(0xBFFFFFFF);

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
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 4, spreadRadius: -2),
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
