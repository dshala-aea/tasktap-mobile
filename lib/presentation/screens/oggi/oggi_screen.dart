import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// Today's schedule screen — placeholder for M3.
class OggiScreen extends StatelessWidget {
  const OggiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Oggi', style: AppTextStyles.titleLarge),
      ),
      body: const Center(
        child: ComingSoonPlaceholder(
          icon: Icons.today,
          title: 'Agenda di oggi',
          subtitle:
              'I tuoi interventi di oggi appariranno qui.\n(disponibile in M3)',
        ),
      ),
    );
  }
}

/// Reusable placeholder widget for unimplemented screens.
class ComingSoonPlaceholder extends StatelessWidget {
  const ComingSoonPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.brand),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            style: AppTextStyles.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
