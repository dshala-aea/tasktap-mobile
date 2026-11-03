// dart format width=100
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';

/// One pending request in the approver's worklist.
///
/// The card is deliberately dumb: it renders what the queue provides and reports the two actions.
/// The screen owns the confirmation, the reject sheet and the in-flight state; [busy] only disables
/// a row whose decision is already being sent.
class ApprovalRequestCard extends StatelessWidget {
  const ApprovalRequestCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.reason,
    required this.onApprove,
    required this.onReject,
    this.busy = false,
  });

  /// The requester's display name, never an id.
  final String title;

  /// Type/period text, already formatted by the screen.
  final String subtitle;

  /// The request's own reason, when it has one.
  final String? reason;

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final reasonText = reason?.trim() ?? '';
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.inkMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.xs,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: context.colors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, style: muted),
            if (reasonText.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(reasonText, style: muted),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Rifiuta',
                    size: AppButtonSize.sm,
                    onPressed: busy ? null : onReject,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Approva',
                    size: AppButtonSize.sm,
                    onPressed: busy ? null : onApprove,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
