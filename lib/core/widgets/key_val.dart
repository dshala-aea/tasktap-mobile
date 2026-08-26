import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'app_tappable.dart';

/// Key–value display row / column.
///
/// Horizontal (default): Manrope 700/10 MUTED uppercase label (letterSpacing 0.3)
/// on the left + Manrope 13 DARK value on the right (ellipsis); 10 px vertical
/// padding; bottom 1 px BL divider.
///
/// Vertical variant: label above value (value fontSize 14).
///
/// Pass [onTap] to make the row navigate somewhere the value names (e.g. the customer this
/// ticket is for) — draws a chevron so the row reads as a control, not just a fact, the same
/// distinction the status pill already makes for itself elsewhere on ticket detail.
///
/// ```dart
/// KeyVal(label: 'Cliente', value: 'Rossi S.r.l.');
/// KeyVal(label: 'Data', value: '15/06/2026', vertical: true);
/// KeyVal(label: 'Cliente', value: 'Rossi S.r.l.', onTap: () => context.push(...));
/// ```
class KeyVal extends StatelessWidget {
  const KeyVal({
    super.key,
    required this.label,
    required this.value,
    this.vertical = false,
    this.showDivider = true,
    this.onTap,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool vertical;
  final bool showDivider;
  final VoidCallback? onTap;

  /// Overrides the value's default `context.colors.ink` — e.g. a red overdue date. Rare: most
  /// rows should read as plain facts, not warnings.
  final Color? valueColor;

  static TextStyle _labelStyle(BuildContext context) => TextStyle(
    fontFamily: 'Manrope',
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: context.colors.inkMuted,
    letterSpacing: 0.3,
  );

  @override
  Widget build(BuildContext context) {
    final Widget content = vertical ? _vertical(context) : _horizontal(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        if (showDivider) Divider(height: 1, thickness: 1, color: context.colors.borderLight),
      ],
    );
  }

  Widget _horizontal(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: _labelStyle(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: valueColor ?? context.colors.ink,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 14, color: context.colors.inkMuted),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return AppTappable(
      onTap: onTap,
      semanticLabel: '$label: $value. Tocca per aprire.',
      child: row,
    );
  }

  Widget _vertical(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _labelStyle(context)),
          const SizedBox(height: 4),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: context.colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
