import 'package:flutter/material.dart';
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

/// Floating latch-row bottom navigation — the case's own row of compartment latches.
///
/// This replaced a white floating pill with a 23 px radius and a fully-rounded active sub-pill —
/// recoloring that shape orange still reads as "the old pill, repainted," not a latch. A latch is
/// squared off, not round: the bar itself is machined at 10 px (not 23), each tab is a near-square
/// compartment at 6 px (not 19, which was pill-rounded enough to disappear into the bar), and the
/// active one shows a small tick engaged above it — the physical detail of a case latch actually
/// clicking down, not just a colour change. Case-shell (permanently dark, like the punch-clock
/// screens) ground, safety-orange active fill. Inactive tabs are icon-only in `onDarkMuted` — a
/// fixed dark surface needs the fixed-ink tokens, not the flipping ones (see
/// `AppColors.onDark`/`onDarkMuted` doc comment).
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
            color: AppColors.CHARCOAL,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(20), width: 0.5),
            boxShadow: context.colors.shadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The tick a latch shows when it's actually engaged, not just a colour swap. Space
            // reserved either way so the row below never shifts when a tab (de)activates.
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppRack.drawerOut,
              curve: AppRack.slideOut,
              width: 16,
              height: 3,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: active ? AppColors.Y : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AnimatedContainer(
              // The rack's own drawer movement, and it stops when the OS says stop. Both platforms
              // require this: "Remove animations" on Android and Reduce Motion on iOS both surface
              // as MediaQuery.disableAnimations, and a nav bar that keeps sliding through it is the
              // single most noticeable place to ignore the setting.
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppRack.drawerOut,
              curve: AppRack.slideOut,
              constraints: const BoxConstraints(minHeight: 40),
              padding: EdgeInsets.symmetric(horizontal: active ? 14 : 12, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.Y : Colors.transparent,
                // AppRack.insetRadius (4, derived from cellRadius), not the near-pill 19 this
                // used to carry — a latch is machined square, not rounded into a pill. Matches
                // every other "compartment inside a compartment" in the app rather than inventing
                // a fourth radius.
                borderRadius: BorderRadius.circular(AppRack.insetRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 18,
                    // The bar is CHARCOAL now, permanently dark regardless of app theme (see the
                    // punch-clock screens' own reasoning) — a flipping token like `inkMuted` is
                    // tuned against a light ground and goes near-invisible here. `onDarkMuted` is
                    // white at 75%, built for exactly this surface, and still clears AA against
                    // CHARCOAL.
                    color: active ? context.colors.brandOn : AppColors.onDarkMuted,
                  ),
                  if (active) ...[
                    const SizedBox(width: 8),
                    // The label is what gives when space runs out — an icon nobody can read is
                    // worse than a word that ends in an ellipsis, and the icon is what marks the
                    // tab.
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Sora',
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
          ],
        ),
      ),
    );
  }
}
