import 'package:flutter/material.dart';

import '../theme/app_vetro_palette.dart';
import 'vetro_glass.dart';

/// The app's general-purpose container — a Vetro glass panel.
///
/// The public API is unchanged on purpose. Thirty-three call sites across thirteen screens say
/// `AppCard(child: …)`, and every one of them means "a block of content," which [VetroGlass]
/// renders directly now rather than through `RackCell`'s drawer-front cell.
///
/// This is deliberately not routed through [VetroCard]: that widget's own doc comment explains
/// why it stays minimal (no state-marking concept), and [strapped]/[borderColor] are real,
/// currently-used capability — recoloring the glass border rather than a separate ledge bar,
/// which is the same move `ListRow`'s state marking made (a property of the surface's own edge,
/// not a second material glued onto it).
///
/// [flush] no longer does anything: it distinguished a cell butted against the rail from a free
/// one, and Vetro has no rail for a card to be flush against. Kept on the constructor only so
/// call sites need no change.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
    this.strapped = false,
    this.flush = true,
  });

  /// Tappable variant with ink ripple.
  const AppCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding,
    this.borderColor,
    this.backgroundColor,
    this.strapped = false,
    this.flush = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Overrides the glass border colour. [strapped] wins when both are set.
  final Color? borderColor;

  final Color? backgroundColor;

  /// Selected, priority, or still-needs-finishing — turns the glass border the Vetro tint. Not
  /// for a live/running state: that's `LiveDot`, deliberately a different mark (see its doc
  /// comment).
  final bool strapped;

  /// No longer consulted — see class doc. Kept so existing call sites need no change.
  final bool flush;

  static const EdgeInsets _defaultPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);
  static const _radius = BorderRadius.all(Radius.circular(20));

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final border = strapped ? v.tint : borderColor;
    final content = Padding(padding: padding ?? _defaultPadding, child: child);

    return VetroGlass(
      borderRadius: _radius,
      fill: backgroundColor,
      border: border,
      // VetroGlass would otherwise apply its own padding around `content`, double-padding it —
      // padding is handled here instead so an `onTap` row's ink can reach the full glass bounds.
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: _radius,
              child: InkWell(borderRadius: _radius, onTap: onTap, child: content),
            ),
    );
  }
}
