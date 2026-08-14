import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Floating action button — 56 px circle, Y bg, large shadow
/// (0 8px 20px rgba(0,0,0,0.18)), plus icon (24, DARK).
///
/// ```dart
/// AppFab(onPressed: () {});
/// AppFab(icon: LucideIcons.camera, onPressed: () {});
/// ```
class AppFab extends StatelessWidget {
  const AppFab({
    super.key,
    required this.onPressed,
    this.icon = LucideIcons.plus,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRack.freeShape,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRack.freeShape,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.Y,
              // Machined, not moulded — and closer to Material 3's own squircle FAB than the
              // circle this drew before. It reads as the yellow lever on the load rail, which is
              // the one place in a van that colour means "pull this".
              borderRadius: AppRack.freeShape,
              // A graphite bottom edge gives it the ledge every other object in the rack has, so
              // the primary action is made of the same material as everything it sits above.
              border: Border(
                bottom: BorderSide(color: context.colors.ledge, width: 3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(56),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: context.colors.brandOn),
          ),
        ),
      ),
    );
  }
}
