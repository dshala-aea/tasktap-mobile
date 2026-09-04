// dart format width=100
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_rack.dart';

/// Flat Documento replacement for the old `VetroCompartmentTile` — same interface, so every call
/// site swaps one name for the other with no other changes. Shared across Ticket detail,
/// Rapportino, and Altro (same three screens `VetroCompartmentTile`'s own doc comment named).
class AppCompartmentTile extends StatelessWidget {
  const AppCompartmentTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Clamped for the same reason the old widget clamped it: the grid's fixed childAspectRatio
    // sizes this tile to a constant cell that doesn't grow with text, so an unclamped large
    // accessibility text size would overflow a 2-line label.
    final systemScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final clampedScaler = TextScaler.linear(systemScale > 1.3 ? 1.3 : systemScale);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRack.freeShape,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRack.freeShape,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: AppColors.Y),
                  const SizedBox(height: 8),
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
      ),
    );
  }
}
