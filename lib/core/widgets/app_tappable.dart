// dart format width=100
import 'package:flutter/material.dart';

/// A decorated surface that answers a tap.
///
/// The app reached for [GestureDetector] nineteen times and [InkWell] eight, and the split was not
/// principled: primary things a technician taps all day — an appointment block, a day cell, a row
/// that opens a job — took the silent one. On a mid-range phone under load, a tap that paints
/// nothing is a tap the user repeats, and repeating it is how a screen gets opened twice or a
/// queued action gets submitted twice.
///
/// The mechanical reason this kept happening: an [InkWell] inside a [Container] that paints its own
/// colour shows no splash at all. Ink is drawn onto the [Material] *beneath* the child, so an opaque
/// child covers it, and the fix looks like it did not work. [Ink] is the piece that resolves it —
/// it hands the decoration to the Material layer so the splash lands on top.
///
/// Reach for [GestureDetector] directly only where the gesture is not a "press" — drags on the
/// signature pad, the toggle's own animated thumb.
class AppTappable extends StatelessWidget {
  const AppTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color,
    this.gradient,
    this.borderRadius,
    this.border,
    this.padding,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The surface colour this used to paint through a `Container`'s decoration.
  final Color? color;

  /// A gradient fill instead of a flat [color] — the Vetro tint→tintStrong "selected" state (see
  /// `AppBottomNav`'s active tab, calendario's selected-day disc/cell). Takes precedence over
  /// [color] when both are set, same as [BoxDecoration] itself.
  final Gradient? gradient;

  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;

  /// Only for a target whose visible content does not name it (an icon alone, a coloured block).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;

    Widget surface = Ink(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Colors.transparent) : null,
        gradient: gradient,
        borderRadius: radius,
        border: border,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );

    if (semanticLabel != null) {
      surface = Semantics(label: semanticLabel, button: true, child: surface);
    }

    // Transparent Material so the splash has a layer to paint on without adding a second
    // background behind the one `Ink` already draws.
    return Material(color: Colors.transparent, child: surface);
  }
}
