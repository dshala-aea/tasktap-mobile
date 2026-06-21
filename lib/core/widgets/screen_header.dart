import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';

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
    this.onTap,
    this.showDot = false,
    this.glass = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool showDot;

  /// Glass styling for placement on a dark hero.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
                    color: glass ? Colors.white.withAlpha(46) : AppColors.BG3,
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
                    color: glass ? AppColors.WHITE : AppColors.DARK,
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
                        color: AppColors.RED,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.WHITE, width: 1.5),
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
    final titleColor = dark ? AppColors.WHITE : AppColors.DARK;
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HeaderIconBtn(
                icon: LucideIcons.chevronLeft,
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
                          : AppColors.MUTED,
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
