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

  /// Standard card border radius.
  static const double cardRadius = 12;

  /// Standard button border radius.
  static const double buttonRadius = 10;

  /// Standard input border radius.
  static const double inputRadius = 10;

  /// Bottom nav bar height (including safe-area overlay).
  static const double bottomNavHeight = 64;
}
