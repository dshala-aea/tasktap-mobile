import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../oggi/oggi_screen.dart';

/// Reports list screen — placeholder for M4.
class RapportiniScreen extends StatelessWidget {
  const RapportiniScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Rapportini', style: AppTextStyles.titleLarge),
      ),
      body: const Center(
        child: ComingSoonPlaceholder(
          icon: Icons.description,
          title: 'Rapportini',
          subtitle:
              'I tuoi rapportini di lavoro appariranno qui.\n(disponibile in M4)',
        ),
      ),
    );
  }
}
