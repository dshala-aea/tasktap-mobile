import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'status_pill.dart';

/// Active-job glass card (dashboard hero).
///
/// Spec: status badge, Sora 700/18 white title, Manrope 11 client; right side
/// shows an HH:MM:SS timer as separate 40×38 translucent tiles (Manrope 18)
/// plus a small yellow "Apri attività" button.
///
/// [elapsed] is a pre-formatted `HH:MM:SS` string (formatting lives in the
/// caller / a later timer phase).
///
/// ```dart
/// ActiveJobCard(
///   stato: 'In corso',
///   title: 'Sostituzione caldaia',
///   client: 'Condominio Roma 12',
///   elapsed: '01:24:07',
///   onOpen: () {},
/// );
/// ```
class ActiveJobCard extends StatelessWidget {
  const ActiveJobCard({
    super.key,
    required this.stato,
    required this.title,
    this.client,
    required this.elapsed,
    this.onOpen,
  });

  final String stato;
  final String title;
  final String? client;
  final String elapsed;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final segments = elapsed.split(':');

    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(stato: stato),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.WHITE,
                  ),
                ),
                if (client != null)
                  Text(
                    client!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.INV,
                    ),
                  ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Apri attività',
                  size: AppButtonSize.sm,
                  fullWidth: false,
                  onPressed: onOpen,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                _TimerTile(value: segments[i]),
                if (i < segments.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TimerTile extends StatelessWidget {
  const _TimerTile({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(38), // ~0.15 opacity
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.WHITE,
        ),
      ),
    );
  }
}
