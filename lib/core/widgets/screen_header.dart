import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_rack.dart';
import '../theme/app_vetro_palette.dart';
import 'app_tappable.dart';
import 'vetro_glass.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// 38×38 circular icon button (≥44 pt hit area), BG3 bg (or glass), icon 17, optional red dot
/// badge.
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

  /// Real `VetroGlass` styling, reading `context.vetro` so the disc flips with the app theme —
  /// every `ScreenHeader` is itself a flipping glass bar. Default true: this is the button every
  /// header action in the app uses. Pass `false` only for a caller that genuinely needs the
  /// squared, `bg3`-filled machined look instead (none do today).
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
                  // header sat over anything but a flat colour. Fill/border omitted so VetroGlass
                  // reads them from `context.vetro` and flips with the app theme, same as the bar
                  // it sits on.
                  VetroGlass(
                    borderRadius: BorderRadius.circular(19),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(icon, size: 17, color: context.colors.ink),
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
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final titleColor = context.colors.ink;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HeaderIconBtn(
                icon: LucideIcons.chevronLeft,
                label: 'Indietro',
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
                      color: context.colors.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 4), action],
        ],
      ),
    );

    // A real frosted bar, not a flat tint standing in for one — same reasoning as VetroGlass's
    // own doc comment. Border radius zero: this spans the full screen width, so the only edge
    // that reads is the bottom hairline the artifact's own `.tabbar`/status bar draws.
    //
    // RepaintBoundary around the clip+blur: without its own compositing layer, BackdropFilter
    // here leaked an unclipped second copy of content past its ClipRect bounds on-device (the
    // bottom nav's identical bar had the same leak — see AppBottomNav's own comment on this).
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppVetroColors.blurSigma,
            sigmaY: AppVetroColors.blurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: v.glassFill,
              border: Border(bottom: BorderSide(color: v.hairline)),
            ),
            child: row,
          ),
        ),
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
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// 8 + 12 padding around a 44dp target, plus the subtitle's line when there is one.
  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 64 : 82);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ScreenHeader(
        title: title,
        subtitle: subtitle,
        showBack: showBack,
        onBack: onBack,
        actions: actions,
      ),
    );
  }
}
