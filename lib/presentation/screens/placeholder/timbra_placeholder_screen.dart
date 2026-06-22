import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../oggi/oggi_screen.dart';

/// Placeholder for the Timbra tab — real clock-in feature arrives in a later phase.
class TimbraPlaceholderScreen extends StatelessWidget {
  const TimbraPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: ComingSoonPlaceholder(
          icon: LucideIcons.clock,
          title: 'Timbra',
          subtitle:
              'Il modulo di timbratura arriverà in una prossima versione.',
        ),
      ),
    );
  }
}
