// dart format width=100
import 'package:flutter/material.dart';

import 'vetro_glass.dart';

/// Vetro's container — additive alongside [AppCard], same reasoning as [VetroButton]: [AppCard]'s
/// rail-drawer metaphor (a ledge, a strap, a flush/nested distinction) is Cassetta's own material
/// language and doesn't have a Vetro equivalent worth forcing into this widget's interface.
/// Deliberately smaller: a glass panel, a tap target, nothing else.
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
