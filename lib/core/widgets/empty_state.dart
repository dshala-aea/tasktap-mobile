import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Centered empty state — 60 px circle BG3 + icon (26, DIS), Sora 700/16 title,
/// Manrope 13 MUTED body (max width 280), optional action. Pad 60/30.
///
/// ```dart
/// EmptyState(
///   icon: LucideIcons.inbox,
///   title: 'Nessun rapportino',
///   body: 'I rapportini che crei appariranno qui.',
///   action: AppButton(label: 'Nuovo rapportino', onPressed: () {}),
/// );
/// ```
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: AppColors.BG3,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: AppColors.DIS),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.DARK,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.MUTED,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
