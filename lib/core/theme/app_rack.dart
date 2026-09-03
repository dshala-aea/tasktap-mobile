import 'package:flutter/widgets.dart';

/// Corner-radius tokens shared across the app, and the floating-nav clearance math.
///
/// Was the van-racking design language's own geometry file — the rail, the cell-pitch spacing,
/// the shadow-board silhouette, and `RackCell` (the drawer-front cell they were all sized for)
/// were retired along with that metaphor (see `rack.dart`/`empty_state.dart`'s own doc comments).
/// [cellRadius]/[insetRadius]/[freeShape]/[insetShape] outlived it: plain corner-radius values
/// used throughout the app independent of any one component, not specific to a cell that no
/// longer exists.
///
/// ## Corner radius
///
/// 2px — DESIGN.md's literal "near-square, paper" radius. See the Il Documento restyle plan's
/// Global Constraints for why the app's earlier 6px rejection (under Cassetta's machined-metal
/// reading) doesn't apply here (different visual premise — square reads as a form sheet, not a
/// manufacturing defect).
abstract final class AppRack {
  // ── Corner radius ─────────────────────────────────────────────────────────

  /// The app's standard corner radius. See the class doc.
  static const double cellRadius = 2;

  /// Radius of a compartment *inside* a larger container (a material line, an hour tile, a photo
  /// thumb — also what `AppChip`'s filter pills use). Scales with [cellRadius]: half of it, so a
  /// compartment always reads as nested inside its container rather than competing with its
  /// corner.
  static const double insetRadius = cellRadius / 1.5;

  /// [cellRadius] on all four corners — a sheet, a dialog, a standalone panel.
  static const BorderRadius freeShape = BorderRadius.all(Radius.circular(cellRadius));

  /// [insetRadius] on all four corners — a compartment nested inside a larger container.
  static const BorderRadius insetShape = BorderRadius.all(Radius.circular(insetRadius));

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

/// Bottom clearance for a FAB on a route the shell's floating nav never reaches — every
/// `parentNavigatorKey: rootNavigatorKey` detail screen (see `app_router.dart`'s own comment on
/// why those are full-screen). Nine of them borrowed [NavClearance.navClearance] instead, which
/// reserves the pill's own 74px even though it is never drawn there — the FAB floated in a dead
/// gap well clear of the screen edge. Just the device's own inset plus a standard Material margin.
extension FabSafeBottom on BuildContext {
  double get fabSafeBottom => MediaQuery.viewPaddingOf(this).bottom + 16;
}
