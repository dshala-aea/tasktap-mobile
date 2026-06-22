import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';

/// Altro hub — links to Rapportini and Profilo (other sections added in P4).
class AltroScreen extends StatelessWidget {
  const AltroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Altro'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 19),
                children: [
                  _AltroTile(
                    icon: LucideIcons.fileText,
                    title: 'Rapportini',
                    onTap: () => context.go('/altro/rapportini'),
                  ),
                  const SizedBox(height: 8),
                  _AltroTile(
                    icon: LucideIcons.user,
                    title: 'Profilo',
                    onTap: () => context.go('/altro/profilo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AltroTile extends StatelessWidget {
  const _AltroTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard.pressable(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.BG3,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.DARK),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.DARK,
              ),
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: AppColors.DIS,
          ),
        ],
      ),
    );
  }
}
