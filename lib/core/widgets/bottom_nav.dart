import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';

/// Default tab icons (exposed so screens/tests need not import lucide directly).
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
  const AppBottomNav({super.key, required this.currentIndex, required this.onTap, this.items});

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
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: context.colors.borderLight, width: 0.5),
            boxShadow: context.colors.shadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible, so the bar fits the phone rather than the phone fitting the bar. The
                // tabs' natural width is padding + icon + the active label, which came to two
                // pixels more than a 5.9" screen has and drew the striped overflow bar across the
                // bottom of every screen. Turn the system font size up and it is far more than
                // two. Loose fit: a tab still takes only what it needs when there is room.
                for (var i = 0; i < tabs.length; i++)
                  Flexible(
                    child: _NavTab(item: tabs[i], active: i == currentIndex, onTap: () => onTap(i)),
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
  const _NavTab({required this.item, required this.active, required this.onTap});

  final AppBottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      // Stays a GestureDetector, unlike the rest of the app's press targets (see
      // core/widgets/app_tappable.dart). The pill below animates its colour, padding and label
      // on every selection change, so a tap is already answered — visibly and immediately, by a
      // larger movement than a splash. Wrapping it in an AppTappable would hide the ink behind
      // the AnimatedContainer's own fill anyway, and lose the animation to keep it.
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          // The rack's own drawer movement, and it stops when the OS says stop. Both platforms
          // require this: "Remove animations" on Android and Reduce Motion on iOS both surface as
          // MediaQuery.disableAnimations, and a nav bar that keeps sliding through it is the
          // single most noticeable place to ignore the setting.
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppRack.drawerOut,
          curve: AppRack.slideOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: active ? 16 : 14, vertical: 10),
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
                // Inactive tabs were `inkDisabled` — #B4B4B4, which measures 1.9:1 on the white
                // pill. These are the app's five primary destinations, they are icon-only when
                // inactive, and a technician navigates by them one-handed in direct sun. 1.9:1
                // is not a low-emphasis treatment there, it is an invisible one. `inkMuted`
                // clears the 4.5:1 floor at 5.3:1 and still reads as clearly unselected against
                // the yellow pill.
                color: active ? context.colors.brandOn : context.colors.inkMuted,
              ),
              if (active) ...[
                const SizedBox(width: 8),
                // The label is what gives when space runs out — an icon nobody can read is worse
                // than a word that ends in an ellipsis, and the icon is what marks the tab.
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.brandOn,
                    ),
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
