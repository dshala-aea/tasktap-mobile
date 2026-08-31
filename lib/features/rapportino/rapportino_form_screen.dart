// dart format width=100
import 'package:flutter/material.dart';
import '../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_rack.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/vetro_compartment_tile.dart';
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
// A checklist of three compartments (Dettagli / Ore / Materiali), not a stepper — see
// _openStep's own doc comment for why this replaced the sequential wizard. Riepilogo is not a
// fourth peer tile: it is what the completion card itself opens, because reviewing the draft and
// fixing whatever's missing is one action, not a checklist item you tick off in advance of doing
// it. Reuses the M4/M5 reportEditorProvider backbone unchanged, and each step widget unchanged:
// the same StepDettagli/StepOre/StepMaterialiFold/StepRiepilogo the stepper rendered inline now
// render inside a bottom sheet instead.
// ══════════════════════════════════════════════════════════════════════════════

class RapportinoFormScreen extends ConsumerWidget {
  const RapportinoFormScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = context.vetro;
    final editorState = ref.watch(reportEditorProvider(reportId));
    final subtitle = editorState.title.isEmpty ? null : editorState.title;

    final dettagliDone = editorState.title.isNotEmpty;
    final oreDone = editorState.staffRows.isNotEmpty;
    final materialiDone = editorState.materialeRows.isNotEmpty || editorState.materialiNotRequired;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: 'Rapportino',
        subtitle: subtitle,
        actions: [
          // Autosave indicator — spinner ↔ cloud used to hard-cut, on the single most-repeated
          // state change in this screen: it flips on every field edit while filling in a report.
          // AnimatedSwitcher, matching the idiom this pass already established on Dashboard and
          // the ticket list.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Semantics(
              label: editorState.isSaving ? 'Salvataggio in corso' : 'Rapportino salvato',
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: editorState.isSaving
                    ? SizedBox(
                        key: const ValueKey('saving'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: v.tint),
                      )
                    : Icon(LucideIcons.cloud, key: const ValueKey('saved'), size: 20, color: v.tint),
              ),
            ),
          ),
        ],
      ),
      // While the draft's saved data is still loading from Drift, the grid's done/not-done dots
      // and the completion count would read as blank/incomplete regardless of what's actually
      // saved — a flash of wrong information is worse than a brief spinner. See
      // ReportEditorNotifier._hydrate's own doc comment for why this load exists at all.
      body: editorState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
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
                // Wider than a phone (tablet, foldable unfolded) gets a fourth column instead of
                // stretching the same three tiles across the extra width.
                crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
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
                ],
              ),
              const SizedBox(height: 20),
              _CompletionCard(
                completed: [dettagliDone, oreDone, materialiDone].where((d) => d).length,
                onTap: () => openCompartmentSheet(
                  context,
                  label: 'Riepilogo',
                  content: StepRiepilogo(reportId: reportId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _CompletionCard — Vetro gradient summary anchoring the checklist, and its tap target
//
// The grid alone left the rest of the screen a dead void with nothing telling the technician
// where they stood. Was the CHARCOAL/AppColors.Y card Ore's own "Totale ore" card used —
// Vetro's tint gradient carries the same "readout" job now (see _TicketRow's own note on why
// the strap language moved from brand-orange to tint across every module).
//
// It is also the only way into Riepilogo. Riepilogo used to sit in the grid as a fourth
// checklist item, ticked once both signatures existed — which asked the technician to treat
// "review the draft" as a box to check before they had reviewed anything. It is the pre-confirm
// step, not a peer of Dettagli/Ore/Materiali: tapping this card always opens it, complete or not,
// because seeing what's still missing — and filling it in — is what that screen is for.
// ══════════════════════════════════════════════════════════════════════════════

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completed, required this.onTap});

  final int completed;
  final VoidCallback onTap;

  static const _total = 3;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final ready = completed == _total;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRack.freeShape,
      child: InkWell(
        borderRadius: AppRack.freeShape,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRack.freeShape,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [v.tint, v.tintStrong],
            ),
            boxShadow: [
              BoxShadow(color: v.tint.withAlpha(90), blurRadius: 24, offset: const Offset(0, 12)),
            ],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compilazione',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white.withAlpha(200),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // The one number on this whole screen that actually answers "am I done" — used
                  // to jump straight from one digit to the next with no transition, on the card
                  // that is the sole way into Riepilogo. A fade-through (out then in, not a
                  // crossfade) reads as the count ticking over rather than two different cards
                  // being swapped.
                  AnimatedSwitcher(
                    duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      '$completed di $_total',
                      key: ValueKey(completed),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSwitcher(
                    duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Row(
                      key: ValueKey(ready),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ready ? LucideIcons.checkCircle2 : LucideIcons.circleDot,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ready ? 'Pronto per l\'invio' : 'Da completare',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Rivedi e invia',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white.withAlpha(200),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, size: 14, color: Colors.white.withAlpha(200)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _StepTile — CompartmentTile plus a completion mark
// ══════════════════════════════════════════════════════════════════════════════

/// A [VetroCompartmentTile] with a filled/hollow completion dot — the "what's left" read a
/// stepper's numbered discs used to give for free. No forced order and no discs to number, so
/// this is the one piece of state the grid still needs to carry per tile.
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
    // fit: expand — a bare Stack gives the tile loose constraints, so it shrinks to content
    // width and leaves the badge floating at the grid cell's corner instead of the tile's own
    // corner (visible as a detached circle to the right of each tile).
    return Stack(
      fit: StackFit.expand,
      children: [
        VetroCompartmentTile(icon: icon, label: label, onTap: onTap),
        Positioned(
          top: 10,
          right: 10,
          // The one confirmation that a compartment's work actually registered — returning from
          // Ore or Materiali having just filled something in, this badge used to just flip with
          // no transition at all. A scale+fade reads as the tile "catching" the checkmark rather
          // than silently being a different icon on the next frame.
          child: AnimatedSwitcher(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              done ? LucideIcons.checkCircle2 : LucideIcons.circle,
              key: ValueKey(done),
              size: 16,
              color: done ? context.colors.green : context.colors.borderMedium,
            ),
          ),
        ),
      ],
    );
  }
}
