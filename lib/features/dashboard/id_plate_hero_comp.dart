import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The dashboard hero — flat Documento direction.
///
/// A flat "ID plate" band: `AppColors.Y`, no shadow, no gradient, no blur — the treatment
/// on-device testing originally approved for cantiere safety-signage legibility, and what this
/// hero returns to now that the Vetro glass/gradient detour (module-by-module, see this app's own
/// nav-restructure history) has reached Dashboard's turn. `AppColors.Y` is used directly rather
/// than through `context.colors`: it's the one theme-invariant brand accent, same status as every
/// other flat `AppColors.Y` fill in the app (`AppButton.primary`, `AppFab`, the active bottom-nav
/// tab).
class IdPlateHeroComp extends StatelessWidget {
  const IdPlateHeroComp({
    super.key,
    required this.userName,
    required this.todayCount,
    required this.completedCount,
    this.actions = const [],
    this.child,
  });

  final String userName;
  final int todayCount;
  final int completedCount;
  final List<Widget> actions;
  final Widget? child;

  /// Quiet (non-accent) text on this hero's solid `AppColors.Y` band. Neither color flips, so
  /// this isn't a dark-mode bug — it's a flat contrast failure found by hand-computing WCAG
  /// contrast during a re-critique: the previous `WHITE.withAlpha(150)` (~59% opacity) composites
  /// to only ≈2.87:1 against `#C03221`, under even the relaxed 3:1 large-text floor. 230 (~90%
  /// opacity) composites to ≈4.86:1, clearing the 4.5:1 floor this small (10-12px) text needs.
  /// The size/weight/case gap against the value text above it already carries the visual
  /// hierarchy — opacity was never load-bearing for that, only for contrast it was failing.
  static const _quietOnY = Color(0xE6FFFFFF); // white, 230/255 ≈ 90%

  @override
  Widget build(BuildContext context) {
    final remaining = todayCount - completedCount;
    final dateLabel = DateFormat(
      'EEEE d MMM',
      'it',
    ).format(DateTime.now()).toUpperCase();

    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.Y),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.base,
            AppSpacing.pagePadding,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // Was .start: the 44dp HeaderIconBtn actions are taller than the 26px username
                // line, so top-aligning them against a shorter line reads as the icons hanging low
                // rather than sitting level with the name. .center (this Row's own default — kept
                // explicit for clarity) lines the icons up with the text's vertical middle instead.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      userName.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Archivo Narrow',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.WHITE,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  for (final action in actions) ...[
                    const SizedBox(width: 4),
                    action,
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _quietOnY,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              // Restores the readout `todayCount`/`completedCount` were already being computed
              // for — dropped silently when this hero flattened onto Documento (both params, and
              // `_Readout` itself, were left wired but unrendered; confirmed dead by the analyzer,
              // not just suspected). `remaining` accents when there's still work today, quiet
              // once the count hits zero — same "accent marks what needs attention" discipline
              // the rest of the app already holds to.
              Row(
                children: [
                  _Readout(value: '$todayCount', label: 'INTERVENTI OGGI', accent: false),
                  const SizedBox(width: 28),
                  _Readout(
                    value: '$remaining',
                    label: 'DA FARE',
                    accent: remaining > 0,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (child != null) ...[
                const SizedBox(height: AppSpacing.base),
                child!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.value,
    required this.label,
    required this.accent,
  });

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    // Sits directly on the hero's own solid AppColors.Y band (see IdPlateHeroComp.build), not a
    // card — `brandOn` (near-white, ≥5.37:1 on Y per that token's own doc comment) is what every
    // other value on this band already reads in, matching the username line above it. `accent`
    // stays full brandOn rather than reaching for AppColors.Y-on-Y, which would be unreadable on
    // its own background; the weight/size step against the quiet [IdPlateHeroComp._quietOnY]
    // label is what marks "needs attention" here instead.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Archivo Narrow',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: context.colors.brandOn,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Archivo',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: accent ? context.colors.brandOn : IdPlateHeroComp._quietOnY,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
