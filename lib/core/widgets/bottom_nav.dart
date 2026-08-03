import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';

/// Default tab icons (exposed so screens/tests need not import lucide directly).
abstract final class AppBottomNavIcons {
  static const IconData dashboard = LucideIcons.home;
  static const IconData ticket = LucideIcons.ticket;
  static const IconData timbra = LucideIcons.clock;
  static const IconData calendario = LucideIcons.calendar;
  static const IconData altro = LucideIcons.moreHorizontal;
}

/// A single bottom-navigation tab descriptor.
class AppBottomNavItem {
  const AppBottomNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Floating-pill bottom navigation.
///
/// Spec: white floating pill, 23 px radius, 0.5 px BL border, SH shadow,
/// 19 px horizontal margin, 18 px bottom. 5 tabs (Dashboard / Ticket / Timbra /
/// Calendario / Altro). Active tab: yellow bg, 19 px radius, icon (18, DARK) +
/// Sora 600/12 label. Inactive: icon only (DIS). 200 ms transition.
///
/// ```dart
/// AppBottomNav(currentIndex: 0, onTap: (i) => setState(() => index = i));
/// ```
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Defaults to the 5 standard tabs when omitted.
  final List<AppBottomNavItem>? items;

  static const List<AppBottomNavItem> defaultItems = [
    AppBottomNavItem(icon: AppBottomNavIcons.dashboard, label: 'Dashboard'),
    AppBottomNavItem(icon: AppBottomNavIcons.ticket, label: 'Ticket'),
    AppBottomNavItem(icon: AppBottomNavIcons.timbra, label: 'Timbra'),
    AppBottomNavItem(icon: AppBottomNavIcons.calendario, label: 'Calendario'),
    AppBottomNavItem(icon: AppBottomNavIcons.altro, label: 'Altro'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = items ?? defaultItems;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 0, 19, 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.WHITE,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: AppColors.BL, width: 0.5),
            boxShadow: AppColors.SH,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _NavTab(
                    item: tabs[i],
                    active: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppBottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: active ? 16 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.Y : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 18,
                color: active ? AppColors.DARK : AppColors.DIS,
              ),
              if (active) ...[
                const SizedBox(width: 8),
                Text(
                  item.label,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.DARK,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
