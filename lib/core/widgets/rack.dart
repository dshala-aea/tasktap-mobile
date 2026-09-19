// dart format width=100
import 'package:flutter/material.dart';

/// Was the aluminium-rail decoration painted behind the app shell's content — the van-racking
/// metaphor's own fixed backdrop. Vetro has no rail-and-drawer shell to bolt content to, so this
/// is a passthrough now: kept as a class (one call site, `home_shell.dart`, wraps its content in
/// it) purely so that site needs no change, not because anything still renders here.
class Rack extends StatelessWidget {
  const Rack({super.key, required this.child, this.top = 0, this.bottom = 0, this.visible = true});

  final Widget child;

  /// No longer consulted — nothing is painted behind [child] to inset around. Kept on the
  /// constructor so `home_shell.dart`'s call site needs no change.
  final double top;

  /// No longer consulted, for the same reason as [top].
  final double bottom;

  /// No longer consulted, for the same reason as [top].
  final bool visible;

  @override
  Widget build(BuildContext context) => child;
}

// RackCell (the drawer-front cell AppCard and the old CompartmentTile used to render through),
// RackLabel, and ShadowBoard/SilhouettePainter used to live here. RackCell has no callers left —
// AppCard renders VetroGlass directly now (see its own doc comment) and CompartmentTile was
// deleted outright once every screen turned out to already use VetroCompartmentTile instead.
// RackLabel was never referenced by anything. ShadowBoard moved to empty_state.dart as
// CompactEmptyState, the family it actually belongs with under Vetro.
