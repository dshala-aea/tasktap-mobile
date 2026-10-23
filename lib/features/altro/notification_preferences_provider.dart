import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/notification_preferences_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Labels and grouping
//
// The server sends an ordinal and an enum name, never a label. Italian copy and the grouping live
// here, keyed by ordinal, because that is the stable half of the contract: a new ordinal the
// server adds before this build knows it falls through to its `key` in [PrefGroup.altro] instead
// of crashing or disappearing.
// ══════════════════════════════════════════════════════════════════════════════

enum PrefGroup {
  interventi('Interventi'),
  pianificazione('Pianificazione'),
  rapportini('Rapporti di lavoro e ore'),
  assenze('Assenze'),
  magazzino('Magazzino'),
  sistema('Sistema'),

  /// Ordinals this build has no entry for.
  altro('Altro');

  const PrefGroup(this.title);
  final String title;
}

class NotificationPrefLabel {
  const NotificationPrefLabel(this.group, this.title, this.subtitle);
  final PrefGroup group;
  final String title;
  final String subtitle;
}

/// Ordinal → copy. Ordinals match the backend `NotificationType` enum; 7, 8 and 22 are not
/// user-controllable (or retired) and are deliberately absent, as are the locked types.
const Map<int, NotificationPrefLabel> kNotificationPrefLabels = {
  0: NotificationPrefLabel(
    PrefGroup.interventi,
    'Intervento assegnato',
    'Quando ti viene assegnato un intervento',
  ),
  1: NotificationPrefLabel(
    PrefGroup.interventi,
    'Cambio di stato',
    'Quando cambia lo stato di un tuo intervento',
  ),
  2: NotificationPrefLabel(
    PrefGroup.interventi,
    'Nuovo intervento',
    'Quando viene creato un nuovo intervento',
  ),
  3: NotificationPrefLabel(
    PrefGroup.interventi,
    'Intervento completato',
    'Quando un intervento viene completato',
  ),
  4: NotificationPrefLabel(
    PrefGroup.interventi,
    'Intervento in ritardo',
    'Quando un tuo intervento supera la scadenza',
  ),
  23: NotificationPrefLabel(
    PrefGroup.interventi,
    'Riepilogo interventi in ritardo',
    'Il riepilogo giornaliero degli interventi in ritardo',
  ),
  15: NotificationPrefLabel(
    PrefGroup.interventi,
    'Manutenzione in scadenza',
    'Quando una manutenzione programmata sta per scadere',
  ),
  21: NotificationPrefLabel(
    PrefGroup.interventi,
    'Cantiere assegnato',
    'Quando vieni assegnato a un cantiere',
  ),
  5: NotificationPrefLabel(
    PrefGroup.pianificazione,
    'Promemoria pianificazione',
    'Un promemoria prima di una attività pianificata',
  ),
  6: NotificationPrefLabel(
    PrefGroup.pianificazione,
    'Inizio attività',
    'Quando sta per iniziare una attività pianificata',
  ),
  26: NotificationPrefLabel(
    PrefGroup.pianificazione,
    'Pianificazione modificata',
    'Quando cambia una attività pianificata',
  ),
  9: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Ore inviate',
    'Quando vengono inviate le ore di lavoro',
  ),
  24: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Ore corrette',
    'Quando le tue ore vengono corrette dall\'ufficio',
  ),
  16: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Soglia straordinari superata',
    'Quando le ore superano la soglia degli straordinari',
  ),
  25: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Rapporto di lavoro inviato',
    'Quando un tecnico invia un rapporto di lavoro all\'ufficio',
  ),
  17: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Rapporto di lavoro rivisto',
    'Quando un tuo rapporto di lavoro viene rivisto',
  ),
  18: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Rapporto di lavoro respinto',
    'Quando un tuo rapporto di lavoro viene respinto',
  ),
  19: NotificationPrefLabel(
    PrefGroup.rapportini,
    'Rapporto di lavoro annullato',
    'Quando un rapporto di lavoro viene annullato',
  ),
  20: NotificationPrefLabel(
    PrefGroup.assenze,
    'Richiesta di assenza inviata',
    'Quando un collega invia una richiesta di assenza',
  ),
  14: NotificationPrefLabel(
    PrefGroup.assenze,
    'Esito richiesta di assenza',
    'Quando la tua richiesta viene approvata o rifiutata',
  ),
  13: NotificationPrefLabel(
    PrefGroup.magazzino,
    'Scorta bassa',
    'Quando un articolo scende sotto la soglia minima',
  ),
  10: NotificationPrefLabel(
    PrefGroup.sistema,
    'Documento caricato',
    'Quando viene caricato un nuovo documento',
  ),
  11: NotificationPrefLabel(
    PrefGroup.sistema,
    'Comunicazioni aziendali',
    'Avvisi generali inviati dall\'azienda',
  ),
  12: NotificationPrefLabel(
    PrefGroup.sistema,
    'Menzioni',
    'Quando vieni menzionato in un commento',
  ),
};

/// What to draw for one server row. Falls back to the enum [NotificationPreferenceDto.key] so an
/// ordinal added server-side still renders.
NotificationPrefLabel labelFor(NotificationPreferenceDto dto) =>
    kNotificationPrefLabels[dto.type] ?? NotificationPrefLabel(PrefGroup.altro, dto.key, '');

/// Groups in display order, each with its rows in the server's (enum) order. Empty groups are
/// omitted.
List<(PrefGroup, List<NotificationPreferenceDto>)> groupPreferences(
  List<NotificationPreferenceDto> items,
) {
  return [
    for (final group in PrefGroup.values)
      if (items.where((i) => labelFor(i).group == group).toList() case final rows
          when rows.isNotEmpty)
        (group, rows),
  ];
}

// ══════════════════════════════════════════════════════════════════════════════
// State
// ══════════════════════════════════════════════════════════════════════════════

class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.items = const [],
    this.loading = true,
    this.error,
    this.pending = const {},
  });

  final List<NotificationPreferenceDto> items;
  final bool loading;

  /// Set when the initial load failed; [items] is then empty.
  final NotificationPreferencesFailure? error;

  /// Ordinals with a write in flight. A row in this set ignores further taps, so an answer can
  /// never be matched with the wrong request.
  final Set<int> pending;

  NotificationPreferencesState copyWith({
    List<NotificationPreferenceDto>? items,
    bool? loading,
    NotificationPreferencesFailure? error,
    bool clearError = false,
    Set<int>? pending,
  }) {
    return NotificationPreferencesState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      pending: pending ?? this.pending,
    );
  }
}

class NotificationPreferencesNotifier extends StateNotifier<NotificationPreferencesState> {
  NotificationPreferencesNotifier(this._api) : super(const NotificationPreferencesState()) {
    load();
  }

  final NotificationPreferencesApiClient _api;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await _api.fetch();
      if (!mounted) return;
      state = state.copyWith(items: items, loading: false);
    } on NotificationPreferencesFailure catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Flips [type] optimistically and writes it. Returns null on success, or the sentence to toast
  /// after the switch has been put back.
  Future<String?> toggle(int type) async {
    if (state.pending.contains(type)) return null;
    final index = state.items.indexWhere((i) => i.type == type);
    if (index < 0) return null;

    final before = state.items[index];
    final wanted = !before.enabled;
    state = state.copyWith(
      items: _replace(state.items, type, (i) => i.copyWith(enabled: wanted)),
      pending: {...state.pending, type},
    );

    try {
      final confirmed = await _api.update({type: wanted});
      if (!mounted) return null;
      // Take the server's word for this type only: other rows may have been toggled meanwhile.
      final fromServer = confirmed.where((i) => i.type == type).firstOrNull;
      state = state.copyWith(
        items: fromServer == null
            ? state.items
            : _replace(state.items, type, (i) => i.copyWith(enabled: fromServer.enabled)),
        pending: {...state.pending}..remove(type),
      );
      return null;
    } on NotificationPreferencesFailure catch (e) {
      if (!mounted) return e.message;
      state = state.copyWith(
        items: _replace(state.items, type, (i) => i.copyWith(enabled: before.enabled)),
        pending: {...state.pending}..remove(type),
      );
      return e.message;
    }
  }

  static List<NotificationPreferenceDto> _replace(
    List<NotificationPreferenceDto> items,
    int type,
    NotificationPreferenceDto Function(NotificationPreferenceDto) change,
  ) => [for (final i in items) i.type == type ? change(i) : i];
}

final notificationPreferencesProvider =
    StateNotifierProvider.autoDispose<
      NotificationPreferencesNotifier,
      NotificationPreferencesState
    >((ref) => NotificationPreferencesNotifier(ref.watch(notificationPreferencesApiClientProvider)));
