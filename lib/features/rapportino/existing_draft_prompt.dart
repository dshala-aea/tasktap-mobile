// dart format width=100
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';

/// What the technician chose when told a draft already exists for the ticket.
enum ExistingDraftChoice {
  /// Open the draft that is already there.
  resume,

  /// Leave it alone and start a second one.
  createNew,
}

/// Warns that the ticket already has a draft and asks whether to resume it.
///
/// Reached from a ticket's "Crea rapportino": pressing it used to always create another draft, so
/// a technician who had already started that rapportino — and simply forgotten, or come back to
/// the ticket the next morning — ended up with two half-filled reports for one intervention.
/// Neither is wrong by itself; the pair is, because the office has to guess which one to bill and
/// the ticket's own report list shows both.
///
/// Three answers, and only three. Resuming is the primary action: the warning exists to prevent a
/// duplicate, and the draft already holds work. Starting a second one stays available — a
/// technician may genuinely need two rapportini on one ticket — but it is a deliberate second
/// choice rather than the unconsidered default. Dismissing returns null and creates nothing.
Future<ExistingDraftChoice?> promptExistingDraft(
  BuildContext context, {
  required String draftTitle,
  required DateTime lastTouchedAt,
}) {
  final when = DateFormat('dd/MM/yy HH:mm', 'it').format(lastTouchedAt.toLocal());
  return showDialog<ExistingDraftChoice>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bozza già presente',
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ctx.colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Per questo ticket c\'è già una bozza: «$draftTitle», '
              'ultima modifica $when.\n\n'
              'Vuoi riprenderla o crearne una nuova?',
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: ctx.colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Stacked, full-width actions: one-handed, outdoors, gloves. A three-across row would
            // leave each target well under the 44pt minimum this app holds itself to.
            AppButton(
              label: 'Riprendi bozza',
              onPressed: () => Navigator.of(ctx).pop(ExistingDraftChoice.resume),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.secondary(
              label: 'Crea una nuova bozza',
              onPressed: () => Navigator.of(ctx).pop(ExistingDraftChoice.createNew),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.ghost(label: 'Annulla', onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    ),
  );
}
