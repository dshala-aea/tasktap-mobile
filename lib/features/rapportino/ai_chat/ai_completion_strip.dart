// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import 'completion.dart';

/// Persistent "what the report still needs" above the chat composer.
///
/// One row of chips and nothing else. It used to carry a second line summarising them ("Pronto per
/// la revisione" / "Manca: …") which restated the chips it sat under, and could contradict them —
/// a draft one soft item short of complete read "Pronto" while an amber chip said otherwise. The
/// chips are the summary: a check means captured, an alert means the send gate still wants it, a
/// hollow circle means the ticket has nothing to satisfy.
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
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: 6,
        children: [for (final item in completion.items) _chip(context, item)],
      ),
    );
  }

  Widget _chip(BuildContext context, CompletionItem item) {
    final colors = context.colors;
    final label = _labels[item.key] ?? item.key;
    final (icon, color) = switch (item.state) {
      CompletionState.complete => (LucideIcons.checkCircle2, colors.green),
      // Amber as a glyph on Paper measures ~1.9:1; DESIGN.md routes every amber line and icon
      // through `amberInk` for exactly this reason (5.8:1), keeping the fill hue for fills only.
      CompletionState.missing => (LucideIcons.alertCircle, colors.amberInk),
      CompletionState.notApplicable => (LucideIcons.circle, colors.inkMuted),
    };

    return Semantics(
      // The "se previsti" caveat belongs in the reader, not in the chip: every extra word in the
      // row is a word the technician reads before finding the one that matters.
      label: item.state == CompletionState.notApplicable ? '$label, se previsti' : label,
      child: Container(
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
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
