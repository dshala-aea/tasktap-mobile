import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_rack.dart';
import '../theme/app_vetro_palette.dart';

/// Floating action button — 56 px circle, Vetro tint→tintStrong gradient, white icon.
///
/// Same gradient `AppButton.primary`/`AppBottomNav`'s active tab use — the one accent in the app
/// means the same thing everywhere. Retired: the flat orange fill, the "ledge" bottom-edge border
/// (a van-racking cue — the FAB is no longer part of that metaphor), and the heavy drop shadow
/// (a soft shadow is invisible outdoors in direct sun, same reasoning as `AppButton`'s primary).
///
/// ```dart
/// AppFab(onPressed: () {});
/// AppFab(icon: LucideIcons.camera, onPressed: () {});
/// ```
class AppFab extends StatelessWidget {
  const AppFab({super.key, required this.onPressed, this.icon = LucideIcons.plus, this.tooltip});

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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.vetro.tint, context.vetro.tintStrong],
              ),
              borderRadius: AppRack.freeShape,
              boxShadow: [
                BoxShadow(
                  color: context.vetro.tint.withAlpha(90),
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
