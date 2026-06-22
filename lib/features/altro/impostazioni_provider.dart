import 'package:flutter_riverpod/flutter_riverpod.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Settings state
// ══════════════════════════════════════════════════════════════════════════════

/// App-wide settings state (in-memory).
///
/// Seam: `shared_preferences` is not in pubspec — add it when persisting.
// TODO: persist settings via shared_preferences or similar.
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
      autenticazioneBiometrica:
          autenticazioneBiometrica ?? this.autenticazioneBiometrica,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Notifier
// ══════════════════════════════════════════════════════════════════════════════

class ImpostazioniNotifier extends StateNotifier<ImpostazioniState> {
  ImpostazioniNotifier() : super(const ImpostazioniState());

  void toggle({required String key}) {
    // TODO: persist settings via shared_preferences after each toggle.
    state = switch (key) {
      'pushAbilitate' => state.copyWith(pushAbilitate: !state.pushAbilitate),
      'notificheInterventi' =>
        state.copyWith(notificheInterventi: !state.notificheInterventi),
      'notificheRapportini' =>
        state.copyWith(notificheRapportini: !state.notificheRapportini),
      'syncOffline' => state.copyWith(syncOffline: !state.syncOffline),
      'geoLocazione' => state.copyWith(geoLocazione: !state.geoLocazione),
      'temaScuro' => state.copyWith(temaScuro: !state.temaScuro),
      'autenticazioneBiometrica' => state.copyWith(
          autenticazioneBiometrica: !state.autenticazioneBiometrica),
      _ => state,
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider
// ══════════════════════════════════════════════════════════════════════════════

final impostazioniProvider =
    StateNotifierProvider<ImpostazioniNotifier, ImpostazioniState>(
  (ref) => ImpostazioniNotifier(),
);
