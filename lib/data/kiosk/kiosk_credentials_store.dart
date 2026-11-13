import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything persisted on a device once it has been activated as a kiosk (attendance totem).
class KioskCredentials {
  const KioskCredentials({
    required this.rawKey,
    required this.deviceLabel,
    this.deviceId,
    this.signingKey,
    this.serverTimeOffsetSeconds = 0,
    this.expiresInSeconds = 300,
  });

  /// The `sp_...` ServicePrincipal API key issued once by the web admin's "Registra dispositivo"
  /// flow (`RegisterKioskDeviceSheet.tsx` / `KioskDevicesController.Register`). Sent as
  /// `X-Api-Key` on every kiosk request — see [KioskApiClient].
  final String rawKey;

  /// Locally-chosen label for this tablet (e.g. "Totem ingresso cantiere Rossi"). Cosmetic only —
  /// the backend already knows the device by the name the admin gave it at registration; this is
  /// just what the activation screen shows back on this specific handset.
  final String deviceLabel;

  /// Server-issued per-device identity and QR signing key. Null on an old installation that has
  /// not provisioned the offline generator yet; [KioskModeNotifier.refreshQr] provisions on the
  /// next online attempt and persists both here.
  final String? deviceId;
  final String? signingKey;

  /// `serverTimeUtc - deviceTimeUtc` captured at provisioning, so a freshly generated token uses
  /// the server's clock even when the tablet's clock has drifted.
  final int serverTimeOffsetSeconds;
  final int expiresInSeconds;

  KioskCredentials copyWith({
    String? deviceId,
    String? signingKey,
    int? serverTimeOffsetSeconds,
    int? expiresInSeconds,
  }) => KioskCredentials(
    rawKey: rawKey,
    deviceLabel: deviceLabel,
    deviceId: deviceId ?? this.deviceId,
    signingKey: signingKey ?? this.signingKey,
    serverTimeOffsetSeconds:
        serverTimeOffsetSeconds ?? this.serverTimeOffsetSeconds,
    expiresInSeconds: expiresInSeconds ?? this.expiresInSeconds,
  );
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
  static const _deviceIdKey = 'tt.kiosk.device_id';
  static const _signingKeyKey = 'tt.kiosk.signing_key';
  static const _serverOffsetKey = 'tt.kiosk.server_offset_seconds';
  static const _expiresInKey = 'tt.kiosk.expires_in_seconds';

  final FlutterSecureStorage _storage;

  /// Returns the stored credentials, or null when this device has never been activated (or has
  /// since been deactivated/cleared).
  Future<KioskCredentials?> read() async {
    final rawKey = await _storage.read(key: _rawKeyKey);
    if (rawKey == null || rawKey.isEmpty) return null;
    final label = await _storage.read(key: _deviceLabelKey) ?? '';
    return KioskCredentials(
      rawKey: rawKey,
      deviceLabel: label,
      deviceId: await _storage.read(key: _deviceIdKey),
      signingKey: await _storage.read(key: _signingKeyKey),
      serverTimeOffsetSeconds:
          int.tryParse(await _storage.read(key: _serverOffsetKey) ?? '') ?? 0,
      expiresInSeconds:
          int.tryParse(await _storage.read(key: _expiresInKey) ?? '') ?? 300,
    );
  }

  Future<void> save({
    required String rawKey,
    required String deviceLabel,
    required String exitPin,
    String? deviceId,
    String? signingKey,
    int serverTimeOffsetSeconds = 0,
    int expiresInSeconds = 300,
  }) async {
    await _storage.write(key: _rawKeyKey, value: rawKey);
    await _storage.write(key: _deviceLabelKey, value: deviceLabel);
    await _storage.write(key: _exitPinHashKey, value: _hashPin(exitPin));
    if (deviceId != null && signingKey != null) {
      await saveProvisioning(
        deviceId: deviceId,
        signingKey: signingKey,
        serverTimeOffsetSeconds: serverTimeOffsetSeconds,
        expiresInSeconds: expiresInSeconds,
      );
    }
  }

  /// Persists the offline QR provisioning without touching the PIN or label. Used by an already
  /// activated installation upgrading from the server-issued QR token.
  Future<void> saveProvisioning({
    required String deviceId,
    required String signingKey,
    required int serverTimeOffsetSeconds,
    required int expiresInSeconds,
  }) async {
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(key: _signingKeyKey, value: signingKey);
    await _storage.write(
      key: _serverOffsetKey,
      value: '$serverTimeOffsetSeconds',
    );
    await _storage.write(key: _expiresInKey, value: '$expiresInSeconds');
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
    await _storage.delete(key: _deviceIdKey);
    await _storage.delete(key: _signingKeyKey);
    await _storage.delete(key: _serverOffsetKey);
    await _storage.delete(key: _expiresInKey);
  }

  static String _hashPin(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();
}
