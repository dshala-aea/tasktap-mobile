import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Inline error for one section of a screen — distinct from the page-level [ErrorState]: a failed
/// sub-section (a tab's own fetch, a detail screen's own sub-list) should not block the rest of
/// the screen from being usable the way a full [ErrorState] would.
///
/// Was three independent, drifting copies of the same shape — two identical private
/// `_SectionError` classes (`admin_cantiere_detail_screen.dart`, `admin_customer_detail_screen.dart`)
/// and a third, inlined copy (`admin_prodotto_detail_screen.dart`) that had quietly lost the red
/// text color the other two carried.
///
/// ```dart
/// AppSectionError(onRetry: () => ref.invalidate(someProvider));
/// AppSectionError(message: 'Impossibile caricare i contatti. Riprova.', onRetry: _retry);
/// ```
class AppSectionError extends StatelessWidget {
  const AppSectionError({
    super.key,
    required this.onRetry,
    this.message = 'Impossibile caricare. Riprova.',
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.red),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    );
  }
}
