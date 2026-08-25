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
const _kNotificheEmail = 'settings.notifiche_email';
const _kNotificheInApp = 'settings.notifiche_in_app';
const _kNotificheInterventi = 'settings.notifiche_interventi';
const _kNotifichePianificazione = 'settings.notifiche_pianificazione';
const _kNotificheLicenza = 'settings.notifiche_licenza';
const _kNotificheOrePresenze = 'settings.notifiche_ore_presenze';
const _kNotificheRapportini = 'settings.notifiche_rapportini';
const _kNotificheMenzioni = 'settings.notifiche_menzioni';
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
    // Notifiche — canali
    this.pushAbilitate = true,
    this.notificheEmail = true,
    this.notificheInApp = true,
    // Notifiche — categorie
    this.notificheInterventi = true,
    this.notifichePianificazione = true,
    this.notificheLicenza = true,
    this.notificheOrePresenze = true,
    this.notificheRapportini = true,
    this.notificheMenzioni = true,
    // App
    this.syncOffline = true,
    // True, not false. GPS was captured on every cantiere clock-in regardless of this flag, so
    // honouring a false default would have silently switched off the position evidence that makes
    // a timbratura defensible. The behaviour is unchanged; the difference is that turning it off
    // now actually turns it off.
    this.geoLocazione = true,
    this.temaScuro = false,
    // Account
    this.autenticazioneBiometrica = false,
  });

  // ── Notifiche — canali ───────────────────────────────────────────────────
  final bool pushAbilitate;
  final bool notificheEmail;
  final bool notificheInApp;

  // ── Notifiche — categorie ────────────────────────────────────────────────
  final bool notificheInterventi;
  final bool notifichePianificazione;
  final bool notificheLicenza;
  final bool notificheOrePresenze;
  final bool notificheRapportini;
  final bool notificheMenzioni;

  // ── App ──────────────────────────────────────────────────────────────────
  final bool syncOffline;
  final bool geoLocazione;
  final bool temaScuro;

  // ── Account ──────────────────────────────────────────────────────────────
  final bool autenticazioneBiometrica;

  ImpostazioniState copyWith({
    bool? pushAbilitate,
    bool? notificheEmail,
    bool? notificheInApp,
    bool? notificheInterventi,
    bool? notifichePianificazione,
    bool? notificheLicenza,
    bool? notificheOrePresenze,
    bool? notificheRapportini,
    bool? notificheMenzioni,
    bool? syncOffline,
    bool? geoLocazione,
    bool? temaScuro,
    bool? autenticazioneBiometrica,
  }) {
    return ImpostazioniState(
      pushAbilitate: pushAbilitate ?? this.pushAbilitate,
      notificheEmail: notificheEmail ?? this.notificheEmail,
      notificheInApp: notificheInApp ?? this.notificheInApp,
      notificheInterventi: notificheInterventi ?? this.notificheInterventi,
      notifichePianificazione: notifichePianificazione ?? this.notifichePianificazione,
      notificheLicenza: notificheLicenza ?? this.notificheLicenza,
      notificheOrePresenze: notificheOrePresenze ?? this.notificheOrePresenze,
      notificheRapportini: notificheRapportini ?? this.notificheRapportini,
      notificheMenzioni: notificheMenzioni ?? this.notificheMenzioni,
      syncOffline: syncOffline ?? this.syncOffline,
      geoLocazione: geoLocazione ?? this.geoLocazione,
      temaScuro: temaScuro ?? this.temaScuro,
      autenticazioneBiometrica:
          autenticazioneBiometrica ?? this.autenticazioneBiometrica,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Notifier (persisted via shared_preferences)
// ══════════════════════════════════════════════════════════════════════════════

class ImpostazioniNotifier extends StateNotifier<ImpostazioniState> {
  ImpostazioniNotifier(this._authRepo, this._api)
    : super(const ImpostazioniState()) {
    _loadFromPrefs()
        .then((_) => _reconcilePushWithOs())
        .then((_) => unawaited(reconcileWithServer()));
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
      notificheEmail: prefs.getBool(_kNotificheEmail) ?? true,
      notificheInApp: prefs.getBool(_kNotificheInApp) ?? true,
      notificheInterventi: prefs.getBool(_kNotificheInterventi) ?? true,
      notifichePianificazione: prefs.getBool(_kNotifichePianificazione) ?? true,
      notificheLicenza: prefs.getBool(_kNotificheLicenza) ?? true,
      notificheOrePresenze: prefs.getBool(_kNotificheOrePresenze) ?? true,
      notificheRapportini: prefs.getBool(_kNotificheRapportini) ?? true,
      notificheMenzioni: prefs.getBool(_kNotificheMenzioni) ?? true,
      syncOffline: prefs.getBool(_kSyncOffline) ?? true,
      geoLocazione: prefs.getBool(_kGeoLocazione) ?? true,
      temaScuro: prefs.getBool(_kTemaScuro) ?? false,
      autenticazioneBiometrica:
          prefs.getBool(_kAutenticazioneBiometrica) ?? false,
    );
  }

  /// Force "Notifiche push" off when the OS will not deliver any.
  ///
  /// `pushAbilitate` defaults to **true**, and the permission request no longer happens at startup
  /// — it happens when this switch is turned on. Without this reconcile, a fresh install would show
  /// the switch already on while the OS had never been asked, which is the exact defect the move
  /// was meant to fix: a control reporting a state the system will not honour.
  ///
  /// It also catches the case that has always been possible and was never handled — permission
  /// revoked from the phone's own settings between sessions.
  ///
  /// Never forces the switch *on*. Holding the OS permission is not the same as wanting push, and
  /// a setting that turned itself back on would be worse than one that lags.
  Future<void> _reconcilePushWithOs() async {
    if (!state.pushAbilitate) return;
    // Firebase absent (init failed, no Play Services, every widget test) — nothing to reconcile
    // against, and touching `instance` here would throw `[core/no-app]`.
    if (!NotificationService.isAvailable) return;

    if (await NotificationService.instance.hasPermission()) return;

    state = state.copyWith(pushAbilitate: false);
    await _persist('pushAbilitate', false);
  }

  /// Toggle a setting by key and persist to SharedPreferences.
  void toggle({required String key}) {
    state = switch (key) {
      'pushAbilitate' => state.copyWith(pushAbilitate: !state.pushAbilitate),
      'notificheEmail' => state.copyWith(notificheEmail: !state.notificheEmail),
      'notificheInApp' => state.copyWith(notificheInApp: !state.notificheInApp),
      'notificheInterventi' => state.copyWith(
        notificheInterventi: !state.notificheInterventi,
      ),
      'notifichePianificazione' => state.copyWith(
        notifichePianificazione: !state.notifichePianificazione,
      ),
      'notificheLicenza' => state.copyWith(notificheLicenza: !state.notificheLicenza),
      'notificheOrePresenze' => state.copyWith(
        notificheOrePresenze: !state.notificheOrePresenze,
      ),
      'notificheRapportini' => state.copyWith(
        notificheRapportini: !state.notificheRapportini,
      ),
      'notificheMenzioni' => state.copyWith(notificheMenzioni: !state.notificheMenzioni),
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

  /// The nine toggles that have a server field (everything except `enableSMS`, which has no
  /// backend send-path implementation and therefore no UI here). The four device settings below
  /// have no server counterpart, and sending them anywhere would be inventing a contract.
  static bool _isServerBacked(String key) => switch (key) {
    'pushAbilitate' ||
    'notificheEmail' ||
    'notificheInApp' ||
    'notificheInterventi' ||
    'notifichePianificazione' ||
    'notificheLicenza' ||
    'notificheOrePresenze' ||
    'notificheRapportini' ||
    'notificheMenzioni' => true,
    _ => false,
  };

  /// Send the nine server-backed toggles, marking them pending until the server confirms.
  ///
  /// The pending flag is written *before* the request, not after a failure: a process killed
  /// mid-flight would otherwise leave the change local-only with nothing recording that it had
  /// never been sent.
  Future<void> _pushToServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifichePending, true);
    try {
      await _api.update(
        enableInApp: state.notificheInApp,
        enablePush: state.pushAbilitate,
        enableEmail: state.notificheEmail,
        ticketNotifications: state.notificheInterventi,
        scheduleNotifications: state.notifichePianificazione,
        licenseNotifications: state.notificheLicenza,
        workLogNotifications: state.notificheOrePresenze,
        documentNotifications: state.notificheRapportini,
        mentionNotifications: state.notificheMenzioni,
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
      notificheEmail: remote.enableEmail,
      notificheInApp: remote.enableInApp,
      notificheInterventi: remote.ticketNotifications,
      notifichePianificazione: remote.scheduleNotifications,
      notificheLicenza: remote.licenseNotifications,
      notificheOrePresenze: remote.workLogNotifications,
      notificheRapportini: remote.documentNotifications,
      notificheMenzioni: remote.mentionNotifications,
    );

    await prefs.setBool(_kPushAbilitate, remote.enablePush);
    await prefs.setBool(_kNotificheEmail, remote.enableEmail);
    await prefs.setBool(_kNotificheInApp, remote.enableInApp);
    await prefs.setBool(_kNotificheInterventi, remote.ticketNotifications);
    await prefs.setBool(_kNotifichePianificazione, remote.scheduleNotifications);
    await prefs.setBool(_kNotificheLicenza, remote.licenseNotifications);
    await prefs.setBool(_kNotificheOrePresenze, remote.workLogNotifications);
    await prefs.setBool(_kNotificheRapportini, remote.documentNotifications);
    await prefs.setBool(_kNotificheMenzioni, remote.mentionNotifications);

    // Push arriving from another device still has to register or unregister *this* one.
    if (pushChanged) _syncPushRegistration(remote.enablePush);
  }

  bool _valueForKey(String key) => switch (key) {
    'pushAbilitate' => state.pushAbilitate,
    'notificheEmail' => state.notificheEmail,
    'notificheInApp' => state.notificheInApp,
    'notificheInterventi' => state.notificheInterventi,
    'notifichePianificazione' => state.notifichePianificazione,
    'notificheLicenza' => state.notificheLicenza,
    'notificheOrePresenze' => state.notificheOrePresenze,
    'notificheRapportini' => state.notificheRapportini,
    'notificheMenzioni' => state.notificheMenzioni,
    'syncOffline' => state.syncOffline,
    'geoLocazione' => state.geoLocazione,
    'temaScuro' => state.temaScuro,
    'autenticazioneBiometrica' => state.autenticazioneBiometrica,
    _ => false,
  };

  String _prefKeyForKey(String key) => switch (key) {
    'pushAbilitate' => _kPushAbilitate,
    'notificheEmail' => _kNotificheEmail,
    'notificheInApp' => _kNotificheInApp,
    'notificheInterventi' => _kNotificheInterventi,
    'notifichePianificazione' => _kNotifichePianificazione,
    'notificheLicenza' => _kNotificheLicenza,
    'notificheOrePresenze' => _kNotificheOrePresenze,
    'notificheRapportini' => _kNotificheRapportini,
    'notificheMenzioni' => _kNotificheMenzioni,
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

final impostazioniProvider =
    StateNotifierProvider<ImpostazioniNotifier, ImpostazioniState>(
      (ref) => ImpostazioniNotifier(
        ref.watch(authRepositoryProvider),
        ref.watch(notificationSettingsApiClientProvider),
      ),
    );
