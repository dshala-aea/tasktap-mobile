import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import 'empty_state.dart';

/// Shown where a screen needs backend data that no client code path fetches (or writes to the
/// local cache) yet.
///
/// Always states the reason. "Prossimamente" tells a technician nothing and hides a real gap
/// behind a promise nobody scheduled — every call site names the specific capability that is
/// missing, traceable to `docs/api-gap-list.md`.
///
/// ## Why this shares EmptyState's shell, muted rather than red
///
/// Both are the same claim — *something belongs here and is not here* — and a technician should
/// not have to learn two visual languages for one idea. What separates them is the icon badge's
/// tint: neutral ink-muted rather than [ErrorState]'s red. An unreachable capability is not the
/// technician's error and must not be dressed as one; the red channel in this app is reserved for
/// things they can actually act on. (The old design marked this distinction with a graphite ledge
/// stub — a mark specific to the rack metaphor Vetro replaced; the muted badge carries the same
/// meaning without borrowing vocabulary from a design language this one isn't part of.)
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
          child: VetroStateCard(
            iconBadge: VetroStateIconBadge(
              icon: icon,
              tint: c.inkMuted,
              tintBg: c.inkMuted.withAlpha(31),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
