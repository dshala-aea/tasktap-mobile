import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Default tab icons (exposed so screens/tests need not import lucide directly).
abstract final class AppBottomNavIcons {
  static const IconData dashboard = LucideIcons.home;
  static const IconData ticket = LucideIcons.ticket;
  static const IconData cantieri = LucideIcons.hardHat;
  static const IconData calendario = LucideIcons.calendar;
  static const IconData altro = LucideIcons.moreHorizontal;
}

/// A single bottom-navigation tab descriptor.
class AppBottomNavItem {
  const AppBottomNavItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// Floating bottom navigation — a flat Documento sheet (`context.colors.surface` + a hairline
/// border), the same material every card and the header now share. `AppColors.Y` (stamp red, the
/// one deliberately-saturated accent in the system) marks the active tab as a flat fill — no
/// blur, no gradient.
///
/// The active tab expands horizontally to reveal its icon + complete label. The expansion is
/// animated so switching tabs feels like the active pill moves rather than the entire navigation
/// jumping between layouts.
///
/// This used to be Vetro: a frosted `BackdropFilter` bar with a tint→tintStrong gradient on the
/// active pill. DESIGN.md's Il Documento system bans both (paper, not glass; a flat accent fill,
/// not a gradient) the same way it does for every other surface in the app.
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
    AppBottomNavItem(
      icon: AppBottomNavIcons.dashboard,
      label: 'Dashboard',
    ),
    AppBottomNavItem(
      icon: AppBottomNavIcons.ticket,
      label: 'Ticket',
    ),
    AppBottomNavItem(
      icon: AppBottomNavIcons.cantieri,
      label: 'Cantieri',
    ),
    AppBottomNavItem(
      icon: AppBottomNavIcons.calendario,
      label: 'Calendario',
    ),
    AppBottomNavItem(
      icon: AppBottomNavIcons.altro,
      label: 'Altro',
    ),
  ];

  /// Above this window width (a tablet/expanded window, not a phone in any orientation this app
  /// otherwise targets) the shell switches to [_buildRail].
  static const double wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final tabs = items ?? defaultItems;
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    return wide
        ? _buildRail(context, tabs)
        : _buildBar(context, tabs);
  }

  /// Compact width (phone).
  ///
  /// The active item receives substantially more horizontal space so its complete icon + label
  /// can be displayed. Width changes are animated when the selected tab changes.
  Widget _buildBar(
    BuildContext context,
    List<AppBottomNavItem> tabs,
  ) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 0, 19, 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: context.colors.shadow,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: context.colors.surface,
              border: Border.all(
                color: context.colors.borderLight,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;

                  // The active tab needs enough room for labels such as "Calendario"
                  // and "Dashboard" without truncation.
                  //
                  // The minimum inactive width keeps the icon comfortably tappable.
                  const minInactiveWidth = 48.0;
                  const preferredActiveWidth = 96.0;

                  final inactiveCount = tabs.length - 1;

                  final activeWidth = tabs.length <= 1
                      ? availableWidth
                      : availableWidth >=
                              preferredActiveWidth +
                                  (inactiveCount * minInactiveWidth)
                          ? preferredActiveWidth
                          : (availableWidth -
                                  (inactiveCount * minInactiveWidth))
                              .clamp(0.0, preferredActiveWidth);

                  final remainingWidth = availableWidth - activeWidth;

                  final inactiveWidth = inactiveCount > 0
                      ? remainingWidth / inactiveCount
                      : 0.0;

                  return Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        _AnimatedNavSlot(
                          width: i == currentIndex
                              ? activeWidth
                              : inactiveWidth,
                          duration: reduceMotion
                              ? Duration.zero
                              : AppRack.drawerOut,
                          child: _NavTab(
                            item: tabs[i],
                            active: i == currentIndex,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ≥[wideBreakpoint] (tablet/expanded window) — same tabs, same flat-fill active-state, laid out
  /// as a fixed vertical rail along the leading edge.
  Widget _buildRail(
    BuildContext context,
    List<AppBottomNavItem> tabs,
  ) {
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.colors.shadow,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: context.colors.surface,
              border: Border.all(
                color: context.colors.borderLight,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == tabs.length - 1 ? 0 : 14,
                      ),
                      child: _NavTab(
                        item: tabs[i],
                        active: i == currentIndex,
                        onTap: () => onTap(i),
                        vertical: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated horizontal slot used by the phone bottom navigation.
///
/// Unlike [Expanded] with a changing `flex`, this animates the actual width continuously.
class _AnimatedNavSlot extends StatelessWidget {
  const _AnimatedNavSlot({
    required this.width,
    required this.duration,
    required this.child,
  });

  final double width;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: AppRack.slideOut,
      width: width,
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.active,
    required this.onTap,
    this.vertical = false,
  });

  final AppBottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  /// The wide-window rail's orientation — icon-above-label instead of icon-beside-label.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      item.label,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      overflow: TextOverflow.visible,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        height: 1.0,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppRack.drawerOut,
          curve: AppRack.slideOut,
          constraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          padding: vertical
              ? EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: active ? 8 : 12,
                )
              : EdgeInsets.symmetric(
                  horizontal: active ? 10 : 12,
                  vertical: active ? 7 : 12,
                ),
          decoration: BoxDecoration(
            color: active ? AppColors.Y : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: active
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 4),

                    // Scale down only when absolutely necessary. The text itself is
                    // never ellipsized or cropped, so "Calendario" remains readable.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: label,
                    ),
                  ],
                )
              : Icon(
                  item.icon,
                  size: 18,
                  color: context.colors.inkMuted,
                ),
        ),
      ),
    );
  }
}
