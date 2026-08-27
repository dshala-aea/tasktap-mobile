// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../theme/app_vetro_palette.dart';
import '../utils/maps_launcher.dart';
import 'vetro_card.dart';

/// A location summary + "Naviga" action — added to close a real gap the Vetro mockup's own
/// `.mapcard` called for on both Ticket detail and Cantiere detail: an address shown with no way
/// to act on it. Not a real map SDK (the mockup's own `.mapviz` is a stylised placeholder, not
/// map tiles either) — a decorative pin panel plus a single external maps launch, no API key, no
/// new native map dependency.
class VetroMapCard extends StatelessWidget {
  const VetroMapCard({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return VetroCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 84,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [v.tint.withAlpha(46), v.tintStrong.withAlpha(31)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Center(
              child: Icon(LucideIcons.mapPin, size: 28, color: v.tint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _NavigaButton(address: address),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigaButton extends StatelessWidget {
  const _NavigaButton({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return Material(
      color: v.tint,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openMapsForAddress(address),
        // 8dp vertical padding alone is ~32px tall — under the 44pt/48dp floor for the sole
        // control that launches navigation from this card.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Naviga',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
