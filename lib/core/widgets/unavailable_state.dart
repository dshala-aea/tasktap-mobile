import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
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
    this.action,
  });

  /// What is missing (short, e.g. "Catalogo materiali non disponibile").
  final String titolo;

  /// Why it's missing — always a concrete reason, never a vague promise.
  final String motivo;

  /// Defaults to a generic "something's off" glyph; pass a domain icon (e.g.
  /// [LucideIcons.package]) to match the surrounding screen's iconography.
  final IconData icon;

  /// Optional retry action — same slot shape as [EmptyState.action]. Pass e.g. an
  /// `AppButton(label: 'Riprova', ...)` at any call site whose `motivo` copy already promises a
  /// retry ("riprova tra poco") with no actual gesture behind it.
  final Widget? action;

  /// A fetch-on-demand tab's own error state — offline and generic-failure read as genuinely
  /// different things to a technician (nothing to do about one, a real retry-worthy problem on
  /// the other), so this always distinguishes them rather than showing one flat error for both.
  ///
  /// Was `ticket_detail_screen.dart`'s own private `_TabError` class, duplicated in spirit (not
  /// literally copy-pasted, but reinvented) at two other raw [UnavailableState] call sites in the
  /// same screen that never got the same split — this is now the one place that logic lives.
  ///
  /// ```dart
  /// ticketReportsProvider(ticketId).when(
  ///   error: (e, _) => UnavailableState.forFetchError(
  ///     icon: LucideIcons.fileText,
  ///     offline: e is TicketDetailOfflineException,
  ///     offlineTitle: 'Rapportini non disponibili offline',
  ///     offlineBody: 'La lista richiede una connessione: riprova quando torni online.',
  ///     errorTitle: 'Impossibile caricare i rapportini',
  ///     errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
  ///   ),
  ///   ...
  /// );
  /// ```
  factory UnavailableState.forFetchError({
    Key? key,
    required bool offline,
    required String offlineTitle,
    required String offlineBody,
    required String errorTitle,
    required String errorBody,
    IconData icon = LucideIcons.alertTriangle,
  }) {
    return offline
        ? UnavailableState(
            key: key,
            icon: LucideIcons.wifiOff,
            titolo: offlineTitle,
            motivo: offlineBody,
          )
        : UnavailableState(key: key, icon: icon, titolo: errorTitle, motivo: errorBody);
  }

  /// Same as the plain constructor, wrapped in the horizontal page padding a tab's own content
  /// needs (the plain constructor already pads itself for a full-screen placement, which double-
  /// pads inside a tab that provides its own outer padding) — [forFetchError]'s original call
  /// sites all wanted this; kept as an explicit opt-in rather than baked into every use.
  Widget paddedForTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 40),
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
                    fontFamily: 'Archivo Narrow',
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
                    fontFamily: 'Archivo',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: c.inkMuted,
                    height: 1.4,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
