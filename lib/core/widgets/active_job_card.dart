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

  /// A pre-formatted `HH:MM:SS`, or null when nothing is actually running.
  ///
  /// Nullable on purpose. The dashboard used to pass a literal `'00:00:00'` for a job the
  /// calendar called in-progress but that had no running clock behind it, which put a stopped
  /// timer on the hero that looked exactly like a running one reading zero. A technician who
  /// believes that has not started their clock.
  final String? elapsed;

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final segments = elapsed?.split(':');

    return GlassCard(
      // A live clock is strapped, the same yellow mark the rest of the app uses for "this one is
      // running". Nothing else on the hero earns it.
      strapped: elapsed != null,
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
                      // A fixed light ink, not `inkInverse`. The hero is a dark gradient in both
                      // themes, but `inkInverse` flips to near-black in the dark palette — so
                      // this line, and only this line on the card, went unreadable the moment a
                      // technician turned dark mode on. The title beside it was already a fixed
                      // white, which is why the bug was invisible in review.
                      color: AppColors.WHITE.withAlpha(191),
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
          if (segments != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  _TimerTile(value: segments[i]),
                  if (i < segments.length - 1) const SizedBox(width: 4),
                ],
              ],
            )
          else
            // Says the true thing instead of drawing a zeroed clock.
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Non avviato',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.WHITE.withAlpha(153),
                ),
              ),
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
