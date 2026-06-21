import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Key–value display row / column.
///
/// Horizontal (default): Manrope 700/10 MUTED uppercase label (letterSpacing 0.3)
/// on the left + Manrope 13 DARK value on the right (ellipsis); 10 px vertical
/// padding; bottom 1 px BL divider.
///
/// Vertical variant: label above value (value fontSize 14).
///
/// ```dart
/// KeyVal(label: 'Cliente', value: 'Rossi S.r.l.');
/// KeyVal(label: 'Data', value: '15/06/2026', vertical: true);
/// ```
class KeyVal extends StatelessWidget {
  const KeyVal({
    super.key,
    required this.label,
    required this.value,
    this.vertical = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool vertical;
  final bool showDivider;

  static TextStyle get _labelStyle => GoogleFonts.manrope(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.MUTED,
        letterSpacing: 0.3,
      );

  @override
  Widget build(BuildContext context) {
    final Widget content = vertical ? _vertical() : _horizontal();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.BL,
          ),
      ],
    );
  }

  Widget _horizontal() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: _labelStyle,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.DARK,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vertical() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _labelStyle),
          const SizedBox(height: 4),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.DARK,
            ),
          ),
        ],
      ),
    );
  }
}
