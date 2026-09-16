import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kiosk/kiosk_lock_service.dart';
import '../../data/kiosk/kiosk_api_client.dart';
import '../../data/kiosk/kiosk_credentials_store.dart';

// ── Dependency providers ────────────────────────────────────────────────────

final kioskCredentialsStoreProvider = Provider<KioskCredentialsStore>((ref) {
  return KioskCredentialsStore();
});

final kioskApiClientProvider = Provider<KioskApiClient>((ref) {
  return KioskApiClient();
});

final kioskLockServiceProvider = Provider<IKioskLockService>((ref) {
  return const PlatformKioskLockService();
});

// ── Kiosk mode state ─────────────────────────────────────────────────────────

/// What the whole app needs to know about this device's kiosk status. Read by the router's
/// `redirect` callback to force every route to `/kiosk` once active (see `app_router.dart`), and
/// by `KioskDisplayScreen`/`KioskActivationScreen` for their own UI.
class KioskModeState {
  const KioskModeState({
    this.loading = true,
    this.active = false,
    this.deviceLabel,
    this.lockOutcome,
  });

  /// True only during the very first read of secure storage at app start — the router treats
  /// "loading" like `authStateProvider`'s own `AsyncLoading` does: stay put, don't redirect yet.
  final bool loading;

  final bool active;
  final String? deviceLabel;

  /// Result of the last `IKioskLockService.start()` call, so the display screen can show the
  /// iOS "this tablet is NOT actually locked down" notice when relevant. Null before kiosk mode
  /// has attempted to lock at all.
  final KioskLockOutcome? lockOutcome;

  KioskModeState copyWith({
    bool? loading,
    bool? active,
    String? deviceLabel,
    KioskLockOutcome? lockOutcome,
  }) {
    return KioskModeState(
      loading: loading ?? this.loading,
      active: active ?? this.active,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      lockOutcome: lockOutcome ?? this.lockOutcome,
    );
  }
}

/// Owns the device's kiosk activation lifecycle: read state at boot, activate (validate +
/// persist + lock), deactivate (PIN check + unlock + wipe), and react to the backend revoking
/// this device out from under it.
class KioskModeNotifier extends StateNotifier<KioskModeState> {
  KioskModeNotifier(this._store, this._api, this._lock)
    : super(const KioskModeState()) {
    _init();
  }

  final KioskCredentialsStore _store;
  final KioskApiClient _api;
  final IKioskLockService _lock;

  Future<void> _init() async {
    final creds = await _store.read();
    if (creds == null) {
      state = const KioskModeState(loading: false, active: false);
      return;
    }
    // A device that was already active before the app restarted (kiosk tablets stay powered on
    // for weeks, but crashes/OS updates happen) re-locks itself immediately rather than sitting
    // unpinned on whatever screen it happened to land on.
    final outcome = await _lock.start();
    state = KioskModeState(
      loading: false,
      active: true,
      deviceLabel: creds.deviceLabel,
      lockOutcome: outcome,
    );
  }

  /// Validates [rawKey] against the backend (any successful `GET kiosk/qr` proves it is a live,
  /// entitled kiosk credential), then persists it, locks the device, and flips the app into
  /// kiosk mode. Throws [KioskApiException] on a bad key or a network problem — the activation
  /// screen surfaces that message and nothing is persisted/locked on failure.
  Future<void> activate({
    required String rawKey,
    required String deviceLabel,
    required String exitPin,
  }) async {
    await _api.fetchQr(
      rawKey,
    ); // throws KioskApiException on invalid/revoked/network/etc.
    await _store.save(
      rawKey: rawKey,
      deviceLabel: deviceLabel,
      exitPin: exitPin,
    );
    final outcome = await _lock.start();
    state = KioskModeState(
      loading: false,
      active: true,
      deviceLabel: deviceLabel,
      lockOutcome: outcome,
    );
  }

  /// Fetches the next rotating QR token for display. On
  /// [KioskApiFailureReason.invalidOrRevoked] — the admin revoked this device from the web —
  /// automatically deactivates kiosk mode on the device itself rather than leaving it pinned to
  /// a dead credential forever.
  Future<KioskQrToken> refreshQr() async {
    final creds = await _store.read();
    if (creds == null) {
      throw const KioskApiException(KioskApiFailureReason.invalidOrRevoked);
    }
    try {
      return await _api.fetchQr(creds.rawKey);
    } on KioskApiException catch (e) {
      if (e.reason == KioskApiFailureReason.invalidOrRevoked) {
        await _forceDeactivate();
      }
      rethrow;
    }
  }

  /// Human-initiated exit: only proceeds when [pin] matches the PIN chosen at activation.
  /// Returns false (state unchanged) on a wrong PIN.
  Future<bool> deactivate(String pin) async {
    final ok = await _store.verifyExitPin(pin);
    if (!ok) return false;
    await _forceDeactivate();
    return true;
  }

  Future<void> _forceDeactivate() async {
    await _lock.stop();
    await _store.clear();
    state = const KioskModeState(loading: false, active: false);
  }
}

final kioskModeProvider =
    StateNotifierProvider<KioskModeNotifier, KioskModeState>((ref) {
      return KioskModeNotifier(
        ref.watch(kioskCredentialsStoreProvider),
        ref.watch(kioskApiClientProvider),
        ref.watch(kioskLockServiceProvider),
      );
    });
