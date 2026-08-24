import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import 'rack.dart';

/// A grid tile that opens a sub-section — icon top, label bottom, in a RackCell.
///
/// First built for Altro's Gestione grid; reused by Ticket detail's compartment grid (see
/// ticket_detail_screen.dart) rather than each screen hand-rolling its own tile.
class CompartmentTile extends StatelessWidget {
  const CompartmentTile({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RackCell(
      onTap: onTap,
      flush: false,
      minHeight: 84,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: c.inkFaint),
          const SizedBox(height: 14),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
