// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import 'checklist_providers.dart';

/// The Controlli sheet's door to the per-asset matrix. Nothing when the ticket has no asset
/// checklist (and nothing was omitted), so a ticket without assets looks exactly as before.
class AssetChecklistEntryCard extends ConsumerWidget {
  const AssetChecklistEntryCard({super.key, required this.reportId, required this.ticketId});

  final String reportId;
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(assetChecklistStatusProvider(reportId));
    if (status == null || (!status.hasAssetChecklists && !status.omitted)) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final line = status.omitted
        ? 'Checklist non ancora scaricata'
        : status.missing.isEmpty
        ? '${status.assetCount} asset · obbligatori completi'
        : '${status.assetCount} asset · ${status.missing.length} obbligatori mancanti';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard.pressable(
        onTap: () => context.push(AppRoutes.reportAssetChecklistPath(reportId)),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(LucideIcons.clipboardCheck, size: 20, color: c.inkMuted),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controlli per asset',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.ink),
                  ),
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: 12,
                      color: status.missing.isEmpty ? c.inkMuted : c.amber,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}
