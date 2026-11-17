// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';

import '../../presentation/providers/clock_disagreement_provider.dart'
    show describeClockDisagreement;

/// "The server and this phone disagreed about the time."
///
/// Shared by the two punch screens — personal Timbra and cantiere — because the sentence is the
/// same one and the difference between them is only *which* notifier dismisses it. Not a toast
/// and not a guard: those say a punch did or will fail, while this says the punch succeeded and
/// the hours may be filed under the wrong clock.
///
/// It stays until dismissed on purpose. The flag is the phone's only way to hear about its own
/// drifted clock, and a four-second toast would be gone before the technician looked up.
class ClockDisagreementNote extends StatelessWidget {
  const ClockDisagreementNote({super.key, required this.seconds, required this.onDismiss});

  /// Signed gap the server measured: positive means this phone was ahead of it.
  final int seconds;

  /// Clears this screen's reminder. The server keeps the record either way — the office sees the
  /// same flag in Correzioni.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: v.statusWarnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: v.statusWarn.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 15, color: v.statusWarn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'L\'orologio del telefono non coincideva con quello del server: segnava '
              '${describeClockDisagreement(seconds)}. Le ore sono state registrate con '
              'l\'ora del telefono: se non tornano, segnalale all\'ufficio.',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                height: 1.35,
                color: v.statusWarn,
              ),
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 14, color: v.statusWarn),
            tooltip: 'Nascondi avviso orologio',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.only(left: 6),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
