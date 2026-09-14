// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereMapCard
//
// A real embedded OpenStreetMap preview for the cantiere detail screen — not just the pin-icon
// AppMapCard fallback. Backed by `cantiereGeocodedLocationProvider` (cache-then-geocode-then-
// persist, see that provider's own doc comment), so most opens after the first render straight
// from the local cache with no network call at all.
//
// Falls back to `AppMapCard` (unchanged, still the correct fallback per its own doc comment)
// whenever there's nothing to plot: geocoding still in flight shows a lightweight placeholder
// instead — never a full-screen spinner, since the rest of the detail screen's sections load and
// render independently of this card.
//
// Non-interactive by deliberate choice, not an oversight: this card is a small (160px) preview
// embedded in a scrolling page, not a full-screen map. A pinch/pan-capable map that size fights
// the page's own scroll gesture — the classic "map trap" — and a field technician glancing at
// this card wants confirmation of where the site is, not an in-card explorer. The one real
// interaction (zoom, search, turn-by-turn) already has a correct home: tapping the card, or the
// "Apri in Mappe" row below it, both launch the device's own maps app via `openMapsForAddress`.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/location/geocoding_service.dart' show GeocodedPoint;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/maps_launcher.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_map_card.dart';
import '../../core/widgets/app_tappable.dart';
import 'cantiere_providers.dart';

/// This app's own applicationId (android/app/build.gradle.kts / iOS
/// PRODUCT_BUNDLE_IDENTIFIER) — flutter_map's `TileLayer.userAgentPackageName` sends this as part
/// of the User-Agent on every tile request, per OSM's tile usage policy
/// (operations.osmfoundation.org/policies/tiles) on identifying the requesting app.
const String _osmUserAgentPackageName = 'com.advantedge.tasktap.tasktap_mobile';

const double _mapHeight = 160;

class CantiereMapCard extends ConsumerWidget {
  const CantiereMapCard({super.key, required this.cantiereId, required this.address});

  final String cantiereId;

  /// The joined display address (address/city/postalCode) — same string `AppMapCard` and
  /// `openMapsForAddress` already use, so the fallback and the "Apri in Mappe" affordance always
  /// agree with what an embedded map, once geocoded, is showing.
  final String address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointAsync = ref.watch(cantiereGeocodedLocationProvider(cantiereId));

    return pointAsync.when(
      loading: () => const _MapPlaceholder(),
      // A geocoding failure surfaces here as AsyncError only for a bug in the provider itself —
      // GeocodingService.geocode() never throws (see its own doc comment) — but falling back
      // rather than propagating keeps this card's contract simple either way: no coordinates,
      // same fallback as "no address" or "address unresolvable".
      error: (e, _) => AppMapCard(address: address),
      data: (point) => point == null
          ? AppMapCard(address: address)
          : _EmbeddedMap(point: point, address: address),
    );
  }
}

/// Shown while `cantiereGeocodedLocationProvider` is still resolving (loading the cached row, or —
/// the first time only — waiting on the one Nominatim round-trip). Deliberately the same
/// footprint as the eventual map/AppMapCard, so nothing reflows once it resolves.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: _mapHeight,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.inkMuted),
          ),
        ),
      ),
    );
  }
}

class _EmbeddedMap extends StatelessWidget {
  const _EmbeddedMap({required this.point, required this.address});

  final GeocodedPoint point;
  final String address;

  @override
  Widget build(BuildContext context) {
    final center = LatLng(point.lat, point.lng);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: AppRack.freeShape,
            child: SizedBox(
              height: _mapHeight,
              child: GestureDetector(
                onTap: () => openMapsForAddress(address),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 16,
                    // Non-interactive — see this file's header comment for why.
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: _osmUserAgentPackageName,
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: center,
                          width: 36,
                          height: 36,
                          child: const Icon(LucideIcons.mapPin, color: AppColors.Y, size: 36),
                        ),
                      ],
                    ),
                    // A real license requirement (OSM's attribution guideline), not decoration —
                    // flutter_map's own widget for it rather than hand-rolled text.
                    const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: AppTappable(
              onTap: () => openMapsForAddress(address),
              borderRadius: AppRack.insetShape,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.mapPin, size: 14, color: context.colors.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    'Apri in Mappe',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
