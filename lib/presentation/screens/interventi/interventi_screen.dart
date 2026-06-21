import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../oggi/oggi_screen.dart';

/// Interventions list screen — placeholder for M3/M4.
class InterventiScreen extends StatelessWidget {
  const InterventiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Interventi', style: AppTextStyles.titleLarge),
      ),
      body: const Center(
        child: ComingSoonPlaceholder(
          icon: Icons.build,
          title: 'Interventi',
          subtitle:
              'La lista degli interventi apparirà qui.\n(disponibile in M3)',
        ),
      ),
    );
  }
}
