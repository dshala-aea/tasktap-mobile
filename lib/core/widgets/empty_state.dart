import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_vetro_palette.dart';
import 'vetro_card.dart';

/// The empty state — a Vetro glass card around a tinted icon badge.
///
/// Was a "shadow board": a dashed cut-silhouette borrowed from the app's earlier van-racking
/// design language, claiming *something belongs in this slot and it is not here*. Vetro has no
/// rack for a slot to be cut into, so that claim now reads as a glass panel instead — the same
/// "designated area, softly bounded" idea `VetroCard`/`VetroCompartmentTile` already carry
/// everywhere else, rather than a metaphor specific to a design language this one replaced.
/// Twenty call sites across sixteen screens inherit that for free — the API is unchanged.
///
/// Where the emptiness is a failure rather than a fact, pass [reason]; that is the distinction the
/// third product principle exists to protect, and [UnavailableState] is the heavier-weight version
/// for a capability that is genuinely unreachable.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.reason,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  /// Why the slot is empty, when "empty" is not the ordinary case.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: VetroStateCard(
            iconBadge: VetroStateIconBadge(icon: icon, tint: v.tint, tintBg: v.tint.withAlpha(31)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    body!,
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
                if (reason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    reason!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: c.inkFaint,
                      height: 1.4,
                    ),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared shell for [EmptyState]/[ErrorState]/[UnavailableState]: a glass card around an icon
/// badge and whatever content each of the three needs below it. The single owner of that shape so
/// the family cannot drift apart the way three copies of the same padding/radius eventually would.
class VetroStateCard extends StatelessWidget {
  const VetroStateCard({super.key, required this.iconBadge, required this.child});

  final Widget iconBadge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return VetroCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [iconBadge, const SizedBox(height: 14), child],
      ),
    );
  }
}

/// The tinted circle behind a state card's icon — same "icon in a gradient-tinted disc" language
/// as `VetroMapCard`'s pin header, sized down for an inline badge rather than a card header.
class VetroStateIconBadge extends StatelessWidget {
  const VetroStateIconBadge({
    super.key,
    required this.icon,
    required this.tint,
    required this.tintBg,
    this.size = 52,
    this.iconSize = 24,
  });

  final IconData icon;
  final Color tint;
  final Color tintBg;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// A compact, inline "nothing here yet" — a form field with nothing picked, a sub-section with no
/// rows. [EmptyState]'s smaller sibling: no title/body split, no action slot, sized to sit inside
/// a form rather than center itself on a whole screen.
///
/// Was `ShadowBoard`, a dashed cut-silhouette in `rack.dart` — moved and renamed with the rest of
/// that file's van-racking metaphor retired to Vetro; this is the family it actually belongs with
/// now, not a shape specific to a design language this app no longer uses.
class CompactEmptyState extends StatelessWidget {
  const CompactEmptyState({
    super.key,
    required this.label,
    this.reason,
    this.icon,
    this.action,
    this.height = 96,
  });

  /// What belongs in this slot, named as the object it is: "nessun rapportino in coda".
  final String label;

  /// Why it is absent, when absence is not the normal case. Renders under the label in the
  /// muted ink, never in red — an empty slot is not an error.
  final String? reason;

  final IconData? icon;
  final Widget? action;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final c = context.colors;

    return Semantics(
      label: reason == null ? label : '$label. $reason',
      // Without this the state is announced three times: once as this composed phrase, then again
      // as each Text's own node. A screen-reader user hears the whole empty state twice over
      // before reaching the action.
      excludeSemantics: true,
      child: VetroCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                VetroStateIconBadge(icon: icon!, tint: v.tint, tintBg: v.tint.withAlpha(31), size: 36, iconSize: 18),
                const SizedBox(height: 8),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted),
              ),
              if (reason != null) ...[
                const SizedBox(height: 4),
                Text(
                  reason!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: c.inkFaint),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}
