import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything persisted on a device once it has been activated as a kiosk (attendance totem).
class KioskCredentials {
  const KioskCredentials({required this.rawKey, required this.deviceLabel});

  /// The `sp_...` ServicePrincipal API key issued once by the web admin's "Registra dispositivo"
  /// flow (`RegisterKioskDeviceSheet.tsx` / `KioskDevicesController.Register`). Sent as
  /// `X-Api-Key` on every kiosk request — see [KioskApiClient].
  final String rawKey;

  /// Locally-chosen label for this tablet (e.g. "Totem ingresso cantiere Rossi"). Cosmetic only —
  /// the backend already knows the device by the name the admin gave it at registration; this is
  /// just what the activation screen shows back on this specific handset.
  final String deviceLabel;
}

/// Secure, on-device storage for kiosk mode's activation state.
///
/// Three values live here, all under `flutter_secure_storage` (Keystore/Keychain-backed — the
/// same mechanism [ZitadelAuthRepository] uses for the refresh token; see that class's own doc
/// comment):
/// - the raw kiosk API key — this device's actual credential, never the interactive Zitadel
///   session a technician's own phone uses;
/// - a local label, purely cosmetic;
/// - a SHA-256 hash of a locally-chosen exit PIN — never the PIN itself — checked by
///   `KioskModeNotifier.deactivate` before a kiosk tablet can be unpinned and handed back to
///   ordinary sign-in. Hashed the same spirit as the backend hashes API keys
///   (`ApiKeyGenerator.Hash` in TaskTapAPI.Core.Security): the PIN only ever needs to be
///   compared, never recovered.
class KioskCredentialsStore {
  KioskCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _rawKeyKey = 'tt.kiosk.raw_key';
  static const _deviceLabelKey = 'tt.kiosk.device_label';
  static const _exitPinHashKey = 'tt.kiosk.exit_pin_hash';

  final FlutterSecureStorage _storage;

  /// Returns the stored credentials, or null when this device has never been activated (or has
  /// since been deactivated/cleared).
  Future<KioskCredentials?> read() async {
    final rawKey = await _storage.read(key: _rawKeyKey);
    if (rawKey == null || rawKey.isEmpty) return null;
    final label = await _storage.read(key: _deviceLabelKey) ?? '';
    return KioskCredentials(rawKey: rawKey, deviceLabel: label);
  }

  Future<void> save({
    required String rawKey,
    required String deviceLabel,
    required String exitPin,
  }) async {
    await _storage.write(key: _rawKeyKey, value: rawKey);
    await _storage.write(key: _deviceLabelKey, value: deviceLabel);
    await _storage.write(key: _exitPinHashKey, value: _hashPin(exitPin));
  }

  /// Compares [pin] against the stored hash. False (never throws) when no PIN was ever set —
  /// that reads as "wrong PIN", not "any PIN works", which is the safe default for an exit gate.
  Future<bool> verifyExitPin(String pin) async {
    final storedHash = await _storage.read(key: _exitPinHashKey);
    if (storedHash == null) return false;
    return storedHash == _hashPin(pin);
  }

  /// Wipes all kiosk state. Called on deactivation and whenever the backend reports the device's
  /// key as invalid/revoked (`KioskApiFailureReason.invalidOrRevoked`) — an admin revoking a
  /// device from the web must end kiosk mode on the tablet itself the next time it polls, not
  /// just stop it from working.
  Future<void> clear() async {
    await _storage.delete(key: _rawKeyKey);
    await _storage.delete(key: _deviceLabelKey);
    await _storage.delete(key: _exitPinHashKey);
  }

  static String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();
}
