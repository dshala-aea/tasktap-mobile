// dart format width=100
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_vetro_palette.dart';
import 'vetro_glass.dart';

/// Vetro's [CompartmentTile] — additive, same interface, so a call site swaps one for the other
/// without touching how the grid around it is built. `CompartmentTile` is shared across three
/// screens (Ticket detail, Rapportino, Altro) — same reasoning as [VetroCard]/[VetroButton]: a
/// new widget, not a change to the one every not-yet-redesigned screen still depends on.
///
/// Real `VetroGlass` blur here, unlike the ticket list's rows: this renders a small, fixed-count
/// grid (8 tiles on Ticket detail), not an unbounded scrolling list — the "many small instances"
/// cost that ruled out blur there doesn't apply at this count.
class VetroCompartmentTile extends StatelessWidget {
  const VetroCompartmentTile({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return VetroGlass(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: v.tint),
                const SizedBox(height: 14),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                    letterSpacing: -0.1,
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
