import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'app_tappable.dart';

/// A single tab descriptor with an optional count pill.
class AppTab {
  const AppTab({required this.label, this.count});

  final String label;
  final int? count;
}

/// Horizontal scrolling tabs — Manrope 700/12, active DARK + 2 px Y underline
/// (inactive MUTED), 12/14 padding, optional count pill.
///
/// ```dart
/// AppTabs(
///   tabs: const [AppTab(label: 'Tutti', count: 12), AppTab(label: 'Aperti')],
///   selectedIndex: 0,
///   onSelected: (i) {},
/// );
/// ```
class AppTabs extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final active = i == selectedIndex;
          final tab = tabs[i];
          return Semantics(
            button: true,
            selected: active,
            label: tab.label,
            child: AppTappable(
              onTap: () => onSelected(i),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: Border(
                bottom: BorderSide(
                  color: active ? AppColors.Y : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.label,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? AppColors.DARK : AppColors.MUTED,
                      ),
                    ),
                    if (tab.count != null) ...[
                      const SizedBox(width: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: active ? AppColors.DARK : AppColors.BG3,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          child: Text(
                            '${tab.count}',
                            style: GoogleFonts.manrope(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: active ? AppColors.WHITE : AppColors.MUTED,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ),
          );
        },
      ),
    );
  }
}
