// ══════════════════════════════════════════════════════════════════════════════
// BadgeScanResultCard — one scan attempt, rendered for a leader in the field
//
// Closed mapping from (result, action) / error to an Italian line plus an icon and a tone.
// Success is green with a check icon AND text; every non-success carries its own icon AND text, so
// colour is never the only signal. Anything this build cannot classify reads "Risposta non
// riconosciuta — riprova" in the warning style — never as a success.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/badge/badge_models.dart';
import 'badge_scan_controller.dart';
import 'my_badge_screen.dart' show BadgeAvatar;

enum BadgeScanTone { success, warning, error }

class BadgeScanPresentation {
  const BadgeScanPresentation(this.text, this.icon, this.tone);
  final String text;
  final IconData icon;
  final BadgeScanTone tone;
}

const _unrecognised = BadgeScanPresentation(
  'Risposta non riconosciuta — riprova',
  LucideIcons.alertTriangle,
  BadgeScanTone.warning,
);

/// The closed text/icon/tone mapping for [entry]. Pure, so tests can theory over it.
BadgeScanPresentation presentBadgeScan(BadgeScanEntry entry) {
  final o = entry.outcome;
  if (o != null) {
    switch (o.result) {
      case BadgeScanResult.accepted:
        switch (o.action) {
          case BadgeScanAction.opened:
            return const BadgeScanPresentation(
              'ENTRATA registrata',
              LucideIcons.check,
              BadgeScanTone.success,
            );
          case BadgeScanAction.closed:
            return const BadgeScanPresentation(
              'USCITA registrata',
              LucideIcons.check,
              BadgeScanTone.success,
            );
          case BadgeScanAction.none:
            return const BadgeScanPresentation(
              'Già registrato',
              LucideIcons.check,
              BadgeScanTone.success,
            );
          case BadgeScanAction.unknown:
            // Accepted but the server did something this build cannot name: do not claim it.
            return _unrecognised;
        }
      case BadgeScanResult.notAssigned:
        return const BadgeScanPresentation(
          'Non assegnato a questo cantiere — segnalato all\'ufficio',
          LucideIcons.alertTriangle,
          BadgeScanTone.warning,
        );
      case BadgeScanResult.revoked:
        return const BadgeScanPresentation(
          'Badge non valido — contatta l\'ufficio',
          LucideIcons.xCircle,
          BadgeScanTone.error,
        );
      case BadgeScanResult.expired:
        return const BadgeScanPresentation(
          'Badge scaduto — chiedi di riaprire il badge',
          LucideIcons.clock,
          BadgeScanTone.warning,
        );
      case BadgeScanResult.replayed:
        return const BadgeScanPresentation(
          'Codice già usato — chiedi di aggiornare il badge',
          LucideIcons.clock,
          BadgeScanTone.warning,
        );
      case BadgeScanResult.invalid:
        return const BadgeScanPresentation(
          'Codice non riconosciuto',
          LucideIcons.xCircle,
          BadgeScanTone.error,
        );
      case BadgeScanResult.openElsewhere:
        return const BadgeScanPresentation(
          'Ha un turno aperto su un altro cantiere',
          LucideIcons.alertTriangle,
          BadgeScanTone.warning,
        );
      case BadgeScanResult.payrollLocked:
        return const BadgeScanPresentation(
          'Periodo paghe chiuso — contatta l\'ufficio',
          LucideIcons.lock,
          BadgeScanTone.error,
        );
      case BadgeScanResult.unknown:
        return _unrecognised;
    }
  }
  final e = entry.error;
  if (e != null) {
    if (e.isNotLead) {
      return const BadgeScanPresentation(
        'Solo il capo squadra può scansionare',
        LucideIcons.lock,
        BadgeScanTone.error,
      );
    }
    final gateway = e.statusCode == 502 || e.statusCode == 503 || e.statusCode == 504;
    if (e.isOffline || gateway) {
      return const BadgeScanPresentation(
        'Nessuna connessione — riprova',
        LucideIcons.wifiOff,
        BadgeScanTone.warning,
      );
    }
  }
  return const BadgeScanPresentation(
    'Scansione non riuscita — riprova',
    LucideIcons.alertTriangle,
    BadgeScanTone.error,
  );
}

class BadgeScanResultCard extends StatelessWidget {
  const BadgeScanResultCard({super.key, required this.entry, this.prominent = false});

  final BadgeScanEntry entry;

  /// The newest result is drawn larger.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = presentBadgeScan(entry);
    final tone = switch (p.tone) {
      BadgeScanTone.success => c.green,
      BadgeScanTone.warning => c.amber,
      BadgeScanTone.error => c.red,
    };
    final worker = entry.outcome?.worker;
    final textStyle = (prominent ? AppTextStyles.titleLarge : AppTextStyles.titleMedium).copyWith(
      color: c.ink,
      fontWeight: FontWeight.w700,
    );
    return Container(
      key: ValueKey('badge-scan-card-${p.tone.name}'),
      constraints: BoxConstraints(minHeight: prominent ? 88 : 64),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        border: Border.all(color: tone, width: prominent ? 3 : 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(p.icon, size: prominent ? 40 : 30, color: tone),
          const SizedBox(width: AppSpacing.md),
          if (worker != null) ...[
            BadgeAvatar(
              name: worker.displayName,
              photoUrl: worker.photoUrl,
              size: prominent ? 56 : 44,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (worker != null)
                  Text(
                    worker.displayName,
                    style: AppTextStyles.titleMedium.copyWith(color: c.ink),
                  ),
                Text(p.text, style: textStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
