// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// GeocodingService
//
// Thin client for OpenStreetMap's Nominatim `/search` geocoding endpoint — turns a free-text
// address into a {lat, lng} point for CantiereMapCard's embedded preview.
//
// Deliberately stateless: no caching, no rate-limiting, no retry logic here. The one caller
// (`cantiereGeocodedLocationProvider`, lib/features/cantiere/cantiere_providers.dart) already
// geocodes a given cantiere's address at most once ever — it checks the local Drift cache
// (Cantieri.latitude/longitude) first and persists the result back there on success — so this
// class never sees more than one request per cantiere per device, which is what keeps it
// compliant with Nominatim's usage policy without this class needing to know anything about that
// policy's rate limits itself.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A geocoded point. No accuracy/timestamp metadata — Nominatim's response carries neither.
typedef GeocodedPoint = ({double lat, double lng});

/// Geocodes a free-text address via Nominatim. See this file's header comment for the
/// once-per-cantiere-forever caching contract that keeps calls to this class rare.
class GeocodingService {
  GeocodingService({Dio? dio}) : _dio = dio ?? _buildDio();

  final Dio _dio;

  // A private Dio instance, not the app's shared `dioProvider` (data/api/dio_client.dart): that
  // instance's AuthInterceptor attaches this device's bearer token to every request it makes,
  // which must never reach a third party — and Nominatim has no use for it or the app's base URL
  // anyway. This one carries only what Nominatim's own usage policy asks for.
  static Dio _buildDio() => Dio(
    BaseOptions(
      baseUrl: 'https://nominatim.openstreetmap.org',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      // Nominatim's usage policy (operations.osmfoundation.org/policies/nominatim) requires a
      // real, identifying User-Agent — a missing or generic one can be blocked outright. This
      // names the app and nothing else: no per-user or per-device identifier belongs in a header
      // sent to a third-party service.
      headers: {'User-Agent': 'TaskTapMobile/1.0'},
    ),
  );

  /// Geocodes [address], returning its first (best) match, or null when the address is blank, no
  /// match was found, or the request failed for any reason (offline, timeout, a Nominatim error).
  ///
  /// Never throws: a failed lookup is exactly as absent as no address at all to every caller, and
  /// the ultimate fallback (AppMapCard's pin-and-external-link) already handles "no coordinates"
  /// as a normal case, not an error state.
  Future<GeocodedPoint?> geocode(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;

    try {
      final response = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {'format': 'json', 'q': trimmed, 'limit': 1},
      );
      final results = response.data;
      if (results == null || results.isEmpty) return null;

      final first = results.first;
      if (first is! Map) return null;
      final lat = _parseCoord(first['lat']);
      final lng = _parseCoord(first['lon']);
      if (lat == null || lng == null) return null;
      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  double? _parseCoord(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }
}

/// Overridden in tests with a fake/mocked-Dio instance. The real implementation is stateless and
/// cheap to construct, so a plain (non-autoDispose) `Provider` — no per-family instance needed.
final geocodingServiceProvider = Provider<GeocodingService>((ref) => GeocodingService());
