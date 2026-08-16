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
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Result record: latitude + longitude.
typedef GpsCoords = ({double lat, double lng});

/// Contract for obtaining the device's current GPS position.
abstract class ILocationService {
  /// Const so the two implementations below can stay const singletons.
  ///
  /// This is `extends`, not `implements`, precisely so [willPromptForPermission] can carry a
  /// default: Dart's `implements` demands every member be restated, which would have put the same
  /// `=> false` in four test fakes.
  const ILocationService();

  /// Returns the current GPS position, or null if unavailable/denied.
  /// Never throws — failures are silently absorbed.
  Future<GpsCoords?> getCurrentPosition();

  /// Whether calling [getCurrentPosition] would put an OS permission dialog on screen.
  ///
  /// Exists so the UI can state the purpose *before* the system asks. The prompt used to appear
  /// inside an "Acquisisci" button with nothing saying what the coordinate was for or what happened
  /// if they refused — and on iOS the dialog cannot be shown again, so the first ask is the only
  /// one there is.
  ///
  /// Concrete rather than abstract so the test fakes and [DisabledLocationService] inherit the
  /// honest answer (they never prompt) instead of each having to restate it.
  Future<bool> willPromptForPermission() async => false;
}

// ── Real implementation ───────────────────────────────────────────────────────

class LocationService extends ILocationService {
  const LocationService();

  /// Only `denied` produces a dialog. `deniedForever` never asks again — there the honest move is
  /// to let the call fail and tell the technician where the system setting lives, not to open a
  /// purpose sheet that leads nowhere.
  @override
  Future<bool> willPromptForPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      return await Geolocator.checkPermission() == LocationPermission.denied;
    } catch (_) {
      return false;
    }
  }

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

// ── Disabled implementation ───────────────────────────────────────────────────

/// What the app uses when the technician has turned "Geolocalizzazione" off.
///
/// Returns null exactly as the real service does on a denial, so every call site already handles
/// it — the position is simply absent, and no record claims one was taken.
class DisabledLocationService extends ILocationService {
  const DisabledLocationService();

  @override
  Future<GpsCoords?> getCurrentPosition() async => null;
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Whether the technician has allowed the app to record position.
///
/// Declared here, in core, and overridden in `main.dart` from the Impostazioni setting. Core must
/// not import a feature, and the alternative — having every call site remember to check a setting
/// — is how the setting came to control nothing in the first place.
///
/// Defaults to true so a test, or any scope that does not override it, behaves like the app did
/// before the setting was honoured.
final gpsPreferenceProvider = Provider<bool>((ref) => true);

/// Provides the [ILocationService]. Override in tests with a fake.
///
/// The gate lives here rather than at the call sites. "Geolocalizzazione — Posizione GPS per i
/// rapportini" was a switch wired to nothing: it wrote a bool that no code ever read, while
/// `cantiere_timbra_screen` captured a position on every clock-in regardless. A settings toggle
/// that reports a choice it does not enforce is worse than no toggle, and under a consent audit it
/// is worse still.
final locationServiceProvider = Provider<ILocationService>((ref) {
  return ref.watch(gpsPreferenceProvider)
      ? const LocationService()
      : const DisabledLocationService();
});
