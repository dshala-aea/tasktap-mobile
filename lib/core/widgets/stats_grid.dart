import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// A single statistic (label + value).
class StatItem {
  const StatItem({required this.label, required this.value});

  final String label;
  final String value;
}

/// The day's manifest: counts in one strip, the way a load list prints them.
///
/// This was a 2×2 grid of 36pt figures — the hero-metric template. Two problems, and only one of
/// them was taste:
///
/// 1. Four 36pt numbers and their labels took roughly half the viewport above the fold, which
///    pushed "Prossimi interventi" — the only actionable content on the dashboard — below it. The
///    numbers are glanceable at 20pt; the appointments are not readable at zero.
/// 2. A count of four is a quantity, not a headline. The van's load list prints quantities in a
///    row with rules between them, and that is both the truthful form and the compact one.
///
/// The API is unchanged, so the dashboard's four [StatItem]s render as a strip without a diff at
/// the call site. Labels may still contain the old newlines; they are flattened here rather than
/// at every call site.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.items});

  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, color: context.colors.divider),
            Expanded(child: _Cell(item: items[i])),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The labels were authored for a two-line grid cell.
    final label = item.label.replaceAll('\n', ' ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.inkMuted,
              letterSpacing: 0.4,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          // Sora, and only 20pt. This is the label stamped on the drawer, not a headline.
          Text(
            item.value,
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.ink,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
