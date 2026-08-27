import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'vetro_glass.dart';

/// Search input — a real frosted [VetroGlass] panel, 12 px radius, pad 10/14, search icon (16,
/// MUTED) + 14 px input. Spec margin: 0 / 19 / 12.
///
/// Was a solid `bg3` fill with a `borderMedium` rule and the Cassetta rack's inset radius — a
/// leftover of the pre-Vetro shell metaphor on the two screens (ticket list, rapportini list)
/// that otherwise switched fully to Vetro glass. Now built on the same `v.glassFill`/`v.glassBorder`
/// pair every other Vetro surface reads from `context.vetro`, so it flips with the app theme
/// instead of staying a flat plate.
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: VetroGlass(
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: context.colors.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: TextStyle(fontSize: 14, color: context.colors.ink),
                  cursorColor: context.colors.ink,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
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
