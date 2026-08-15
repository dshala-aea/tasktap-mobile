import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Dashboard hero header.
///
/// Spec: dark radial/linear gradient with 0.45 black overlay, bottom radius 30,
/// minHeight ~430; "Bentornato" (Manrope 500/16 white) + user name
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
    this.minHeight = 430,
  });

  final String userName;
  final String greeting;
  final List<Widget> actions;
  final Widget? child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
          decoration: BoxDecoration(color: Colors.black.withAlpha(115)), // 0.45
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
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
                                style: GoogleFonts.manrope(
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
                                style: GoogleFonts.sora(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.Y,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final action in actions) ...[const SizedBox(width: 6), action],
                      ],
                    ),
                    if (child != null) ...[const SizedBox(height: 20), child!],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
