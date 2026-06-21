import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/status_colors.dart';

/// Displays a [ReportStato] as a compact, colored badge pill.
///
/// ```dart
/// StatusBadge(stato: ReportStato.inviato);
/// StatusBadge(stato: ReportStato.fatturato, size: StatusBadgeSize.large);
/// ```
enum StatusBadgeSize { small, medium, large }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.stato,
    this.size = StatusBadgeSize.medium,
  });

  final ReportStato stato;
  final StatusBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final pair = statusColor(stato);
    final label = statoLabel(stato);

    final textStyle = switch (size) {
      StatusBadgeSize.small => AppTextStyles.labelSmall.copyWith(
          color: pair.foreground,
          fontWeight: FontWeight.w700,
        ),
      StatusBadgeSize.medium => AppTextStyles.labelMedium.copyWith(
          color: pair.foreground,
          fontWeight: FontWeight.w700,
        ),
      StatusBadgeSize.large => AppTextStyles.labelLarge.copyWith(
          color: pair.foreground,
          fontWeight: FontWeight.w700,
        ),
    };

    final hPad = switch (size) {
      StatusBadgeSize.small => AppSpacing.xs + 2,
      StatusBadgeSize.medium => AppSpacing.sm,
      StatusBadgeSize.large => AppSpacing.md,
    };

    final vPad = switch (size) {
      StatusBadgeSize.small => 2.0,
      StatusBadgeSize.medium => AppSpacing.xs,
      StatusBadgeSize.large => AppSpacing.xs + 2,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: pair.background,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: Text(label, style: textStyle),
      ),
    );
  }
}
