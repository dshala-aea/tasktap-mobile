import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
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
        borderRadius: BorderRadius.circular(22),
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
                    color: glass ? Colors.white.withAlpha(46) : context.colors.bg3,
                    shape: BoxShape.circle,
                    border: glass
                        ? Border.all(
                            color: Colors.white.withAlpha(128),
                            width: 0.5,
                          )
                        : null,
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
                        border: Border.all(color: context.colors.bg3, width: 1.5),
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

/// Screen header — optional back chevron, Sora 700/18 title (ellipsis),
/// optional Manrope 12 MUTED subtitle, trailing actions.
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
    this.dark = false,
  });

  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// Dark variant: white title on a dark background.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final titleColor = dark ? AppColors.WHITE : context.colors.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
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
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
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
          for (final action in actions) ...[
            const SizedBox(width: 4),
            action,
          ],
        ],
      ),
    );
  }
}
