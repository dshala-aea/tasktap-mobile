import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

/// A tinted inline message — a failure or warning surfaced next to the thing that caused it,
/// rather than a screen-blocking dialog or a page-level [ErrorState].
///
/// Was three verbatim-identical copies (`login_screen.dart`'s `_ErrorBanner`,
/// `scan_timbra_screen.dart`'s `_ErrorBanner` of the same name but drifted to drop the icon,
/// `kiosk_activation_screen.dart`'s inlined raw copy) of the same `color.withAlpha(20)` fill +
/// `color.withAlpha(80)` border formula, each with its own hardcoded 8px radius — not
/// `AppRack.freeShape` (2px), Il Documento's "paper, nearly square" token. This is the one
/// definition; the radius is now the real token, not the drifted 8px every copy carried.
///
/// ```dart
/// InlineAlert(message: 'Credenziali non valide.');
/// InlineAlert(message: 'Il PIN non è corretto.', icon: LucideIcons.alertCircle);
/// InlineAlert(message: 'Verifica i campi evidenziati.', color: context.colors.amber);
/// ```
class InlineAlert extends StatelessWidget {
  const InlineAlert({super.key, required this.message, this.color, this.icon});

  final String message;

  /// Defaults to [AppPalette.red] — every current use is an error; pass e.g. `context.colors.amber`
  /// for a warning.
  final Color? color;

  /// Omitted by default — two of the three sites this consolidates had no icon at all.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.withAlpha(20),
        border: Border.all(color: tone.withAlpha(80)),
        borderRadius: AppRack.freeShape,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: tone, size: 18),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(message, style: AppTextStyles.bodySmall.copyWith(color: tone)),
          ),
        ],
      ),
    );
  }
}
