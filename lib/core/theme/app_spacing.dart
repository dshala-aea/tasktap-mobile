import 'app_rack.dart';

/// TaskTap spacing scale (4 pt base).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard page horizontal padding — the gutter the screens actually use.
  ///
  /// 19, not `base`. Roughly ninety `EdgeInsets` across `lib/features` write a literal 19 for the
  /// page gutter, so the token claiming 16 described nothing that ships: anything adopting it
  /// would have stepped 3dp out of line with every neighbour. Correcting the token rather than
  /// re-gutting ninety screens keeps the app looking the way it looks and puts the next change in
  /// one place.
  ///
  /// Off the 4pt scale on purpose, and the only member that is. Nothing else should be.
  static const double pagePadding = 19;

  // ── Corner language ───────────────────────────────────────────────────────
  //
  // These were 12 / 10 / 10 — the moulded rounded-card idiom every app in this category ships.
  // The rack is machined, not moulded, so they now delegate to [AppRack]. They stay here as
  // aliases rather than being deleted because the theme and a handful of screens reference them
  // by these names, and one edit to the token layer was cheaper and safer than nine to the theme.
  //
  // The floating pill nav is the deliberate exception and keeps its own large radius: it is the
  // load strap across the bottom of the bay, a different object, and a pinned brand commitment.

  /// A cell — the app's container. See [AppRack.cellRadius].
  static const double cardRadius = AppRack.cellRadius;

  /// A control. Same as a cell: a button is a cell you can press.
  static const double buttonRadius = AppRack.cellRadius;

  /// A compartment inside a cell — an input, a material line, an hour tile.
  /// See [AppRack.insetRadius].
  static const double inputRadius = AppRack.insetRadius;

  /// Bottom nav bar height (including safe-area overlay).
  static const double bottomNavHeight = 64;
}
