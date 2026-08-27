import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_rack.dart';
import '../theme/app_vetro_palette.dart';

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

/// Floating bottom navigation — Vetro's tint→tintStrong gradient marks the active tab, on a
/// frosted [VetroGlass]-style bar that flips with the app theme, the same material every card and
/// the header now share. This used to self-paint a permanently-dark CHARCOAL plate — a leftover
/// of the pre-Vetro "Cassetta" shell metaphor, not something the actual approved Vetro reference
/// (light frosted glass throughout, no dark chrome) ever called for.
///
/// Replaced: safety-orange (`AppColors.Y`) active fill → the Vetro gradient every other active/
/// primary surface in the app uses (VetroButton, the rapportino completion card, ...); the
/// "machined latch" 4px corner + tick-engaged-above indicator → a single 12px pill (VetroButton's
/// own compact radius) whose gradient fill *is* the state, the way a VetroCompartmentTile's or
/// VetroButton's does — a second indicator on top of a colour change was the Cassetta metaphor's
/// own idea, not one Vetro's state language needs. Sora → Inter, matching every other Vetro
/// surface. The active gradient itself still reads from `AppVetroColors` (fixed): the pill's own
/// colours are the one deliberately-saturated accent in the system and must not desaturate for
/// dark mode the way `context.vetro.dark`'s tint does.
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
    final v = context.vetro;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 0, 19, 18),
        // Shadow lives on this outer box, not the one BackdropFilter blurs — a BoxShadow paints
        // outside its own bounds, and the ClipRRect around the blur would have silently clipped
        // it away otherwise.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: context.colors.shadow,
          ),
          // RepaintBoundary around the clip+blur, not just inside it: without its own compositing
          // layer here, this bar's BackdropFilter painted a second, unclipped copy of the active
          // tab's gradient pill into the system gesture-nav strip below it — a real leak this
          // device reproduced every launch, not a one-off frame.
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: AppVetroColors.blurSigma,
                  sigmaY: AppVetroColors.blurSigma,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: v.glassFill,
                    border: Border.all(color: v.glassBorder, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Flexible, so the bar fits the phone rather than the phone fitting the
                        // bar. The tabs' natural width is padding + icon + the active label,
                        // which came to two pixels more than a 5.9" screen has and drew the
                        // striped overflow bar across the bottom of every screen. Turn the
                        // system font size up and it is far more than two. Loose fit: a tab
                        // still takes only what it needs when there is room.
                        for (var i = 0; i < tabs.length; i++)
                          Flexible(
                            child: _NavTab(
                              item: tabs[i],
                              active: i == currentIndex,
                              onTap: () => onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
          // Both platforms require the reduced-motion guard: "Remove animations" on Android and
          // Reduce Motion on iOS both surface as MediaQuery.disableAnimations, and a nav bar that
          // keeps sliding through it is the single most noticeable place to ignore the setting.
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppRack.drawerOut,
          curve: AppRack.slideOut,
          // 48dp, not 40 — this is the app's single global navigation control, tapped constantly
          // by a gloved technician one-handed, and 40 sat under both the 44pt (iOS) and 48dp
          // (Android) touch-target floors.
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(horizontal: active ? 14 : 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppVetroColors.tint, AppVetroColors.tintStrong],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 18,
                // The active tab sits on its own saturated gradient pill regardless of theme, so
                // its icon stays white either way. Inactive sits directly on the flipping glass
                // bar, so it reads `inkMuted` like every other secondary icon in the app.
                color: active ? Colors.white : context.colors.inkMuted,
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
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
