// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import 'completion.dart';

/// Persistent "Stato rapportino" above the chat composer: what is complete, what is missing, and
/// whether the draft is ready to be reviewed.
///
/// An indicator only — the authoritative send gate is the server's `CanInvia`. Keeping it visible
/// (rather than a message in the thread) is the point: a technician scrolling back must not lose
/// sight of what still needs saying.
class AiCompletionStrip extends StatelessWidget {
  const AiCompletionStrip({super.key, required this.completion});

  final AiChatCompletion completion;

  static const _labels = {
    'tecnici': 'Tecnici',
    'materiali': 'Materiali',
    'controlli': 'Controlli',
    'descrizione': 'Descrizione',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ready = completion.readyForReview;
    final summary = ready
        ? 'Pronto per la revisione'
        : 'Manca: ${completion.missingLabels.join(', ')}';

    return Container(
      key: const ValueKey('ai-completion-strip'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 6,
            children: [for (final item in completion.items) _chip(context, item)],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                ready ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
                size: 14,
                color: ready ? colors.green : colors.amber,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  summary,
                  key: const ValueKey('ai-completion-summary'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ready ? colors.ink : colors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, CompletionItem item) {
    final colors = context.colors;
    final (icon, color, suffix) = switch (item.state) {
      CompletionState.complete => (LucideIcons.checkCircle2, colors.green, ''),
      CompletionState.missing => (LucideIcons.alertCircle, colors.amber, ''),
      CompletionState.notApplicable => (LucideIcons.circle, colors.inkMuted, ' · se previsti'),
    };

    return Container(
      key: ValueKey('ai-completion-${item.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '${_labels[item.key] ?? item.key}$suffix',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.ink),
          ),
        ],
      ),
    );
  }
}
