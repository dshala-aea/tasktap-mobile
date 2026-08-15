import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

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
      child: Container(
        // A compartment, not a pill: the search field is a slot cut into the rack, so it takes
        // the inset radius and a machined edge. It also gains a real border — on a bone ground
        // the old borderless bg3 fill had almost no edge at all outdoors.
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: context.colors.bg3,
          borderRadius: AppRack.insetShape,
          border: Border.all(color: context.colors.borderMedium),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: context.colors.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: TextStyle(fontFamily: 'Manrope', fontSize: 14, color: context.colors.ink),
                  cursorColor: context.colors.ink,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontFamily: 'Manrope',
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
