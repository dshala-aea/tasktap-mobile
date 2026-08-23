import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'app_card.dart';
import 'app_tappable.dart';

/// One section of an [AppAccordion].
class AppAccordionItem {
  const AppAccordionItem({required this.label, required this.builder, this.badge});

  final String label;

  /// Built only while this section is open — a closed section's data provider is never touched,
  /// the same laziness a tab strip gives for free and an accordion has to earn on purpose.
  final WidgetBuilder builder;

  /// Optional trailing count/status, e.g. an unread or item count.
  final String? badge;
}

/// Single-open-at-a-time accordion, replacing a horizontal tab strip where the tab count itself
/// was the problem: seven tabs do not fit a phone width, and reading one meant a round trip —
/// scroll to the strip, choose, scroll back down — on every switch. An accordion turns that round
/// trip into a tap: every section name is always on screen, in one column, and opening one closes
/// whichever was open rather than stacking all seven expanded at once.
class AppAccordion extends StatefulWidget {
  const AppAccordion({super.key, required this.items, this.initialOpenIndex = 0});

  final List<AppAccordionItem> items;

  /// Which section starts open. Null opens none.
  final int? initialOpenIndex;

  @override
  State<AppAccordion> createState() => _AppAccordionState();
}

class _AppAccordionState extends State<AppAccordion> {
  late int? _openIndex = widget.initialOpenIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < widget.items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _Section(
            item: widget.items[i],
            open: _openIndex == i,
            onTap: () => setState(() => _openIndex = _openIndex == i ? null : i),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.item, required this.open, required this.onTap});

  final AppAccordionItem item;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTappable(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (item.badge != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      item.badge!,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: AppRack.detent,
                    curve: AppRack.slideOut,
                    child: Icon(LucideIcons.chevronRight, size: 16, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppRack.drawerOut,
            curve: AppRack.slideOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      0,
                      AppSpacing.base,
                      AppSpacing.base,
                    ),
                    child: Builder(builder: item.builder),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
