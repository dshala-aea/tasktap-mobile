import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Dashboard hero header.
///
/// Dark gradient band with a 0.45 black overlay and a 30dp bottom radius, sized by its content:
/// "Bentornato" (Manrope 500/16 white) + user name
/// (Sora 700/26 YELLOW); top-right glass actions (bell, user); holds glass
/// cards via [child].
///
/// Named [DashboardHero] to avoid clashing with Flutter's own `Hero`.
///
/// ```dart
/// DashboardHero(
///   userName: 'Mario',
///   actions: [HeaderIconBtn(icon: LucideIcons.bell, glass: true, onTap: () {})],
///   child: ActiveJobCard(...),
/// );
/// ```
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.userName,
    this.greeting = 'Bentornato',
    this.actions = const [],
    this.child,
    this.minHeight,
  });

  final String userName;
  final String greeting;
  final List<Widget> actions;
  final Widget? child;

  /// Floor for the dark band. Null — the normal case — means the hero is exactly as tall as what
  /// is inside it.
  ///
  /// It used to be 430 unconditionally. With nothing running that is most of a phone screen given
  /// to an empty gradient with a name at the top, and the day's work started below the fold. The
  /// panel is a header when there is nothing to show and a panel when there is; its height should
  /// say which.
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Outside the clip: a shadow clipped to its own casting box never shows. Purely decorative
      // — the hero is already unambiguously bounded by its solid dark fill against the page
      // background behind it, so this costs nothing legible in direct sun, matching the Figma
      // reference's soft shadow under the same panel.
      decoration: BoxDecoration(boxShadow: context.colors.shadow),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Constants, not palette tokens: this hero is dark under both themes, so a token
              // that flips would turn it white in dark mode — the one place the flip is wrong.
              colors: [AppColors.CHARCOAL, AppColors.DARK],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(115),
            ), // 0.45
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight ?? 0),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(19, 12, 19, 19),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  greeting,
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.WHITE,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Sora',
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.Y,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final action in actions) ...[
                            const SizedBox(width: 6),
                            action,
                          ],
                        ],
                      ),
                      if (child != null) ...[
                        const SizedBox(height: 20),
                        child!,
                      ],
                    ],
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
