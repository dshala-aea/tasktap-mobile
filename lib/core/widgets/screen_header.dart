import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';
import 'app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// 38×38 circular icon button (≥44 pt hit area), BG3 bg (or glass on dark),
/// icon 17 DARK, optional red dot badge.
///
/// ```dart
/// HeaderIconBtn(icon: LucideIcons.bell, showDot: true, onTap: () {});
/// HeaderIconBtn(icon: LucideIcons.user, glass: true, onTap: () {});
/// ```
class HeaderIconBtn extends StatelessWidget {
  const HeaderIconBtn({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.showDot = false,
    this.glass = false,
  });

  final IconData icon;

  /// What a screen reader announces. Required, not optional: this widget draws every header
  /// action in the app — back, notifications, profile, search, across 29 screens — and it used to
  /// set `Semantics(button: true)` with no text at all, so TalkBack announced an unnamed button
  /// for all of them. An optional label would have stayed unset in exactly the same places.
  final String label;

  final VoidCallback? onTap;
  final bool showDot;

  /// Glass styling for placement on a dark hero.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      // Splash covers the whole 44dp target, not the 38dp disc drawn inside it — the same
      // relationship Material's own IconButton has between its ink and its glyph.
      child: AppTappable(
        onTap: onTap,
        borderRadius: glass ? BorderRadius.circular(22) : AppRack.insetShape,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: glass
                        ? Colors.white.withAlpha(46)
                        : context.colors.bg3,
                    // A machined square, not a moulded disc — except in glass mode. Glass marks a
                    // dark/hero-style surface (the dashboard hero, and `ScreenHeader(dark: true)`'s
                    // back chevron); the Figma reference draws that pairing as a round glass disc.
                    // This is a shape exception scoped to glass surfaces specifically, not a
                    // reversal of the machined language the other light-header screens keep.
                    borderRadius: glass
                        ? BorderRadius.circular(19)
                        : AppRack.insetShape,
                    border: Border.all(
                      color: glass
                          ? Colors.white.withAlpha(128)
                          : context.colors.borderMedium,
                      width: glass ? 0.5 : 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: glass ? AppColors.WHITE : context.colors.ink,
                  ),
                ),
                if (showDot)
                  Positioned(
                    right: 1,
                    top: 1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: context.colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.bg3,
                          width: 1.5,
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

/// Screen header — optional back chevron, Inter 700/18 title (ellipsis),
/// optional Inter 12 MUTED subtitle, trailing actions.
///
/// Spec padding: top 8 / horizontal 19 / bottom 12.
///
/// ```dart
/// ScreenHeader(title: 'Rapportini');
/// ScreenHeader(
///   title: 'Dettaglio',
///   subtitle: 'Ticket #1024',
///   showBack: true,
///   actions: [HeaderIconBtn(icon: LucideIcons.bell, onTap: () {})],
/// );
/// ```
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.actions = const [],
    this.dark = true,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// The case-shell top plate: dark ground, white title. Default, not an opt-in — this is what
  /// makes the header read as part of the same shell as the bottom nav rather than a five-screen
  /// exception. Screens that genuinely need a light header (none do today) can still pass `false`.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final titleColor = dark ? AppColors.WHITE : context.colors.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
      // The top plate of the load bay. Headers used to float with no edge at all, so a scrolled
      // list ran up underneath the title with nothing marking where the rack began; the rail now
      // starts at this line. Self-painted CHARCOAL when dark, rather than relying on the Scaffold
      // behind it: the header is the plate riveted to the case lid, not a transparent label
      // floating over whatever colour the page happens to be.
      decoration: BoxDecoration(
        color: dark ? AppColors.CHARCOAL : null,
        border: Border(
          bottom: BorderSide(
            color: dark
                ? Colors.white.withAlpha(38)
                : context.colors.borderMedium,
          ),
        ),
      ),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HeaderIconBtn(
                icon: LucideIcons.chevronLeft,
                label: 'Indietro',
                glass: dark,
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: dark
                          ? AppColors.WHITE.withAlpha(179)
                          : context.colors.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 4), action],
        ],
      ),
    );
  }
}

/// [ScreenHeader] as a `Scaffold.appBar`.
///
/// Nine admin form screens and the rapportino wizard used a Material [AppBar] while every list
/// screen beside them used [ScreenHeader] — so the app's chrome changed at exactly the moment a
/// technician started entering data. Lifting each header into the body would have meant
/// restructuring ten differently-shaped bodies; this keeps `appBar:` and swaps only what it
/// renders, which is a one-line change per screen and moves no content.
///
/// Handles the status-bar inset itself, since a `PreferredSize` does not get the [AppBar]'s
/// automatic [SafeArea].
class ScreenHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const ScreenHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.onBack,
    this.actions = const [],
    this.backgroundColor,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// Defaults to the case-shell CHARCOAL, matching every other header in the app — a form screen
  /// is still light content under a dark plate, same grammar as a list screen. Override for a
  /// caller that genuinely needs something else (none do today).
  final Color? backgroundColor;

  /// 8 + 12 padding around a 44dp target, plus the subtitle's line when there is one.
  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 64 : 82);

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.CHARCOAL;

    // Derived, not passed. `ScreenHeader.dark` decides whether the title and back button are
    // painted for a dark ground, and leaving that to the caller is precisely how this app
    // produced five separate "dark surface, light-theme ink" bugs. A header cannot be given a
    // CHARCOAL background and near-black text here, because nobody is asked.
    final isDark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;

    return ColoredBox(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: ScreenHeader(
          title: title,
          subtitle: subtitle,
          showBack: showBack,
          onBack: onBack,
          actions: actions,
          dark: isDark,
        ),
      ),
    );
  }
}
