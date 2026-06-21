import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// A single statistic (label + value).
class StatItem {
  const StatItem({required this.label, required this.value});

  final String label;
  final String value;
}

/// 2×2 stats grid with DIV dividers.
///
/// Spec: Manrope 12 MUTED label (pre-line) + Manrope 500/36 DARK value.
///
/// ```dart
/// StatsGrid(items: const [
///   StatItem(label: 'Ticket\naperti', value: '8'),
///   StatItem(label: 'Ore\noggi', value: '6.5'),
///   StatItem(label: 'Rapportini', value: '12'),
///   StatItem(label: 'In attesa', value: '3'),
/// ]);
/// ```
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.items});

  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < items.length; row += 2) ...[
          if (row > 0) const Divider(height: 1, color: AppColors.DIV),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Cell(item: items[row])),
                const VerticalDivider(width: 1, color: AppColors.DIV),
                Expanded(
                  child: row + 1 < items.length
                      ? _Cell(item: items[row + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.MUTED,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: GoogleFonts.manrope(
              fontSize: 36,
              fontWeight: FontWeight.w500,
              color: AppColors.DARK,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}
