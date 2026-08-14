import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// Compact rounded badge pill.
///
/// Spec: rounded 9 px radius, Manrope 500/10 (sm: 9), pad 3/9 (sm: 2/7).
///
/// ```dart
/// AppBadge(label: '3');
/// AppBadge(label: 'Nuovo', small: true);
/// AppBadge(label: 'Tag', bgColor: AppColors.Y, fgColor: context.colors.ink);
/// ```
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.small = false,
    this.bgColor,
    this.fgColor,
  });

  final String label;
  final bool small;
  final Color? bgColor;
  final Color? fgColor;

  @override
  Widget build(BuildContext context) {
    final bg = bgColor ?? context.colors.bg3;
    final fg = fgColor ?? context.colors.ink;
    final fontSize = small ? 9.0 : 10.0;
    final vPad = small ? 2.0 : 3.0;
    final hPad = small ? 7.0 : 9.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        // 3, not 9. A badge is ink printed on the label card, and printed marks on a machined
        // label are not lozenges. At this size the difference is small and it is the difference
        // between the app looking drawn and looking specified.
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: fg,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

/// Selection chip — white/DARK (inactive) or DARK/white (active).
///
/// Spec: 1 px border, 5 px radius, Manrope 500/11, pad 5/10.
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
    final bg = active ? context.colors.surfaceInverse : context.colors.surface;
    final fg = active ? context.colors.inkInverse : context.colors.ink;
    final borderColor = active ? context.colors.surfaceInverse : context.colors.borderMedium;

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
            style: GoogleFonts.manrope(
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
