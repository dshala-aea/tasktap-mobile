import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';

/// Floating action button — 56 px circle, flat stamp-red fill, white icon.
///
/// Same flat `AppColors.Y` fill `AppButton.primary`/`AppBottomNav`'s active tab use — the one
/// accent in the app means the same thing everywhere. Retired: the flat orange fill, the "ledge"
/// bottom-edge border (a van-racking cue — the FAB is no longer part of that metaphor). Keeps its
/// shadow — unlike a static in-flow surface, this is a genuinely floating control (see
/// `AppButton`'s doc comment distinguishing the two).
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
              // A true circle, not a 12px-cornered square — the doc comment above already
              // promised one; AppRack.freeShape (the app's general card-corner radius) never
              // delivered it at this size.
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.Y.withAlpha(90),
                  offset: const Offset(0, 4),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
