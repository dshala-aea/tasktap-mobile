import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';

/// A list row's leading icon, cut into the case rather than floating on the page.
///
/// Ten screens built this by hand as `Container(width: 40, height: 40, decoration:
/// BoxDecoration(color: context.colors.bg3, ...))` — a light-gray tile on a light card, barely
/// differentiated from the ground it sits on. The Cassetta world's own compartment icon is a dark
/// case-shell square (see the prototype's `.comp-icon`/`.row-ic`): every icon reads as something
/// cut into the case, not a pale circle drawn on top of it, and the contrast against a light card
/// is what gives a scanned list its rhythm.
///
/// ```dart
/// RowIconTile(icon: LucideIcons.ticket);
/// RowIconTile(child: Image.network(url, fit: BoxFit.cover));  // a real photo, same frame
/// ```
class RowIconTile extends StatelessWidget {
  const RowIconTile({
    super.key,
    this.icon,
    this.child,
    this.size = 40,
    this.iconSize = 20,
    this.radius,
  }) : assert(icon != null || child != null, 'RowIconTile needs an icon or a child');

  final IconData? icon;

  /// Overrides the default icon — a real photo, for instance, clipped to the same frame.
  final Widget? child;

  final double size;
  final double iconSize;

  /// Defaults to [AppRack.insetRadius] — "a compartment inside a compartment," the same corner
  /// every other nested tile in the app uses.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.CHARCOAL,
        borderRadius: BorderRadius.circular(radius ?? AppRack.insetRadius),
      ),
      child:
          child ??
          Icon(icon, size: iconSize, color: AppColors.onDarkMuted),
    );
  }
}
