import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../oggi/oggi_screen.dart';

/// User profile screen — placeholder for M2/M6.
class ProfiloScreen extends StatelessWidget {
  const ProfiloScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Profilo', style: AppTextStyles.titleLarge),
      ),
      body: const Center(
        child: ComingSoonPlaceholder(
          icon: Icons.person,
          title: 'Profilo',
          subtitle:
              'Il tuo profilo e le impostazioni appariranno qui.\n(disponibile in M2)',
        ),
      ),
    );
  }
}
