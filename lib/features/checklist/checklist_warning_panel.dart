// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/widgets/widgets.dart';
import 'checklist_providers.dart';

/// Riepilogo's amber heads-up about required asset controls that are still empty. A warning, never
/// a block: the server decides (a previous visit's answer or an office-deactivated row would make a
/// client-side block wrong), and an offline submit that the server then refuses is exactly what
/// this panel exists to prevent.
class ChecklistWarningPanel extends ConsumerWidget {
  const ChecklistWarningPanel({super.key, required this.reportId, required this.onOpen});

  final String reportId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(assetChecklistStatusProvider(reportId));
    if (status == null || status.missing.isEmpty) return const SizedBox.shrink();
    final n = status.missing.length;
    final preview = status.missing.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineAlert(
            icon: LucideIcons.alertTriangle,
            color: context.colors.amber,
            message: n == 1
                ? 'Manca 1 controllo obbligatorio sugli asset. L\'ufficio non riceverà il rapportino '
                      'finché non lo compili.'
                : 'Mancano $n controlli obbligatori sugli asset. L\'ufficio non riceverà il '
                      'rapportino finché non li compili.',
          ),
          for (final m in preview)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.sm),
              child: Text(
                '${m.assetName}: ${m.label}',
                style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
              ),
            ),
          if (n > preview.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.sm),
              child: Text(
                'e altri ${n - preview.length}',
                style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Apri i controlli mancanti', onPressed: onOpen),
        ],
      ),
    );
  }
}
