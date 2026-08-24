import 'package:flutter/widgets.dart';

/// The rack: the geometry and motion of the van-racking world.
///
/// [AppPalette] owns what things are *made of*; this owns what shape they are and how they move.
/// The two are split because material flips with the theme and geometry never does — a drawer is
/// the same drawer with the van doors shut.
///
/// ## The grammar, in three rules
///
/// 1. **Everything hangs off one rail.** A vertical alu extrusion runs down the leading edge of a
///    scrollable surface. Cells attach to it; nothing floats free of it. The rail is what makes a
///    list of six rows read as one rack rather than six cards.
/// 2. **Cells sit on a constant pitch.** [cellGap] never varies inside one rack, whatever a cell
///    contains. Density comes from what is *in* a cell, never from crowding the cells together.
/// 3. **Absence is drawn.** An empty slot is a cut silhouette ([silhouetteDash]), not whitespace.
///    A technician reading their own rack sees the missing tool; so does this app.
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
  // ── The rail ──────────────────────────────────────────────────────────────

  /// Width of the alu extrusion running down the leading edge.
  ///
  /// 4, not a hairline. At 1–2dp it reads as a stray divider in direct sun; at 4 it reads as
  /// structure. It is the single most load-bearing mark in the world and the one a low-quality
  /// screenshot loses first.
  static const double railWidth = 4;

  /// The machined highlight down the rail's outer edge. One device pixel at most densities.
  static const double railHighlight = 1;

  /// Gap from the screen's leading edge to the rail.
  ///
  /// Deliberately smaller than the page gutter: the rail is chrome bolted to the side of the load
  /// bay, not content, so it sits outside the reading column.
  static const double railInset = 8;

  /// Gap from the rail to the leading edge of a cell.
  static const double railToCell = 7;

  /// Total leading offset a cell's content sits at: [railInset] + [railWidth] + [railToCell] = 19,
  /// which lands exactly on `AppSpacing.pagePadding`.
  ///
  /// This is the reason the rail costs nothing: it is drawn inside the gutter ninety screens
  /// already use, so adopting it moves no content sideways.
  static const double railColumn = railInset + railWidth + railToCell;

  // ── Cells ─────────────────────────────────────────────────────────────────

  /// Vertical gap between two cells on the rail. Never varies within one rack.
  static const double cellGap = 8;

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

  /// Height of the label strip at the top of a cell — the printed card in its window.
  static const double labelStripHeight = 20;

  /// Inner padding of a cell.
  static const EdgeInsets cellPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);

  /// Inner padding of a cell that carries a label strip (the strip supplies its own top space).
  static const EdgeInsets cellPaddingLabelled = EdgeInsets.fromLTRB(12, 6, 12, 10);

  // ── Shadow board ──────────────────────────────────────────────────────────

  /// Stroke weight of a cut silhouette.
  static const double silhouetteStroke = 1.5;

  /// Dash pattern of a cut silhouette: [dash, gap].
  ///
  /// A long dash and a short gap. A fine dotted line disappears at arm's length outdoors, which
  /// would turn "the thing that belongs here is missing" into "nothing is here" — the one
  /// distinction this app exists to preserve.
  static const List<double> silhouetteDash = [6, 4];

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
  //
  // A drawer runs out on its slides and stops against a detent. It does not bounce, and it does
  // not drift to a halt. Every transition in the app is that one movement at a different length.

  /// A cell opening — expanding in place, a sheet rising, a step advancing.
  static const Duration drawerOut = Duration(milliseconds: 180);

  /// A cell closing. Shorter than opening: reversing a movement you initiated should not make you
  /// wait for it.
  static const Duration drawerIn = Duration(milliseconds: 140);

  /// A state change inside a cell — the strap landing, a status flipping, a value updating.
  static const Duration detent = Duration(milliseconds: 120);

  /// The curve for anything opening or arriving. Exponential ease-out, firm stop, no overshoot.
  static const Curve slideOut = Curves.easeOutCubic;

  /// The curve for anything closing or leaving.
  static const Curve slideIn = Curves.easeInCubic;
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
