// dart format width=100
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

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
/// Sat on a fixed-CHARCOAL plate under the header for one round of this project's recurring
/// fixed-dark-surface bug and was painted with `onDark`/`onDarkMuted` to match. That plate is
/// gone — every screen using this now sits directly on the page's own flipping background — so
/// this reads `context.colors` like everything else around it.
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
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.ink,
                ),
              ),
            ),
            Text(
              '${currentIndex + 1} di ${steps.length}',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: context.colors.inkMuted,
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
  const _Segment({required this.step, required this.index, required this.currentIndex, this.onTap});

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
        // bar, so the chrome stays thin and the tap still lands. 22 a side (not the original 10,
        // which only reached ~24px total — half the 44pt/48dp floor for the control that jumps
        // back to an earlier wizard step) makes the full hit target 48dp; the visible bar itself
        // is unchanged.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 4,
            decoration: BoxDecoration(
              color: reached ? AppColors.Y : context.colors.borderMedium,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
