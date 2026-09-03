import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';

/// The app's general-purpose container — a flat Documento sheet.
///
/// Public API unchanged — every `AppCard(child: …)` call site across the app means "a block of
/// content" exactly as before; only the material changed (flat sheet + hairline, not glass/blur).
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

  /// Overrides the sheet's border colour. [strapped] wins when both are set.
  final Color? borderColor;

  final Color? backgroundColor;

  /// Selected, priority, or still-needs-finishing — turns the border stamp-red. Not for a
  /// live/running state: that's `LiveDot`, a different mark.
  final bool strapped;

  /// No longer consulted (kept for call-site compatibility — see the pre-existing `flush` field
  /// on this widget before this change; it already did nothing).
  final bool flush;

  static const EdgeInsets _defaultPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);
  static const _radius = AppRack.freeShape;

  @override
  Widget build(BuildContext context) {
    final border = strapped ? AppColors.Y : (borderColor ?? const Color(0xFFDED9CE));
    final content = Padding(padding: padding ?? _defaultPadding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.SHEET,
        borderRadius: _radius,
        border: Border.all(color: border, width: 1),
      ),
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
