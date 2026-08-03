import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';

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
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.Y,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(46), // ~0.18 opacity
                  offset: const Offset(0, 8),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: AppColors.DARK),
          ),
        ),
      ),
    );
  }
}
