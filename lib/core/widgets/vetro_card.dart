// dart format width=100
import 'package:flutter/material.dart';

import 'vetro_glass.dart';

/// Vetro's minimal container — a glass panel, a tap target, nothing else.
///
/// [AppCard] is glass now too (both wrap [VetroGlass]), but keeps its own interface rather than
/// being replaced by this one: `strapped`/`borderColor` are real, currently-used state-marking
/// capability this widget deliberately doesn't carry — a plain content block never needs to mark
/// state, and forcing that concept into every call site here would widen the interface for the
/// callers that don't want it. Reach for [AppCard] when a block needs to say "this one needs you";
/// reach for this one otherwise.
class VetroCard extends StatelessWidget {
  const VetroCard({super.key, required this.child, this.padding, this.onTap, this.borderRadius});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  static const _defaultRadius = BorderRadius.all(Radius.circular(20));
  static const _defaultPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? _defaultRadius;
    final content = Padding(padding: padding ?? _defaultPadding, child: child);

    return VetroGlass(
      borderRadius: radius,
      // VetroGlass would otherwise apply its own padding around `content`, double-padding it —
      // padding is handled here instead so an `onTap` row's ink can reach the full glass bounds.
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(borderRadius: radius, onTap: onTap, child: content),
            ),
    );
  }
}
