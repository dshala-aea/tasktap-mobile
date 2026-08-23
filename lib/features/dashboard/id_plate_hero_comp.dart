import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The dashboard hero — cantiere safety-signage direction, approved.
///
/// A flat "ID plate" band, not a soft gradient hero: no shadow, no gradient, a stamped identity
/// plate a technician reads once and knows exactly where they stand — who, when, how much is
/// left. Yellow appears exactly once, on the count that still needs doing; everything else is
/// white-on-near-black. Proven against a real empty state and a real live-tracker state on
/// device before being approved to replace the old DashboardHero/ActiveJobCard pair, which this
/// superseded and which no longer exist in the tree.
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

    return ColoredBox(
      color: AppColors.CHARCOAL,
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
              // The plate's readout line — a stamped ID plate, not a stat-grid card. One rule
              // above and below, numerals doing the talking, yellow only where it's earned.
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: AppColors.WHITE.withAlpha(60)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
    final color = accent ? AppColors.Y : AppColors.WHITE;
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
            color: accent ? AppColors.Y : AppColors.WHITE.withAlpha(150),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
