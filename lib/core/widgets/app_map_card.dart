// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_rack.dart';
import '../theme/app_spacing.dart';
import '../utils/maps_launcher.dart';
import 'app_card.dart';

/// Flat Documento replacement for the old `VetroMapCard` — same interface (one `address` prop),
/// so its 2 call sites (Ticket detail, Cantiere detail) swap one name for the other with no other
/// changes. Still not a real map SDK — a flat pin panel plus a single external maps launch,
/// exactly what the old widget's own doc comment already scoped it as.
class AppMapCard extends StatelessWidget {
  const AppMapCard({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              border: Border(bottom: BorderSide(color: context.colors.borderLight)),
            ),
            child: const SizedBox(
              height: 84,
              child: Center(child: Icon(LucideIcons.mapPin, size: 28, color: AppColors.Y)),
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
    return Material(
      color: AppColors.Y,
      borderRadius: AppRack.insetShape,
      child: InkWell(
        borderRadius: AppRack.insetShape,
        onTap: () => openMapsForAddress(address),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
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
