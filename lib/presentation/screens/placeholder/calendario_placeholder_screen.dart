import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../oggi/oggi_screen.dart';

/// Placeholder for the Calendario tab — real calendar arrives in a later phase.
class CalendarioPlaceholderScreen extends StatelessWidget {
  const CalendarioPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: ComingSoonPlaceholder(
          icon: LucideIcons.calendar,
          title: 'Calendario',
          subtitle: 'Il calendario arriverà in una prossima versione.',
        ),
      ),
    );
  }
}
