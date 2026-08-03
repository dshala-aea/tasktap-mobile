import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';

/// Shown where a screen needs backend data that no client code path fetches
/// (or writes to the local cache) yet.
///
/// Always states the reason. "Prossimamente" tells a technician nothing and
/// hides a real gap behind a promise nobody scheduled — every call site
/// names the specific capability that's missing, traceable to
/// `docs/api-gap-list.md`.
///
/// Styled on [EmptyState] (60px BG3 circle + 26px DIS icon, Sora 700/16
/// title, Manrope 13 MUTED body capped at 280px, centred, pad 60/30) so it
/// reads as the same design system, not a bolted-on error screen.
///
/// ```dart
/// UnavailableState(
///   titolo: 'Catalogo materiali non disponibile',
///   motivo: 'Il catalogo materiali non è ancora sincronizzato sul '
///       'dispositivo.',
/// );
/// ```
class UnavailableState extends StatelessWidget {
  const UnavailableState({
    super.key,
    required this.titolo,
    required this.motivo,
    this.icon = LucideIcons.alertTriangle,
  });

  /// What is missing (short, e.g. "Catalogo materiali non disponibile").
  final String titolo;

  /// Why it's missing — always a concrete reason, never a vague promise.
  final String motivo;

  /// Circle icon, 26px, [AppColors.DIS]. Defaults to a generic "something's
  /// off" glyph; pass a domain icon (e.g. [LucideIcons.package]) to match
  /// the surrounding screen's iconography.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: AppColors.BG3,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: AppColors.DIS),
            ),
            const SizedBox(height: 16),
            Text(
              titolo,
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.DARK,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                motivo,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.MUTED,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
