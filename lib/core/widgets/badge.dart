import 'package:flutter/material.dart';

import 'app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// Compact rounded badge pill.
///
/// Spec: rounded 9 px radius, Inter 500/10 (sm: 9), pad 3/9 (sm: 2/7).
///
/// ```dart
/// AppBadge(label: '3');
/// AppBadge(label: 'Nuovo', small: true);
/// AppBadge(label: 'Tag', bgColor: AppColors.Y.withAlpha(31), fgColor: AppColors.Y);
/// ```
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.small = false,
    this.bgColor,
    this.fgColor,
    this.outlined = false,
  });

  final String label;
  final bool small;
  final Color? bgColor;
  final Color? fgColor;

  /// A rule-bordered flat badge instead of a filled pill — a stamped placard label, not a soft
  /// SaaS status chip. [fgColor] becomes the border and text; the fill stays the page's own
  /// surface, since a signage world reads status from an outline and a word, not a color fill.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final bg = bgColor ?? context.colors.bg3;
    final fg = fgColor ?? context.colors.ink;
    final fontSize = small ? 9.0 : 10.0;
    final vPad = small ? 2.0 : 3.0;
    final hPad = small ? 7.0 : 9.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : bg,
        border: outlined ? Border.all(color: fg, width: 1.5) : null,
        borderRadius: AppRack.insetShape,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: fontSize,
            fontWeight: outlined ? FontWeight.w700 : FontWeight.w500,
            color: fg,
            letterSpacing: outlined ? 0.4 : 0.1,
          ),
        ),
      ),
    );
  }
}

/// Selection chip — neutral (inactive) or Vetro tint fill / white (active).
///
/// Spec: 1 px border, 8 px radius, Inter 500/11, pad 5/10.
///
/// ```dart
/// AppChip(label: 'Oggi', active: true, onTap: () {});
/// AppChip(label: 'Settimana', onTap: () {});
/// ```
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.Y : context.colors.surface;
    final fg = active ? Colors.white : context.colors.ink;
    final borderColor = active ? AppColors.Y : context.colors.borderMedium;

    const radius = AppRack.insetRadius;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      child: AppTappable(
        onTap: onTap,
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}
