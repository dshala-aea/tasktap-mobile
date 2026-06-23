// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// LocationService
//
// Thin wrapper around geolocator that:
//   1. Checks if location services are enabled.
//   2. Requests permission if not already granted.
//   3. Returns the current position or null (never throws) on denial/error.
//
// Tested via a fake injected implementation — never calls real GPS in tests.
//
// TODO(native-config): Add the following to native projects before shipping:
//   iOS  → Info.plist: NSLocationWhenInUseUsageDescription
//   Android → AndroidManifest.xml: ACCESS_FINE_LOCATION permission
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Result record: latitude + longitude.
typedef GpsCoords = ({double lat, double lng});

/// Contract for obtaining the device's current GPS position.
abstract class ILocationService {
  /// Returns the current GPS position, or null if unavailable/denied.
  /// Never throws — failures are silently absorbed.
  Future<GpsCoords?> getCurrentPosition();
}

// ── Real implementation ───────────────────────────────────────────────────────

class LocationService implements ILocationService {
  const LocationService();

  @override
  Future<GpsCoords?> getCurrentPosition() async {
    try {
      // 1. Check if the OS location service is turned on.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // 2. Check / request permission.
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // 3. Obtain position.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      // Any platform exception or timeout → gracefully return null.
      return null;
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides the [ILocationService]. Override in tests with a fake.
final locationServiceProvider = Provider<ILocationService>((ref) {
  return const LocationService();
});
