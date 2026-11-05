import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Search input — the prototype's flat sheet: 1px rule, 2px radius, search icon (16, MUTED) and
/// an 11px input. Kept at a 44px minimum height for the touch target. Spec margin: 0 / 19 / 12.
///
/// Was a solid `bg3` fill with a `borderMedium` rule and the Cassetta rack's inset radius — a
/// leftover of the pre-Vetro shell metaphor on the two screens (ticket list, rapportini list).
/// Now built on the same `context.colors.surface`/`context.colors.borderLight` pair every other
/// Documento surface reads from `context.colors`, so it flips with the app theme instead of
/// staying a flat plate. The 2px radius and 11px type are the list prototype's own values.
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
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.pagePadding,
      0,
      AppSpacing.pagePadding,
      AppSpacing.md,
    ),
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRack.freeShape,
            border: Border.all(color: context.colors.borderLight),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: 16,
                  color: context.colors.inkMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: TextStyle(fontSize: 11, color: context.colors.ink),
                    cursorColor: context.colors.ink,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: context.colors.inkDisabled,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
