import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Search input — BG3 bg, 12 px radius, pad 10/14, search icon (16, MUTED) +
/// Manrope 14 input. Spec margin: 0 / 19 / 12.
///
/// ```dart
/// AppSearchBar(hint: 'Cerca ticket…', onChanged: (q) {});
/// ```
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    this.controller,
    this.hint = 'Cerca…',
    this.onChanged,
    this.margin = const EdgeInsets.fromLTRB(19, 0, 19, 12),
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.bg3,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: context.colors.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: context.colors.ink,
                  ),
                  cursorColor: context.colors.ink,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 14,
                      color: context.colors.inkDisabled,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
