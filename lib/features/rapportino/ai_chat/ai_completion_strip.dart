// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import 'completion.dart';

/// Persistent "how far the report is" above the chat composer: a segmented rail for magnitude, one
/// caption naming the gap.
///
/// It carried four status pills and, under them, a summary line — the pills named every item, the
/// line restated them, and the two could disagree (a draft one soft item short read "Pronto per la
/// revisione" over an amber chip). The rail and the caption now come from the SAME list
/// ([AiChatCompletion.missingLabels]): a segment per item, and words for the one thing to say.
///
/// Segment colour alone never carries the state — the caption names it, as the accessibility floor
/// requires. Completed items fill green; an item the send gate still wants fills amber (a fill, per
/// DESIGN.md's amber rule); an item with nothing to satisfy — no checklist on this ticket, or the
/// non-blocking description — stays an empty slot rather than a red flag.
///
/// An indicator only: the authoritative send gate is the server's `CanInvia`. Keeping it visible
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
    final missing = completion.missingLabels;
    final ready = missing.isEmpty;
    final caption = ready
        ? 'Pronto per la revisione'
        : 'Manca: ${missing.map((k) => (_labels[k] ?? k).toLowerCase()).join(', ')}';

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
      child: Row(
        children: [
          // The bars are the picture; the caption is what is read out. Excluded from semantics so a
          // reader does not announce four unnamed shapes before the sentence that explains them.
          ExcludeSemantics(
            child: Row(
              key: const ValueKey('ai-completion-rail'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, item) in completion.items.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Container(
                    key: ValueKey('ai-completion-${item.key}'),
                    width: 22,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _fill(colors, item, blocking: missing.contains(item.key)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              caption,
              key: const ValueKey('ai-completion-summary'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                // A gap the send gate wants is an alert; the ready line is ordinary ink. The amber
                // as *text* is `amberInk` (5.8:1), never the fill hue.
                color: ready ? colors.ink : colors.amberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Completed: green. Wanted and missing: amber (a fill — DESIGN.md keeps the fill hue for fills
  /// and routes glyphs and text through `amberInk`). Everything else is an empty slot.
  Color _fill(AppPalette colors, CompletionItem item, {required bool blocking}) {
    return switch (item.state) {
      CompletionState.complete => colors.green,
      CompletionState.missing => blocking ? colors.amber : colors.bg3,
      CompletionState.notApplicable => colors.bg3,
    };
  }
}
