import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

import 'rack.dart';

/// The empty state, now a shadow board.
///
/// The previous version was the category default: a grey disc, an icon, a centred sentence. It
/// said "nothing here" and it said it the same way whether the rack was legitimately empty or the
/// data had never arrived.
///
/// A shadow board makes a different claim, and it is the one this app needs: *something belongs
/// in this slot and it is not here*. The outline is drawn, so the slot is still visibly part of
/// the rack. Twenty call sites across sixteen screens inherit that for free — the API is unchanged.
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
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: CustomPaintShadowBoard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 26, color: c.silhouette),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sora(
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
                      style: GoogleFonts.manrope(
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
                      style: GoogleFonts.manrope(
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
      ),
    );
  }
}

/// The dashed cut-line frame, drawn with the rack's own [SilhouettePainter] so this outline and
/// [ShadowBoard]'s cannot drift apart.
class CustomPaintShadowBoard extends StatelessWidget {
  const CustomPaintShadowBoard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SilhouettePainter(color: context.colors.silhouette),
      child: child,
    );
  }
}
