// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// GeoMapCard
//
// A real embedded OpenStreetMap preview — not just the pin-icon AppMapCard fallback. Generalized
// out of the cantiere feature's original `CantiereMapCard` (lib/features/cantiere/
// cantiere_map_card.dart) so ticket detail, sede detail, and report detail can all show the same
// treatment for whatever location they carry, without any of this widget's code knowing what a
// Cantiere, Ticket, Location or DraftReport is.
//
// Deliberately takes an already-resolved `AsyncValue<GeocodedPoint?>`, not a provider or an
// address to geocode itself: every caller so far resolves its point through a cache-then-geocode-
// then-persist provider keyed on its own entity (`cantiereGeocodedLocationProvider`,
// `locationGeocodedLocationProvider`, ...), and that resolution differs per entity (different
// table, different cache column) in a way this presentation-only widget has no business knowing.
// A caller with a point already in hand (e.g. a freshly-captured GPS fix, nothing to geocode) can
// just wrap it in `AsyncValue.data(point)`.
//
// Falls back to `AppMapCard` (unchanged, still the correct fallback per its own doc comment)
// whenever there's nothing to plot: geocoding still in flight shows a lightweight placeholder
// instead — never a full-screen spinner, since the rest of a detail screen's sections load and
// render independently of this card.
//
// Non-interactive by deliberate choice, not an oversight: this card is a small (160px) preview
// embedded in a scrolling page, not a full-screen map. A pinch/pan-capable map that size fights
// the page's own scroll gesture — the classic "map trap" — and someone glancing at this card wants
// confirmation of where the site is, not an in-card explorer. The one real interaction (zoom,
// search, turn-by-turn) already has a correct home: tapping the card, or the "Apri in Mappe" row
// below it, both launch the device's own maps app via `openMapsForAddress`.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../location/geocoding_service.dart' show GeocodedPoint;
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_rack.dart';
import '../theme/app_spacing.dart';
import '../utils/maps_launcher.dart';
import 'app_card.dart';
import 'app_map_card.dart';
import 'app_tappable.dart';

/// This app's own applicationId (android/app/build.gradle.kts / iOS
/// PRODUCT_BUNDLE_IDENTIFIER) — flutter_map's `TileLayer.userAgentPackageName` sends this as part
/// of the User-Agent on every tile request, per OSM's tile usage policy
/// (operations.osmfoundation.org/policies/tiles) on identifying the requesting app.
const String _osmUserAgentPackageName = 'com.advantedge.tasktap.tasktap_mobile';

const double _mapHeight = 160;

class GeoMapCard extends StatelessWidget {
  const GeoMapCard({super.key, required this.pointAsync, required this.address});

  /// The point to plot, still loading, or absent — see this file's header comment for why this is
  /// an already-resolved `AsyncValue` rather than a provider or a raw address this widget would
  /// geocode itself.
  final AsyncValue<GeocodedPoint?> pointAsync;

  /// The joined display address (address/city/postalCode) — same string `AppMapCard` and
  /// `openMapsForAddress` already use, so the fallback and the "Apri in Mappe" affordance always
  /// agree with what an embedded map, once resolved, is showing.
  final String address;

  @override
  Widget build(BuildContext context) {
    return pointAsync.when(
      loading: () => const GeoMapPlaceholder(),
      // An error surfaces here only for a bug in the resolving provider itself — every resolver
      // this widget is fed by (GeocodingService-backed or otherwise) is documented to never throw
      // — but falling back rather than propagating keeps this card's contract simple either way:
      // no coordinates, same fallback as "no address" or "address unresolvable".
      error: (e, _) => AppMapCard(address: address),
      data: (point) =>
          point == null ? AppMapCard(address: address) : _EmbeddedMap(point: point, address: address),
    );
  }
}

/// Shown while a point is still resolving (loading a cached row, or — the first time only —
/// waiting on a geocoding round-trip). Deliberately the same footprint as the eventual
/// map/AppMapCard, so nothing reflows once it resolves.
class GeoMapPlaceholder extends StatelessWidget {
  const GeoMapPlaceholder({super.key});

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

class _EmbeddedMap extends StatefulWidget {
  const _EmbeddedMap({required this.point, required this.address});

  final GeocodedPoint point;
  final String address;

  @override
  State<_EmbeddedMap> createState() => _EmbeddedMapState();
}

class _EmbeddedMapState extends State<_EmbeddedMap> {
  // Set once an OSM tile request actually fails (offline mid-session after the initial resolve
  // succeeded, tile server outage, etc.) — flutter_map has no built-in "map unavailable" state of
  // its own, only this per-tile error callback, so this is the minimal signal available to fall
  // back on. Falls back to the same AppMapCard this card's parent already shows when there's
  // nothing to plot at all, rather than leaving blank/broken tiles on screen with no explanation.
  bool _tileLoadFailed = false;

  @override
  Widget build(BuildContext context) {
    if (_tileLoadFailed) return AppMapCard(address: widget.address);

    final center = LatLng(widget.point.lat, widget.point.lng);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: AppRack.freeShape,
            child: SizedBox(
              height: _mapHeight,
              child: AppTappable(
                onTap: () => openMapsForAddress(widget.address),
                semanticLabel: 'Apri indirizzo in mappe',
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
                      errorTileCallback: (tile, error, stackTrace) {
                        if (_tileLoadFailed || !mounted) return;
                        setState(() => _tileLoadFailed = true);
                      },
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
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: AppTappable(
            onTap: () => openMapsForAddress(widget.address),
            borderRadius: AppRack.insetShape,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: context.colors.inkMuted),
                const SizedBox(width: 6),
                Text(
                  'Apri in Mappe',
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
