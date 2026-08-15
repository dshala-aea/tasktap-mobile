import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/notification_service.dart';
import '../../data/settings/notification_settings_api_client.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../../presentation/providers/auth_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SharedPreferences keys
// ══════════════════════════════════════════════════════════════════════════════

const _kPushAbilitate = 'settings.push_abilitate';
const _kNotificheInterventi = 'settings.notifiche_interventi';
const _kNotificheRapportini = 'settings.notifiche_rapportini';
const _kSyncOffline = 'settings.sync_offline';
const _kGeoLocazione = 'settings.geo_locazione';
const _kTemaScuro = 'settings.tema_scuro';
const _kAutenticazioneBiometrica = 'settings.auth_biometrica';

/// Set when a notification toggle was changed but the server never confirmed it.
///
/// Without it, the next successful fetch would pull the server's older value straight back over a
/// change the technician made in a basement — the setting would appear to undo itself minutes
/// later, which is worse than never having synced at all. While this is set the reconcile pushes
/// instead of pulling.
const _kNotifichePending = 'settings.notifiche_pending';

// ══════════════════════════════════════════════════════════════════════════════
// Settings state
// ══════════════════════════════════════════════════════════════════════════════

class ImpostazioniState {
  const ImpostazioniState({
    // Notifiche
    this.pushAbilitate = true,
    this.notificheInterventi = true,
    this.notificheRapportini = true,
    // App
    this.syncOffline = true,
    this.geoLocazione = false,
    this.temaScuro = false,
    // Account
    this.autenticazioneBiometrica = false,
  });

  // ── Notifiche ────────────────────────────────────────────────────────────
  final bool pushAbilitate;
  final bool notificheInterventi;
  final bool notificheRapportini;

  // ── App ──────────────────────────────────────────────────────────────────
  final bool syncOffline;
  final bool geoLocazione;
  final bool temaScuro;

  // ── Account ──────────────────────────────────────────────────────────────
  final bool autenticazioneBiometrica;

  ImpostazioniState copyWith({
    bool? pushAbilitate,
    bool? notificheInterventi,
    bool? notificheRapportini,
    bool? syncOffline,
    bool? geoLocazione,
    bool? temaScuro,
    bool? autenticazioneBiometrica,
  }) {
    return ImpostazioniState(
      pushAbilitate: pushAbilitate ?? this.pushAbilitate,
      notificheInterventi: notificheInterventi ?? this.notificheInterventi,
      notificheRapportini: notificheRapportini ?? this.notificheRapportini,
      syncOffline: syncOffline ?? this.syncOffline,
      geoLocazione: geoLocazione ?? this.geoLocazione,
      temaScuro: temaScuro ?? this.temaScuro,
      autenticazioneBiometrica: autenticazioneBiometrica ?? this.autenticazioneBiometrica,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Notifier (persisted via shared_preferences)
// ══════════════════════════════════════════════════════════════════════════════

class ImpostazioniNotifier extends StateNotifier<ImpostazioniState> {
  ImpostazioniNotifier(this._authRepo, this._api) : super(const ImpostazioniState()) {
    _loadFromPrefs().then((_) => unawaited(reconcileWithServer()));
  }

  final IAuthRepository _authRepo;
  final NotificationSettingsApiClient _api;

  /// Load persisted settings from SharedPreferences.
  ///
  /// Local prefs stay the source of truth for what the screen shows. They are on the device, they
  /// read instantly, and they work with the radio off — which the four device-only settings
  /// (offline sync, GPS, dark theme, biometrics) require, since no server field corresponds to
  /// them at all.
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = ImpostazioniState(
      pushAbilitate: prefs.getBool(_kPushAbilitate) ?? true,
      notificheInterventi: prefs.getBool(_kNotificheInterventi) ?? true,
      notificheRapportini: prefs.getBool(_kNotificheRapportini) ?? true,
      syncOffline: prefs.getBool(_kSyncOffline) ?? true,
      geoLocazione: prefs.getBool(_kGeoLocazione) ?? false,
      temaScuro: prefs.getBool(_kTemaScuro) ?? false,
      autenticazioneBiometrica: prefs.getBool(_kAutenticazioneBiometrica) ?? false,
    );
  }

  /// Toggle a setting by key and persist to SharedPreferences.
  void toggle({required String key}) {
    state = switch (key) {
      'pushAbilitate' => state.copyWith(pushAbilitate: !state.pushAbilitate),
      'notificheInterventi' => state.copyWith(notificheInterventi: !state.notificheInterventi),
      'notificheRapportini' => state.copyWith(notificheRapportini: !state.notificheRapportini),
      'syncOffline' => state.copyWith(syncOffline: !state.syncOffline),
      'geoLocazione' => state.copyWith(geoLocazione: !state.geoLocazione),
      'temaScuro' => state.copyWith(temaScuro: !state.temaScuro),
      'autenticazioneBiometrica' => state.copyWith(
        autenticazioneBiometrica: !state.autenticazioneBiometrica,
      ),
      _ => state,
    };

    // Persist the toggled value. Fire-and-forget: `_persist` awaits its own
    // `SharedPreferences.getInstance()` (cached after the first call, so this
    // is cheap even if it races `_loadFromPrefs()` — unlike a shared `late
    // final` field, there's no window where a fast tap right after screen
    // open throws a LateInitializationError).
    unawaited(_persist(key, _valueForKey(key)));

    // Side-effect: push toggle controls device registration. This is the one notification setting
    // that takes effect today, and it takes effect here on the device rather than on the server.
    if (key == 'pushAbilitate') {
      _syncPushRegistration(state.pushAbilitate);
    }

    if (_isServerBacked(key)) {
      unawaited(_pushToServer());
    }
  }

  /// The three toggles that have a server field. The other four are device settings with no
  /// server counterpart, and sending them anywhere would be inventing a contract.
  static bool _isServerBacked(String key) =>
      key == 'pushAbilitate' || key == 'notificheInterventi' || key == 'notificheRapportini';

  /// Send the three server-backed toggles, marking them pending until the server confirms.
  ///
  /// The pending flag is written *before* the request, not after a failure: a process killed
  /// mid-flight would otherwise leave the change local-only with nothing recording that it had
  /// never been sent.
  Future<void> _pushToServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifichePending, true);
    try {
      await _api.update(
        enablePush: state.pushAbilitate,
        ticketNotifications: state.notificheInterventi,
        documentNotifications: state.notificheRapportini,
      );
      await prefs.setBool(_kNotifichePending, false);
    } catch (_) {
      // Deliberately swallowed, and deliberately not reverted. The technician's choice is already
      // saved on the device and already in effect for push; a settings screen that snaps a toggle
      // back because a request timed out is worse than one that syncs late.
    }
  }

  /// Reconcile local notification settings with the server.
  ///
  /// Direction depends on whether a local change is still unsent. Pending → push, so a change made
  /// offline survives. Otherwise → pull, so a change made on another device arrives here. Any
  /// failure leaves local state exactly as it was.
  Future<void> reconcileWithServer() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_kNotifichePending) ?? false) {
      await _pushToServer();
      return;
    }

    final NotificationSettingsDto remote;
    try {
      remote = await _api.fetch();
    } catch (_) {
      return;
    }

    final pushChanged = remote.enablePush != state.pushAbilitate;

    state = state.copyWith(
      pushAbilitate: remote.enablePush,
      notificheInterventi: remote.ticketNotifications,
      notificheRapportini: remote.documentNotifications,
    );

    await prefs.setBool(_kPushAbilitate, remote.enablePush);
    await prefs.setBool(_kNotificheInterventi, remote.ticketNotifications);
    await prefs.setBool(_kNotificheRapportini, remote.documentNotifications);

    // Push arriving from another device still has to register or unregister *this* one.
    if (pushChanged) _syncPushRegistration(remote.enablePush);
  }

  bool _valueForKey(String key) => switch (key) {
    'pushAbilitate' => state.pushAbilitate,
    'notificheInterventi' => state.notificheInterventi,
    'notificheRapportini' => state.notificheRapportini,
    'syncOffline' => state.syncOffline,
    'geoLocazione' => state.geoLocazione,
    'temaScuro' => state.temaScuro,
    'autenticazioneBiometrica' => state.autenticazioneBiometrica,
    _ => false,
  };

  String _prefKeyForKey(String key) => switch (key) {
    'pushAbilitate' => _kPushAbilitate,
    'notificheInterventi' => _kNotificheInterventi,
    'notificheRapportini' => _kNotificheRapportini,
    'syncOffline' => _kSyncOffline,
    'geoLocazione' => _kGeoLocazione,
    'temaScuro' => _kTemaScuro,
    'autenticazioneBiometrica' => _kAutenticazioneBiometrica,
    _ => key,
  };

  Future<void> _persist(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyForKey(key), value);
  }

  /// Register or unregister the device token when push is toggled.
  ///
  /// Guarded on `NotificationService.isAvailable` — same as the two call
  /// sites in main.dart. `NotificationService.instance` eagerly touches
  /// `FirebaseMessaging.instance` on first access and throws `[core/no-app]`
  /// if Firebase was never initialized (missing config, no Play Services,
  /// offline at cold start — an explicitly supported, silently-degraded
  /// path). Without this guard, a logged-in user tapping "Notifiche push"
  /// on a device where Firebase init failed would crash this callback.
  void _syncPushRegistration(bool enabled) {
    if (!NotificationService.isAvailable) return;
    final token = _authRepo.currentUser?.accessToken;
    if (token == null || token.isEmpty) return;
    if (enabled) {
      NotificationService.instance.registerDeviceToken(token);
    } else {
      NotificationService.instance.unregisterDeviceToken(token);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider
// ══════════════════════════════════════════════════════════════════════════════

final impostazioniProvider = StateNotifierProvider<ImpostazioniNotifier, ImpostazioniState>(
  (ref) => ImpostazioniNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(notificationSettingsApiClientProvider),
  ),
);
