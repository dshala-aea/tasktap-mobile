// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// AiDraftAction
//
// The "Genera con AI" draft action, promoted out of the Dettagli step's form and onto
// RapportinoFormScreen itself — see rapportino_form_screen.dart's build() for where it is placed.
//
// Previously this lived as a private `_AiDraftButton` inside step_dettagli.dart's scrollable form:
// two navigation actions deep (open the report → tap the Dettagli tile → the bottom sheet opens),
// and entirely hidden when the draft had no scheduleId (true for cantiere-originated drafts, which
// have no ticket to draft from). Both of those made it easy to miss and feel like a buried form
// field rather than the primary AI-assist entry point it is meant to be.
//
// This widget is self-contained: unlike the old `_AiDraftButton` (which received scheduleId/
// ticketId/busy/onDraft threaded in from `_StepDettagliState`), it reads everything itself off
// `reportEditorProvider`/`aiQuotaProvider` and writes back through the notifier directly. It does
// NOT need Dettagli's `_titleCtrl`/`_detailsCtrl` controllers — those are just Dettagli's own local
// mirrors, re-read from the notifier in its own initState — so this renders correctly even on a
// screen that never opens the Dettagli sheet in the same session.
//
// Unlike the old full-hide-when-no-schedule behavior, this widget always renders: with no
// scheduleId it shows a disabled button and explains why, rather than disappearing and leaving the
// technician wondering where the AI button they remember from other rapportini went.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';
import '../../presentation/providers/report_editor_providers.dart';

class AiDraftAction extends ConsumerStatefulWidget {
  const AiDraftAction({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<AiDraftAction> createState() => _AiDraftActionState();
}

class _AiDraftActionState extends ConsumerState<AiDraftAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(reportEditorProvider(widget.reportId));
    final scheduleId = state.scheduleId;
    final ticketId = state.ticketId;
    final available = scheduleId != null;
    final quota = ref.watch(aiQuotaProvider);
    final exhausted = quota.valueOrNull?.exhausted ?? false;
    final disabled = !available || exhausted;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        child: Row(
          children: [
            Icon(LucideIcons.penTool, size: 18, color: disabled ? c.inkDisabled : c.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bozza automatica',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: disabled ? c.inkMuted : c.ink,
                    ),
                  ),
                  Text(
                    // No schedule to draft from takes priority over the quota text: it is the
                    // reason the button won't work here regardless of what's left this month.
                    !available
                        ? 'Questo rapportino non è collegato a un ticket pianificato, quindi la '
                              'bozza automatica AI non è disponibile.'
                        : switch (quota) {
                            AsyncData(:final value) when value.exhausted =>
                              'Quota aziendale esaurita per questo mese',
                            AsyncData(:final value) =>
                              '${value.remaining} generazioni rimaste all\'azienda questo mese',
                            AsyncError() => 'Quota non verificabile ora',
                            _ => 'Verifica quota…',
                          },
                    style: TextStyle(fontSize: 11, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              AppButton(
                label: 'Genera',
                size: AppButtonSize.sm,
                fullWidth: false,
                onPressed: disabled ? null : () => _generateAiDraft(scheduleId, ticketId),
              ),
          ],
        ),
      ),
    );
  }

  /// Ask the server for a drafted title and description for this intervento.
  ///
  /// Applies to the two fields the editor can actually hold. `technicianNotes` comes back from the
  /// model too, but `ReportEditorState` hardcodes it to null and exposes no setter, so applying it
  /// would mean inventing storage for it here — a change to the draft model, not to this action.
  ///
  /// Never overwrites silently. Anything the technician has already typed is what they observed on
  /// site; a model's guess must not replace it without being asked.
  Future<void> _generateAiDraft(String scheduleId, String? ticketId) async {
    if (_busy) return;

    final editor = ref.read(reportEditorProvider(widget.reportId));
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);

    // Whatever is already in `details` when the draft is requested — typed or dictated. Captured
    // before the overwrite-confirmation dialog and the draft response replace it, so the backend's
    // "Nota Vocale Tecnico" prompt section actually receives what was said on site instead of
    // nothing.
    final voiceTranscript = editor.details.trim();

    final hasTyped = editor.title.trim().isNotEmpty || editor.details.trim().isNotEmpty;
    if (hasTyped) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sostituire il testo?'),
          content: const Text(
            'Titolo e descrizione contengono già del testo. '
            'La bozza AI lo sostituirà.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sostituisci'),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    setState(() => _busy = true);
    try {
      final draft = await ref
          .read(aiApiClientProvider)
          .generateDraft(
            scheduleId: scheduleId,
            ticketId: ticketId,
            voiceTranscript: voiceTranscript.isEmpty ? null : voiceTranscript,
          );

      await notifier.setTitle(draft.title);
      await notifier.setDetails(draft.details);
      // The rapportino now carries text a model wrote. Recorded here, at the one place the
      // generated text actually enters the record, rather than at the point the button is
      // pressed — a draft that is generated and then discarded is not AI assistance.
      await notifier.markAiAssisted();

      // The allowance is the whole company's, so it can move without this technician doing
      // anything. Re-read it rather than decrementing a local copy.
      ref.invalidate(aiQuotaProvider);

      if (!mounted) return;
      showAppToast(
        context,
        message: 'Bozza generata (${draft.modelUsed}). Rileggila prima di inviare.',
        tone: ToastTone.success,
      );
    } on AiQuotaExhaustedException catch (e) {
      if (!mounted) return;
      final when = e.resetsAt == null
          ? 'il primo del mese'
          : DateFormat('d MMMM', 'it').format(e.resetsAt!.toLocal());
      showAppToast(
        context,
        message: 'Quota AI della tua azienda esaurita. Si azzera $when.',
        tone: ToastTone.warning,
      );
    } on AiFailure catch (e) {
      if (!mounted) return;
      showAppToast(context, message: e.message, tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
