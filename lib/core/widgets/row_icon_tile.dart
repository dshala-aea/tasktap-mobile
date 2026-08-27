import 'package:flutter/material.dart';

import '../theme/app_rack.dart';
import '../theme/app_vetro_palette.dart';

/// A list row's leading icon — a tint-chip cut into the card, matching the Vetro reference's own
/// `.row .ic` (12%-alpha tint fill, solid-tint icon), not the earlier Cassetta-era solid dark
/// case-shell square this used to paint on every list row in the app regardless of theme.
///
/// ```dart
/// RowIconTile(icon: LucideIcons.ticket);
/// RowIconTile(child: Image.network(url, fit: BoxFit.cover));  // a real photo, same frame
/// RowIconTile(icon: LucideIcons.checkCircle2, color: context.colors.green);  // a semantic state
/// ```
class RowIconTile extends StatelessWidget {
  const RowIconTile({
    super.key,
    this.icon,
    this.child,
    this.size = 40,
    this.iconSize = 20,
    this.radius,
    this.color = AppVetroColors.tint,
  }) : assert(icon != null || child != null, 'RowIconTile needs an icon or a child');

  final IconData? icon;

  /// Overrides the default icon — a real photo, for instance, clipped to the same frame.
  final Widget? child;

  final double size;
  final double iconSize;

  /// Defaults to [AppRack.insetRadius] — "a compartment inside a compartment," the same corner
  /// every other nested tile in the app uses.
  final double? radius;

  /// Drives both the tile's fill (this colour at ~12% alpha) and the icon (this colour, solid) —
  /// pass a semantic colour (e.g. [BuildContext.colors]`.green`) for a state icon; the default is
  /// the one Vetro accent, matching a plain, non-semantic row.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(radius ?? AppRack.insetRadius),
      ),
      child: child ?? Icon(icon, size: iconSize, color: color),
    );
  }
}
