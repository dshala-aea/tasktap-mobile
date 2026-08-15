// dart format width=100
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single stepper step.
class StepperStep {
  const StepperStep({required this.label});

  final String label;
}

/// Progress through a multi-step form: where you are, how far is left, and a way back.
///
/// Replaces numbered circles joined by connector lines. That pattern cost two rows — 22dp discs
/// plus a caption under each — to say "step 2 of 4", printed four step names at 10px so none of
/// them was readable, and had to shrink every label to fit a phone.
///
/// It also carried the sixth instance of this project's recurring fixed-dark-surface bug: the
/// labels and the unfilled discs took `context.colors.ink`, but this bar only ever renders on
/// CHARCOAL, so in light mode they were near-black on near-black. Painting on-dark colours
/// explicitly is what stops that recurring — there is no theme-flipping token here to get wrong.
///
/// Steps already visited are tappable. A technician who wants to correct the cliente from the
/// summary should not have to press Indietro three times.
class AppStepper extends StatelessWidget {
  const AppStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.onStepSelected,
  });

  final List<StepperStep> steps;
  final int currentIndex;

  /// Called with the index of a step the user has already been through. Null disables the jump.
  final ValueChanged<int>? onStepSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                steps[currentIndex].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onDark,
                ),
              ),
            ),
            Text(
              '${currentIndex + 1} di ${steps.length}',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: AppColors.onDarkMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: _Segment(
                  step: steps[i],
                  index: i,
                  currentIndex: currentIndex,
                  onTap: onStepSelected != null && i < currentIndex
                      ? () => onStepSelected!(i)
                      : null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.step,
    required this.index,
    required this.currentIndex,
    this.onTap,
  });

  final StepperStep step;
  final int index;
  final int currentIndex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reached = index <= currentIndex;

    return Semantics(
      button: onTap != null,
      selected: index == currentIndex,
      label: '${step.label}, passo ${index + 1}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // The bar is 4dp but the target is a finger. Transparent padding rather than a taller
        // bar, so the chrome stays thin and the tap still lands.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 4,
            decoration: BoxDecoration(
              color: reached ? AppColors.Y : Colors.white.withAlpha(46),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
