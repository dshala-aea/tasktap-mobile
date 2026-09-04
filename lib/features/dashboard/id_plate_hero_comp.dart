import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_card.dart';
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

  @override
  Widget build(BuildContext context) {
    final remaining = todayCount - completedCount;
    final dateLabel = DateFormat('EEEE d MMM', 'it').format(DateTime.now()).toUpperCase();

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      userName.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Inter',
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
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.WHITE.withAlpha(150),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              // The plate's readout line — a flat card over the accent band, numerals doing the
              // talking. Was a Vetro glass panel; AppCard gives it the same flat sheet + hairline
              // every other Documento secondary surface uses, its ink read through `context.colors`
              // like any other card (the surrounding band, not this card, is the fixed element —
              // see this file's own header comment).
              AppCard(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: AppSpacing.base,
                ),
                // Scales down rather than overflowing, same treatment as _LiveClock in
                // timbra_screen.dart: at large accessibility text sizes the two readouts'
                // 32px numerals no longer fit side by side in the available width.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Readout(value: '$todayCount', label: 'JOB OGGI', accent: false),
                      Container(
                        width: 1,
                        height: 32,
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        color: context.colors.borderLight,
                      ),
                      _Readout(
                        value: '$remaining',
                        label: remaining == 1 ? 'DA FARE' : 'DA FARE',
                        accent: remaining > 0,
                      ),
                    ],
                  ),
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
    // This readout now sits on a plain AppCard (the flat-Documento replacement for the old Vetro
    // glass chip — see build() above), so its ink reads through `context.colors` like any other
    // card's text, not the fixed white this needed against the old dark/glass ground. AppColors.Y
    // for the accented readout, same "one accent marks emphasis" language badge.dart/AppTabs
    // already use, matching this readout's own pre-Vetro flat treatment.
    final color = context.colors.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
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
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: accent ? AppColors.Y : context.colors.inkMuted,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
