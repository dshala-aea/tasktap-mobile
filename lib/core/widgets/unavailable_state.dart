import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

import 'empty_state.dart';

/// Shown where a screen needs backend data that no client code path fetches (or writes to the
/// local cache) yet.
///
/// Always states the reason. "Prossimamente" tells a technician nothing and hides a real gap
/// behind a promise nobody scheduled — every call site names the specific capability that is
/// missing, traceable to `docs/api-gap-list.md`.
///
/// ## Why this is a shadow board and not an error
///
/// It shares [EmptyState]'s cut outline, because both are the same claim — *something belongs
/// here and is not here* — and a technician should not have to learn two visual languages for
/// one idea. What separates them is the ledge: this one draws a graphite stub across the top of
/// the board, the mark the rack uses for a slot that is fitted but not stocked. It is never red.
/// An unreachable capability is not the technician's error and must not be dressed as one; the
/// red channel in this app is reserved for things they can actually act on.
///
/// ```dart
/// UnavailableState(
///   titolo: 'Catalogo materiali non disponibile',
///   motivo: 'Il catalogo materiali non è ancora sincronizzato sul dispositivo.',
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

  /// Defaults to a generic "something's off" glyph; pass a domain icon (e.g.
  /// [LucideIcons.package]) to match the surrounding screen's iconography.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: CustomPaintShadowBoard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The fitted-but-not-stocked mark: a graphite stub where a ledge would be if this
                // slot held anything. Deliberately not the full-height ledge of a live cell.
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: 44,
                    height: AppRack.silhouetteStroke * 2,
                    decoration: BoxDecoration(
                      color: c.ledge,
                      borderRadius: BorderRadius.circular(AppRack.silhouetteStroke),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 26, color: c.silhouette),
                      const SizedBox(height: 14),
                      Text(
                        titolo,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        motivo,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: c.inkMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
