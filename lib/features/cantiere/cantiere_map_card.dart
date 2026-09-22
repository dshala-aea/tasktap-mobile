// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereMapCard
//
// Thin cantiere-specific wrapper around the generalized `GeoMapCard`
// (lib/core/widgets/geo_map_card.dart, which carries the full "why" for this card's shape — real
// embedded map, non-interactive, AppMapCard fallback): watches `cantiereGeocodedLocationProvider`
// (cache-then-geocode-then-persist against the Cantieri table, see that provider's own doc
// comment) and hands the resolved point straight to `GeoMapCard`.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/geo_map_card.dart';
import 'cantiere_providers.dart';

class CantiereMapCard extends ConsumerWidget {
  const CantiereMapCard({super.key, required this.cantiereId, required this.address});

  final String cantiereId;

  /// The joined display address (address/city/postalCode) — see `GeoMapCard.address`.
  final String address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointAsync = ref.watch(cantiereGeocodedLocationProvider(cantiereId));
    return GeoMapCard(pointAsync: pointAsync, address: address);
  }
}
