// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../providers/report_editor_providers.dart';
import 'steps/step_allegati.dart';
import 'steps/step_controlli.dart';
import 'steps/step_dati.dart';
import 'steps/step_firme.dart';
import 'steps/step_materiali.dart';
import 'steps/step_review.dart';
import 'steps/step_staff.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RapportinoEditorScreen
//
// Multi-step rapportino editor.  All state is managed by ReportEditorNotifier
// and autosaved to Drift on every field change.
// ══════════════════════════════════════════════════════════════════════════════

class RapportinoEditorScreen extends ConsumerWidget {
  const RapportinoEditorScreen({
    super.key,
    required this.reportId,
  });

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        elevation: 0,
        title: Text(
          'Nuovo Rapportino',
          style: AppTextStyles.titleMedium.copyWith(color: AppColors.onBrand),
        ),
        actions: [
          if (editorState.isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black54,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.cloud_done_outlined, size: 20),
            ),
        ],
      ),
      body: Column(
        children: [
          // Step progress indicator
          _StepProgressBar(currentStep: editorState.currentStep),

          // Step content
          Expanded(
            child: _buildCurrentStep(
              context,
              editorState.currentStep,
              reportId,
              ref,
            ),
          ),

          // Navigation buttons
          _StepNavBar(
            reportId: reportId,
            currentStep: editorState.currentStep,
            onBack: () => notifier.prevStep(),
            onNext: () => notifier.nextStep(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep(
    BuildContext context,
    RapportinoStep step,
    String reportId,
    WidgetRef ref,
  ) {
    switch (step) {
      case RapportinoStep.dati:
        return StepDati(reportId: reportId);
      case RapportinoStep.staff:
        return StepStaff(reportId: reportId);
      case RapportinoStep.materiali:
        return StepMateriali(reportId: reportId);
      case RapportinoStep.controlli:
        return StepControlli(reportId: reportId);
      case RapportinoStep.firme:
        return StepFirme(reportId: reportId);
      case RapportinoStep.allegati:
        return StepAllegati(reportId: reportId);
      case RapportinoStep.review:
        return StepReview(reportId: reportId);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Step progress indicator
// ══════════════════════════════════════════════════════════════════════════════

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.currentStep});

  final RapportinoStep currentStep;

  static const _labels = {
    RapportinoStep.dati: 'Dati',
    RapportinoStep.staff: 'Staff',
    RapportinoStep.materiali: 'Mat.',
    RapportinoStep.controlli: 'Ctrl',
    RapportinoStep.firme: 'Firme',
    RapportinoStep.allegati: 'Foto',
    RapportinoStep.review: 'Riepilogo',
  };

  @override
  Widget build(BuildContext context) {
    final steps = RapportinoStep.values;
    final currentIdx = steps.indexOf(currentStep);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepDot(
              label: _labels[steps[i]] ?? '',
              isActive: i == currentIdx,
              isDone: i < currentIdx,
              index: i + 1,
            ),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  color: i < currentIdx ? AppColors.brand : Colors.grey[200],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.isActive,
    required this.isDone,
    required this.index,
  });

  final String label;
  final bool isActive;
  final bool isDone;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? AppColors.brand
                : isActive
                    ? AppColors.onBrand
                    : Colors.grey[200],
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.black87)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : Colors.grey,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppColors.onBrand : Colors.grey,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Step navigation bar
// ══════════════════════════════════════════════════════════════════════════════

class _StepNavBar extends StatelessWidget {
  const _StepNavBar({
    required this.reportId,
    required this.currentStep,
    required this.onBack,
    required this.onNext,
  });

  final String reportId;
  final RapportinoStep currentStep;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isFirst = currentStep == RapportinoStep.dati;
    final isLast = currentStep == RapportinoStep.review;

    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (!isFirst)
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Indietro'),
                ),
              ),
            if (!isFirst) const SizedBox(width: 12),
            if (!isLast)
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: AppColors.onBrand,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Avanti',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
