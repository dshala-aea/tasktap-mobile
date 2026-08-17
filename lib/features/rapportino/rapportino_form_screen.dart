// dart format width=100
import 'package:flutter/material.dart';
import '../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../presentation/providers/report_editor_providers.dart';
import 'steps/step_dettagli.dart';
import 'steps/step_materiali_fold.dart';
import 'steps/step_ore.dart';
import 'steps/step_riepilogo.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RapportinoFormScreen
//
// 4-step rapportino editor (Dettagli / Ore / Materiali / Riepilogo).
// Reuses the M4/M5 reportEditorProvider backbone unchanged.
// The old 7-step RapportinoEditorScreen is superseded by this screen.
// ══════════════════════════════════════════════════════════════════════════════

/// The 4 UI steps exposed by the new form (separate from the legacy
/// RapportinoStep enum which is still used by the notifier internally).
enum _FormStep { dettagli, ore, materiali, riepilogo }

const _kSteps = [
  StepperStep(label: 'Dettagli'),
  StepperStep(label: 'Ore'),
  StepperStep(label: 'Materiali'),
  StepperStep(label: 'Riepilogo'),
];

class RapportinoFormScreen extends ConsumerStatefulWidget {
  const RapportinoFormScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<RapportinoFormScreen> createState() => _RapportinoFormScreenState();
}

class _RapportinoFormScreenState extends ConsumerState<RapportinoFormScreen> {
  _FormStep _step = _FormStep.dettagli;

  int get _stepIndex => _FormStep.values.indexOf(_step);
  bool get _isFirst => _step == _FormStep.dettagli;
  bool get _isLast => _step == _FormStep.riepilogo;

  void _goNext() {
    final values = _FormStep.values;
    final idx = values.indexOf(_step);
    if (idx < values.length - 1) {
      setState(() => _step = values[idx + 1]);
    }
  }

  void _goBack() {
    final values = _FormStep.values;
    final idx = values.indexOf(_step);
    if (idx > 0) {
      setState(() => _step = values[idx - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(reportEditorProvider(widget.reportId));

    // The subtitle used to read "Ticket: 3f2a1c8e-…" — the raw id, in the most prominent piece of
    // secondary text on the screen. What it is linked to is now named properly at the top of
    // Dettagli, where the name is resolvable; repeating it here as a GUID was worse than silence.
    // From Ore onwards it carries the rapportino's own title instead, so the header answers "which
    // one am I in" once the field that names it has scrolled out of reach.
    final subtitle = _isFirst || editorState.title.isEmpty ? null : editorState.title;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      // The last AppBar in the app. Its hand-rolled title Column also carried a fifth instance of
      // the fixed-dark bug: the subtitle took `inkMuted`, which measures 1.9:1 on CHARCOAL in
      // light mode. ScreenHeader's own dark variant renders both lines correctly.
      appBar: ScreenHeaderBar(
        title: 'Rapportino',
        subtitle: subtitle,
        backgroundColor: AppColors.CHARCOAL,
        actions: [
          // Autosave indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
      body: Column(
        children: [
          // ── Stepper ────────────────────────────────────────────────────────
          //
          // The bar names the step, so the header does not have to: two dark bands stacked under
          // each other, one saying "Rapportino" and the other repeating "Dettagli" in 10px under
          // a numbered disc, was most of the first viewport spent on chrome.
          Container(
            color: AppColors.CHARCOAL,
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 8),
            child: AppStepper(
              steps: _kSteps,
              currentIndex: _stepIndex,
              // Jump straight back to a step already filled in. Correcting the cliente from the
              // summary used to mean pressing Indietro three times.
              onStepSelected: (i) => setState(() => _step = _FormStep.values[i]),
            ),
          ),

          // ── Step content ───────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: _buildStep(key: ValueKey(_step)),
            ),
          ),

          // ── Sticky bottom navigation bar ───────────────────────────────────
          _BottomNavBar(isFirst: _isFirst, isLast: _isLast, onBack: _goBack, onNext: _goNext),
        ],
      ),
    );
  }

  Widget _buildStep({required Key key}) {
    return switch (_step) {
      _FormStep.dettagli => StepDettagli(key: key, reportId: widget.reportId),
      _FormStep.ore => StepOre(key: key, reportId: widget.reportId),
      _FormStep.materiali => StepMaterialiFold(key: key, reportId: widget.reportId),
      _FormStep.riepilogo => StepRiepilogo(key: key, reportId: widget.reportId),
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _BottomNavBar
// ══════════════════════════════════════════════════════════════════════════════

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });

  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: context.colors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
        child: Row(
          children: [
            if (!isFirst) ...[
              // Full width only while it is sharing the bar with Avanti. On Riepilogo the real
              // action is Invia, sitting just above; a full-width secondary button underneath it
              // was the largest control on the screen and pointed backwards.
              if (isLast)
                AppButton.secondary(
                  label: 'Indietro',
                  onPressed: onBack,
                  size: AppButtonSize.lg,
                  fullWidth: false,
                )
              else
                Expanded(
                  child: AppButton.secondary(
                    label: 'Indietro',
                    onPressed: onBack,
                    size: AppButtonSize.lg,
                  ),
                ),
              if (!isLast) const SizedBox(width: 12),
            ],
            if (!isLast)
              Expanded(
                child: AppButton(label: 'Avanti', onPressed: onNext, size: AppButtonSize.lg),
              ),
          ],
        ),
      ),
    );
  }
}
