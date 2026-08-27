import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';

/// A tap-to-pick date or time field in the same box as [AppTextField] — filled inset, hairline
/// border, Manrope value text.
///
/// Four admin forms picked a date through a bare Material [ListTile] instead: default font,
/// default padding, no border at all, sitting between fields that all carry the app's own
/// decoration. This is the one place that box gets drawn for a value that isn't typed.
class AdminDateField extends StatelessWidget {
  const AdminDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = LucideIcons.calendar,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppSpacing.inputRadius);

    return AppFieldShell(
      label: label,
      child: AppTappable(
        onTap: onTap,
        color: c.bg3,
        border: Border.all(color: c.borderLight),
        borderRadius: radius,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        semanticLabel: '$label: $value',
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.ink),
              ),
            ),
            Icon(icon, size: 18, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}
