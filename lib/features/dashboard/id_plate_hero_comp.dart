import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/vetro_glass.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The dashboard hero — Vetro glass direction.
///
/// Was a flat "ID plate" band (no shadow, no gradient), approved after on-device testing for
/// cantiere safety-signage legibility. Re-skinned to full Vetro glass — same call made for
/// Timbra (Module #1), whose identical flat/no-glass rationale was overridden in favour of the
/// app-wide Vetro identity. Fixed `AppVetroColors`, not flipping `context.vetro`: this hero is a
/// permanently-dark ground regardless of app theme, same status as `AppColors.punchGround`.
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

  @override
  Widget build(BuildContext context) {
    final remaining = todayCount - completedCount;
    final dateLabel = DateFormat('EEEE d MMM', 'it').format(DateTime.now()).toUpperCase();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppVetroColors.tint, AppVetroColors.tintStrong],
        ),
      ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      userName.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Sora',
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
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.WHITE.withAlpha(150),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              // The plate's readout line — a glass panel over the gradient, numerals doing the
              // talking. Was a bordered flat band; VetroGlass gives it the same real translucency
              // every other Vetro secondary surface uses.
              VetroGlass(
                fill: AppVetroColors.glassFillOnDark,
                border: AppVetroColors.glassBorderOnDark,
                borderRadius: BorderRadius.circular(16),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: AppSpacing.base,
                ),
                child: Row(
                  children: [
                    _Readout(value: '$todayCount', label: 'JOB OGGI', accent: false),
                    Container(
                      width: 1,
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                      color: AppColors.WHITE.withAlpha(40),
                    ),
                    _Readout(
                      value: '$remaining',
                      label: remaining == 1 ? 'DA FARE' : 'DA FARE',
                      accent: remaining > 0,
                    ),
                  ],
                ),
              ),
              if (child != null) ...[const SizedBox(height: AppSpacing.base), child!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.value, required this.label, required this.accent});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    // Was AppColors.Y (safety-orange) for the accented readout — dropped on the gradient ground,
    // where that accent no longer has the contrast it had against flat CHARCOAL. Full-opacity
    // white for the accent, dimmed white for the calm one, same distinction the label already
    // made.
    const color = AppColors.WHITE;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: accent ? AppColors.WHITE : AppColors.WHITE.withAlpha(150),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
