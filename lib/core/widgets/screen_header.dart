import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';
import '../theme/app_vetro_palette.dart';
import 'app_tappable.dart';
import 'vetro_glass.dart';
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
    this.glass = true,
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
  ///
  /// Defaults true because every `ScreenHeader` in the app is `dark: true` — there is no screen
  /// today with the light header this button's other branch was built for (see `ScreenHeader.
  /// dark`'s own doc comment). Before this default flipped, 19 of the app's 20 header-action call
  /// sites left `glass` unset and got the squared, `bg3`-filled machined button anyway: a
  /// light-theme-flipping fill on a permanently-dark CHARCOAL plate, and a squared shape next to
  /// the header's own back chevron, which already opted into glass. Pass `false` explicitly for
  /// the light-header case, if one is ever built.
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
                if (glass)
                  // A real frosted disc — VetroGlass's own BackdropFilter blur, not a flat
                  // translucent-white Container standing in for one. This used to be the one
                  // "glass" surface in the app that wasn't actually glass: every card blurs what's
                  // behind it, this button only tinted it, and the mismatch was visible wherever a
                  // header sat over anything but a flat colour.
                  VetroGlass(
                    borderRadius: BorderRadius.circular(19),
                    fill: AppVetroColors.glassFillOnDark,
                    border: AppVetroColors.glassBorderOnDark,
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(icon, size: 17, color: AppColors.WHITE),
                    ),
                  )
                else
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.colors.bg3,
                      borderRadius: AppRack.insetShape,
                      border: Border.all(color: context.colors.borderMedium),
                    ),
                    child: Icon(icon, size: 17, color: context.colors.ink),
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
