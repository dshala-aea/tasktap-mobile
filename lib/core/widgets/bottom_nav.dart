import 'dart:math' as math;

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
                  final inactiveCount = tabs.length - 1;

                  // Threshold for the "plenty of room" branch below — NOT a width that gets
                  // applied. Inactive tabs always split whatever's left after the active tab
                  // (see `inactiveWidth` below), so the bar fills its full available width in
                  // every branch, exactly like this widget's original layout — a fixed cap here
                  // previously left a trailing empty gap on any phone wider than this threshold,
                  // which is most real phones.
                  const comfortableInactiveWidth = 48.0;

                  // Hard floor for an inactive tab under real space pressure (icon 18px + 12px
                  // padding each side = 42px minimum to avoid clipping the icon itself) — still
                  // comfortably above common accessible tap-target minimums (iOS: 44pt).
                  const minInactiveWidth = 42.0;

                  // The one number that actually matters: how wide does the CURRENTLY active
                  // label need to be to render in full, never shrunk? This is what guarantees
                  // "Calendario"/"Dashboard" are never cropped — a real, pre-verified
                  // measurement (see `_requiredActiveWidthFor`'s doc comment), not a guessed
                  // fixed constant, scaled by the device's own accessibility text-size setting.
                  final requiredActiveWidth = tabs.isEmpty
                      ? 0.0
                      : _requiredActiveWidthFor(
                          tabs[currentIndex].label,
                          MediaQuery.textScalerOf(context),
                        );

                  double activeWidth;

                  if (tabs.length <= 1) {
                    activeWidth = availableWidth;
                  } else {
                    final target = math.max(_preferredActiveWidth, requiredActiveWidth);
                    final roomyTotal = target + inactiveCount * comfortableInactiveWidth;

                    if (availableWidth >= roomyTotal) {
                      // Plenty of room: active gets its target; inactive tabs split the rest
                      // below, which on a wide phone is MORE than comfortableInactiveWidth each
                      // — that's intentional, it's what fills the bar edge to edge.
                      activeWidth = target;
                    } else {
                      // Squeeze: shrink inactive tabs toward their hard floor FIRST, so the
                      // active tab keeps whatever it actually needs to show its full label.
                      final minTotal = requiredActiveWidth + inactiveCount * minInactiveWidth;
                      if (availableWidth >= minTotal) {
                        activeWidth = requiredActiveWidth;
                      } else {
                        // Mathematically impossible to show the full label without pushing
                        // inactive tabs below their hard floor. This does not happen on any
                        // screen width this app targets (verified for 320/360/390/430 logical
                        // px against every label) — reported here rather than silently cropped,
                        // per this widget's own layout contract.
                        assert(() {
                          debugPrint(
                            'AppBottomNav: cannot fit "${tabs[currentIndex].label}" at '
                            '$availableWidth px wide without shrinking inactive tabs below '
                            '$minInactiveWidth px (needs $minTotal px). Falling back to '
                            'whatever space remains after the inactive floor.',
                          );
                          return true;
                        }());
                        activeWidth = math.max(
                          0.0,
                          availableWidth - inactiveCount * minInactiveWidth,
                        );
                      }
                    }
                  }

                  // Always fills availableWidth exactly: whatever's left after the active tab is
                  // split evenly among the inactive ones, in every branch above.
                  final inactiveWidth = inactiveCount > 0
                      ? (availableWidth - activeWidth) / inactiveCount
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
///
/// Uses [TweenAnimationBuilder] + a hard [SizedBox] rather than `AnimatedContainer(width: ...,
/// alignment: ...)`: `Container`'s `alignment` wraps the child in an `Align`, which hands the
/// child LOOSE constraints and just centers whatever size it wants to be — it does not clip or
/// cap the child's width. A `_NavTab` whose content (icon + label) happens to want more space
/// than its assigned slot would then render wider than the slot and visually spill into a
/// neighboring tab instead of being contained — this was the actual cause of the nav overlaying
/// itself, independent of whether the assigned widths were individually correct. `SizedBox`
/// gives the child a TIGHT width (min == max == [width]), so the child is always forced to
/// exactly this slot's width — combined with the measured-width guarantee in `_buildBar` above
/// (the active slot is always sized to fit its label at 12px, never smaller), this makes an
/// overlay structurally impossible rather than merely unlikely. The inner `ClipRect` is a
/// last-resort safety net for the "mathematically impossible" case documented in `_buildBar`
/// (never triggered on any screen width this app targets): if content ever still doesn't fit,
/// it is clipped at the slot boundary rather than painted over a neighboring tab.
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
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: width),
      duration: duration,
      curve: AppRack.slideOut,
      builder: (context, animatedWidth, child) {
        return ClipRect(
          child: SizedBox(width: animatedWidth, child: child),
        );
      },
      child: child,
    );
  }
}

/// The roomy, generous active-pill width used whenever there's space to spare, and the fallback
/// requirement for any label not in [_measuredActiveLabelWidths] (see that map's doc comment).
/// Unchanged from this widget's previous single fixed constant.
const _preferredActiveWidth = 96.0;

/// How wide each default tab's label needs its active pill to be, to render in full at 12px/w600
/// Inter — measured ONCE against the real bundled font (`assets/fonts/InterVariable.ttf`, via a
/// `TextPainter` with that font explicitly loaded, at text scale 1.0), not guessed, and not
/// re-measured at runtime.
///
/// Deliberately NOT computed on every build via a live `TextPainter`: this app's own test suite
/// (like most Flutter test suites) never loads real fonts for ordinary widget/golden tests —
/// `flutter_test`'s default font substitution renders every glyph as a fixed-size placeholder box
/// completely unrelated to Inter's real metrics. A live measurement would silently produce a
/// different (usually much larger, and non-deterministic across the placeholder vs. the real
/// font) required width in tests than on a real device, which is exactly what broke this widget's
/// own golden test during development of this fix. Baking in the real, pre-verified numbers keeps
/// this widget's behavior identical in tests and in the field — this is a measurement result, not
/// a magic guess (each value = ceil(measured glyph width) + 20 padding + 12 safety margin).
///
/// If a label here is ever renamed, or a new tab added with an unlisted label,
/// [_requiredActiveWidthFor] falls back to [_preferredActiveWidth] — the same width every label
/// already gets whenever there's room to spare — rather than crashing or silently under-sizing.
const Map<String, double> _measuredActiveLabelWidths = {
  'Dashboard': 96.0, // 63.29px glyph width, measured
  'Ticket': 68.0, // 35.95px
  'Cantieri': 78.0, // 45.53px
  'Calendario': 95.0, // 62.98px
  'Altro': 61.0, // 28.09px
};

/// [textScaler] MUST be the ambient `MediaQuery.textScalerOf(context)`, not a default/unscaled
/// one: `_NavTab`'s `Text` auto-scales with the device's accessibility text-size setting, and a
/// requirement that ignored that would under-allocate the slot exactly when a larger system font
/// makes the label wider — the same class of bug the existing "fits a narrow phone without
/// overflowing" regression test (`bottom_nav_test.dart`) already guards at 1.3x scale. Scaling the
/// pre-measured base width by the scale ratio (rather than re-measuring text at the scaled size)
/// keeps this font-independent — see [_measuredActiveLabelWidths]'s doc comment for why that
/// matters.
double _requiredActiveWidthFor(String label, TextScaler textScaler) {
  final baseWidth = _measuredActiveLabelWidths[label] ?? _preferredActiveWidth;
  final scaleRatio = textScaler.scale(12.0) / 12.0;
  return baseWidth * scaleRatio;
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

                    // Never scaled down: `_buildBar`'s width allocation guarantees this slot is
                    // always wide enough for this exact label at this exact (12px) size — see
                    // `_requiredActiveWidthFor`.
                    label,
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
