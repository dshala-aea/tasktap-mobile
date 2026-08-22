import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Quick action — 50 px yellow circle + icon (20) + centered Manrope 700/10
/// label.
///
/// ```dart
/// QuickAction(icon: LucideIcons.plus, label: 'Nuovo', onTap: () {});
/// ```
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.Y,
                  shape: BoxShape.circle,
                  // Decorative, not structural: the circle is already fully defined by its solid
                  // yellow fill against the page background, so losing the shadow outdoors costs
                  // nothing legible — this is polish, matching the Figma reference's own soft
                  // shadow on the same element.
                  boxShadow: context.colors.shadow,
                ),
                child: Icon(icon, size: 20, color: context.colors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.colors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
