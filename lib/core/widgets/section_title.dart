import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Section heading row.
///
/// Spec: Sora 700/18 DARK; padding top 20 / horizontal 19 / bottom 10;
/// optional trailing [action] widget.
///
/// ```dart
/// SectionTitle(title: 'Attività recenti');
/// SectionTitle(title: 'Rapportini', action: TextButton(onPressed: ..., child: Text('Vedi tutti')));
/// ```
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.action,
  });

  final String title;

  /// Optional right-side widget (e.g. a "Vedi tutti" TextButton).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 20, 19, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.DARK,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
