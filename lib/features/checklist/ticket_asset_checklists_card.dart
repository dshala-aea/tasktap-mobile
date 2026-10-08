// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/checklist/control_answer_rules.dart';
import 'checklist_providers.dart';

/// The entry to the per-asset checklist on the ticket's Controllo section. Renders nothing when the
/// ticket has no asset checklist and nothing was omitted, so tickets without assets look exactly as
/// they did before.
class TicketAssetChecklistsCard extends ConsumerWidget {
  const TicketAssetChecklistsCard({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(ticketChecklistProvider(ticketId)).valueOrNull;
    if (tree == null || !tree.hasAnything) return const SizedBox.shrink();

    final assets = tree.distinctAssets.where((a) => a.templated).toList();
    final progress = progressOf([for (final a in assets) ...a.controls], (_) => null);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      child: AppCard.pressable(
        onTap: () => context.push(AppRoutes.ticketAssetChecklistPath(ticketId)),
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
                    tree.omitted && assets.isEmpty
                        ? 'Checklist non ancora scaricata'
                        : '${assets.length} asset · ${progress.answered}/${progress.total} compilati'
                              '${progress.requiredMissing > 0 ? ' · ${progress.requiredMissing} obbligatori mancanti' : ''}',
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
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
