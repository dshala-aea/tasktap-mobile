import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';

/// A single stepper step.
class StepperStep {
  const StepperStep({required this.label});

  final String label;
}

/// Numbered horizontal stepper (rapportino form).
///
/// Spec: numbered circles (22) Y (done/current) / BS (upcoming), check icon
/// when done, Sora 600/10 labels, 2 px connector lines Y/BS.
///
/// ```dart
/// AppStepper(
///   steps: const [StepperStep(label: 'Dati'), StepperStep(label: 'Firme')],
///   currentIndex: 0,
/// );
/// ```
class AppStepper extends StatelessWidget {
  const AppStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  final List<StepperStep> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                _Circle(index: i, currentIndex: currentIndex),
                const SizedBox(height: 4),
                Text(
                  steps[i].label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: i <= currentIndex ? AppColors.DARK : AppColors.MUTED,
                  ),
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 16,
                height: 2,
                color: i < currentIndex ? AppColors.Y : AppColors.BS,
              ),
            ),
        ],
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.index, required this.currentIndex});

  final int index;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final done = index < currentIndex;
    final current = index == currentIndex;
    final filled = done || current;

    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppColors.Y : AppColors.BS,
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(LucideIcons.check, size: 12, color: AppColors.DARK)
          : Text(
              '${index + 1}',
              style: GoogleFonts.sora(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: filled ? AppColors.DARK : AppColors.WHITE,
              ),
            ),
    );
  }
}
