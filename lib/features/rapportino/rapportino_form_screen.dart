// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_stepper.dart';
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
  const RapportinoFormScreen({
    super.key,
    required this.reportId,
  });

  final String reportId;

  @override
  ConsumerState<RapportinoFormScreen> createState() =>
      _RapportinoFormScreenState();
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

    // Build header context string from ticket/cantiere if linked.
    String? contextSubtitle;
    if (editorState.ticketId != null && editorState.ticketId!.isNotEmpty) {
      contextSubtitle = 'Ticket: ${editorState.ticketId}';
    } else if (editorState.cantiereId != null &&
        editorState.cantiereId!.isNotEmpty) {
      contextSubtitle = 'Cantiere: ${editorState.cantiereId}';
    } else if (editorState.ticketFreeText?.isNotEmpty ?? false) {
      contextSubtitle = 'Ticket: ${editorState.ticketFreeText}';
    }

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: AppBar(
        backgroundColor: AppColors.CHARCOAL,
        foregroundColor: context.colors.inkInverse,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rapportino',
              style: AppTextStyles.titleMedium.copyWith(color: context.colors.inkInverse),
            ),
            if (contextSubtitle != null)
              Text(
                contextSubtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.colors.inkMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        actions: [
          // Autosave indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: editorState.isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.Y,
                    ),
                  )
                : const Icon(LucideIcons.cloud,
                    size: 20, color: AppColors.Y),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Stepper ────────────────────────────────────────────────────────
          Container(
            color: AppColors.CHARCOAL,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: AppStepper(
              steps: _kSteps,
              currentIndex: _stepIndex,
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
          _BottomNavBar(
            isFirst: _isFirst,
            isLast: _isLast,
            onBack: _goBack,
            onNext: _goNext,
          ),
        ],
      ),
    );
  }

  Widget _buildStep({required Key key}) {
    return switch (_step) {
      _FormStep.dettagli => StepDettagli(key: key, reportId: widget.reportId),
      _FormStep.ore => StepOre(key: key, reportId: widget.reportId),
      _FormStep.materiali =>
        StepMaterialiFold(key: key, reportId: widget.reportId),
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
                child: AppButton(
                  label: 'Avanti',
                  onPressed: onNext,
                  size: AppButtonSize.lg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
