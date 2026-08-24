// dart format width=100
import 'package:flutter/material.dart';
import '../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../presentation/providers/report_editor_providers.dart';
import 'steps/step_dettagli.dart';
import 'steps/step_materiali_fold.dart';
import 'steps/step_ore.dart';
import 'steps/step_riepilogo.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RapportinoFormScreen
//
// A checklist of four compartments (Dettagli / Ore / Materiali / Riepilogo), not a stepper —
// see _openStep's own doc comment for why this replaced the sequential wizard. Reuses the M4/M5
// reportEditorProvider backbone unchanged, and each step widget unchanged: the same
// StepDettagli/StepOre/StepMaterialiFold/StepRiepilogo the stepper rendered inline now render
// inside a bottom sheet instead.
// ══════════════════════════════════════════════════════════════════════════════

class RapportinoFormScreen extends ConsumerWidget {
  const RapportinoFormScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(reportEditorProvider(reportId));
    final subtitle = editorState.title.isEmpty ? null : editorState.title;

    final dettagliDone = editorState.title.isNotEmpty;
    final oreDone = editorState.staffRows.isNotEmpty;
    final materialiDone = editorState.materialeRows.isNotEmpty || editorState.materialiNotRequired;
    // A proxy for "ready to submit," not "submitted" — both signatures are the last thing
    // Riepilogo asks for before Invia unlocks, and reading the real submission state would mean
    // a second provider just to draw a checkmark. Good enough: it tells the truth about whether
    // there is still something to do in here.
    final riepilogoDone =
        editorState.customerSignatureAllegatoId != null &&
        editorState.technicianSignatureAllegatoId != null;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: 'Rapportino',
        subtitle: subtitle,
        backgroundColor: AppColors.CHARCOAL,
        actions: [
          // Autosave indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: editorState.isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.Y),
                  )
                : const Icon(LucideIcons.cloud, size: 20, color: AppColors.Y),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.lg,
            AppSpacing.pagePadding,
            context.navClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  _StepTile(
                    icon: LucideIcons.fileText,
                    label: 'Dettagli',
                    done: dettagliDone,
                    onTap: () => openCompartmentSheet(
                      context,
                      label: 'Dettagli',
                      content: StepDettagli(reportId: reportId),
                    ),
                  ),
                  _StepTile(
                    icon: LucideIcons.clock,
                    label: 'Ore',
                    done: oreDone,
                    onTap: () => openCompartmentSheet(
                      context,
                      label: 'Ore',
                      content: StepOre(reportId: reportId),
                    ),
                  ),
                  _StepTile(
                    icon: LucideIcons.package,
                    label: 'Materiali',
                    done: materialiDone,
                    onTap: () => openCompartmentSheet(
                      context,
                      label: 'Materiali',
                      content: StepMaterialiFold(reportId: reportId),
                    ),
                  ),
                  _StepTile(
                    icon: LucideIcons.send,
                    label: 'Riepilogo',
                    done: riepilogoDone,
                    onTap: () => openCompartmentSheet(
                      context,
                      label: 'Riepilogo',
                      content: StepRiepilogo(reportId: reportId),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _CompletionCard(
                completed: [
                  dettagliDone,
                  oreDone,
                  materialiDone,
                  riepilogoDone,
                ].where((d) => d).length,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _CompletionCard — dark summary anchoring the checklist
//
// The grid alone left the rest of the screen a dead void with nothing telling the technician
// where they stood. Same CHARCOAL/AppColors.Y language as Ore's "Totale ore" card: the checklist
// is the input, this is the readout.
// ══════════════════════════════════════════════════════════════════════════════

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completed});

  final int completed;

  static const _total = 4;

  @override
  Widget build(BuildContext context) {
    final ready = completed == _total;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.CHARCOAL, borderRadius: AppRack.freeShape),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compilazione',
                style: TextStyle(
                  color: AppColors.onDarkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$completed di $_total',
                style: const TextStyle(
                  color: AppColors.Y,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          Icon(
            ready ? LucideIcons.checkCircle2 : LucideIcons.circleDot,
            size: 18,
            color: ready ? context.colors.green : AppColors.onDarkMuted,
          ),
          const SizedBox(width: 8),
          Text(
            ready ? 'Pronto per l\'invio' : 'Da completare',
            style: const TextStyle(
              color: AppColors.onDark,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _StepTile — CompartmentTile plus a completion mark
// ══════════════════════════════════════════════════════════════════════════════

/// A [CompartmentTile] with a filled/hollow completion dot — the "what's left" read a stepper's
/// numbered discs used to give for free. No forced order and no discs to number, so this is the
/// one piece of state the grid still needs to carry per tile.
class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.icon,
    required this.label,
    required this.done,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // fit: expand — a bare Stack gives CompartmentTile loose constraints, so it shrinks to
    // content width and leaves the badge floating at the grid cell's corner instead of the
    // tile's own corner (visible as a detached circle to the right of each tile).
    return Stack(
      fit: StackFit.expand,
      children: [
        CompartmentTile(icon: icon, label: label, onTap: onTap),
        Positioned(
          top: 10,
          right: 10,
          child: Icon(
            done ? LucideIcons.checkCircle2 : LucideIcons.circle,
            size: 16,
            color: done ? context.colors.green : context.colors.borderMedium,
          ),
        ),
      ],
    );
  }
}
