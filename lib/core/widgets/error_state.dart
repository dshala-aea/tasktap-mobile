import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import 'app_button.dart';
import 'empty_state.dart';

/// Shown where a fetch or submit genuinely failed — a network drop, a 403, a 500 — as opposed to
/// [UnavailableState]'s "no client code path fetches this yet".
///
/// Twenty-five call sites across twenty-one screens used to render the raw exception object —
/// `Text('Errore: $e')` — as the entire screen, DioException message and all, with no header and
/// no way back to trying again. A technician reading `DioException [bad response]: ... status
/// code of 403 ...` learns nothing actionable; they need "something went wrong" and a retry, not
/// a stack trace.
///
/// Shares [EmptyState]'s flat-sheet shell so a failed fetch reads as one more member of the same
/// visual family, not a jarring red departure from it. Unlike [UnavailableState] this one *is*
/// red (`context.colors.red`) — a failed request is something the technician can act on by
/// retrying, which is exactly the distinction that widget's own doc reserves the red channel for.
///
/// ```dart
/// error: (e, _) => ErrorState(onRetry: () => ref.invalidate(myProvider)),
/// ```
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.titolo = 'Impossibile caricare i dati',
    this.motivo = 'Controlla la connessione e riprova.',
    this.icon = LucideIcons.alertTriangle,
    this.onRetry,
  });

  /// What failed (short). Defaults to a generic, honest message — never the raw exception.
  final String titolo;

  /// Why it's worth trying again.
  final String motivo;

  final IconData icon;

  /// Retried on tap. Omit only where no retry is possible (e.g. an offline write that already
  /// queued) — a screen with no way forward should say so in [motivo], not hide the button.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: VetroStateCard(
            iconBadge: VetroStateIconBadge(
              icon: icon,
              tint: c.red,
              tintBg: c.red.withAlpha(31),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titolo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  motivo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: c.inkMuted,
                    height: 1.4,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 20),
                  AppButton.secondary(
                    label: 'Riprova',
                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                    size: AppButtonSize.sm,
                    onPressed: onRetry,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
