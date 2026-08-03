import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';

/// Lightweight placeholder screen for features not yet built (D5 anagrafiche, etc.).
///
/// Shows a [ScreenHeader] with a back button + [EmptyState] "Disponibile a breve".
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: title,
              showBack: true,
            ),
            const Expanded(
              child: EmptyState(
                icon: LucideIcons.clock,
                title: 'Disponibile a breve',
                body:
                    'Questa sezione sarà disponibile nei prossimi aggiornamenti.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
