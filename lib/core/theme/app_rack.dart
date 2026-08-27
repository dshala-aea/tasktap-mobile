import 'package:flutter/widgets.dart';

/// Shape and motion tokens for [RackCell] — the one piece of the van-racking design language
/// still in use, by `AppCard` and the pre-Vetro `CompartmentTile`. The rail, the cell-pitch
/// spacing, and the shadow-board silhouette that used to live alongside these were retired with
/// the rest of that metaphor (see `rack.dart`/`empty_state.dart`'s own doc comments); [ListRow],
/// their highest-traffic consumer, no longer uses any of this file at all.
///
/// [AppPalette] owns what things are *made of*; this owns what shape they are and how they move.
///
/// ## Corner radius: settled at the validated number, not re-litigated per world
///
/// [cellRadius] tried 6 for a day under the "die-cut compartment" reading of Cassetta — reverted
/// on direct user feedback that a 6px radius at this cell size reads as dated and over-square, not
/// machined. 12 is where this session's own competitor research (Linear, Vercel, Stripe, Notion —
/// see the design-token audit this session ran) converged independently of any one world's
/// metaphor: it is not "the old Figma number" or "the Cassetta number," it is the number four
/// separate references landed on for a card at this density. Stop moving it per redirection.
abstract final class AppRack {
  // ── Cells ─────────────────────────────────────────────────────────────────

  /// Minimum height of a cell.
  ///
  /// 64, above the 48dp Android floor rather than at it: the target here is a gloved thumb on a
  /// phone braced against a van door, and the extra 16dp is the difference between a tap and a
  /// second tap.
  static const double cellMinHeight = 64;

  /// Corner radius of a cell on its three free edges. See the class doc — this is the validated
  /// number, not a per-world value.
  static const double cellRadius = 12;

  /// Corner radius on the rail edge. Square — the cell is butted against the extrusion. Structural,
  /// not a style knob: does not move when [cellRadius] does.
  static const double cellRadiusFlush = 0;

  /// Radius of a compartment *inside* a cell (a material line, an hour tile, a photo thumb — also
  /// what `AppChip`'s filter pills use). Scales with [cellRadius]: half of it, so a compartment
  /// always reads as nested inside its cell rather than competing with the cell's own corner.
  static const double insetRadius = cellRadius / 1.5;

  /// Standard shape for a cell attached to the rail.
  static const BorderRadius cellShape = BorderRadius.only(
    topLeft: Radius.circular(cellRadiusFlush),
    bottomLeft: Radius.circular(cellRadiusFlush),
    topRight: Radius.circular(cellRadius),
    bottomRight: Radius.circular(cellRadius),
  );

  /// Shape for a cell that is *not* on a rail — a sheet, a dialog, a standalone panel.
  static const BorderRadius freeShape = BorderRadius.all(Radius.circular(cellRadius));

  /// Shape for a compartment inside a cell.
  static const BorderRadius insetShape = BorderRadius.all(Radius.circular(insetRadius));

  /// Inner padding of a cell.
  static const EdgeInsets cellPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);

  // ── The load strap: clearance for the floating nav ────────────────────────

  /// How much room the floating nav pill occupies above the safe area.
  ///
  /// 18 bottom margin + 6 pill padding + 44 tab + 6 pill padding = 74. Every one of those numbers
  /// lives in `AppBottomNav`, and none of them lived anywhere a screen could read.
  ///
  /// The nav belongs to the *shell's* Scaffold, not to the screen inside it, so a screen's own
  /// FloatingActionButton has no idea the pill is there and is placed underneath it. Screens were
  /// compensating with hand-picked bottom padding — 100, 120, 60, 40, 32, and on nine detail
  /// screens just 16, which is not enough to clear anything. Hence buttons hidden under the nav.
  ///
  /// Use `context.navClearance`, which adds the device's own bottom inset to this.
  static const double navBarHeight = 74;

  /// Breathing room between the last cell and the nav, so content does not end flush against it.
  static const double navGap = 12;

  // ── Motion ────────────────────────────────────────────────────────────────

  /// `AppBottomNav`'s active-tab transition — the last consumer of this file's motion tokens.
  /// `RackCell` itself never animates.
  static const Duration drawerOut = Duration(milliseconds: 180);

  /// The curve for anything opening or arriving. Exponential ease-out, firm stop, no overshoot.
  static const Curve slideOut = Curves.easeOutCubic;
}

/// Room to leave at the bottom of a screen that sits under the floating nav.
///
/// `MediaQuery.viewPadding.bottom` rather than `padding.bottom`: the latter is zeroed out while a
/// keyboard is open, which would collapse the clearance at exactly the moment a form is being
/// filled in.
extension NavClearance on BuildContext {
  double get navClearance =>
      MediaQuery.viewPaddingOf(this).bottom + AppRack.navBarHeight + AppRack.navGap;
}
