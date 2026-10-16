import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/problem_details.dart';

/// The per-type notification switches: one row per notification type the user may mute.
///
/// This is the fine-grained sibling of [NotificationSettingsApiClient] (`/api/NotificationSettings`,
/// the coarse category and channel flags). The two are independent routes on the server and this
/// client touches only `/api/notifications/preferences`.
///
/// ## Contract (backend PR tasktap-api#102)
///
/// - `GET  /api/notifications/preferences` (`sistema.notification.read`) →
///   `{ "items": [ { "type": 0, "key": "TicketAssigned", "enabled": true, "default": true } ] }`.
///   Only user-controllable types are listed, in enum order. The locked types (seat-limit and
///   licence alerts) are never listed, so the app cannot offer a switch the server would refuse.
/// - `PUT  /api/notifications/preferences` (`sistema.notification.write`) with
///   `{ "items": [ { "type": 25, "enabled": false } ] }` → 200 with the same shape as GET, the
///   full effective list. 400 codes `notification_type_unknown` / `notification_type_locked`; an
///   empty `items` is a 400 too.
///
/// `type` is the enum ORDINAL on the wire and `key` is the enum name. The server will add types
/// later, so parsing keeps whatever it is sent and the screen falls back to [key] for a label — an
/// unknown ordinal must render, never throw.
///
/// ## Online-only
///
/// There is no local mirror: a stale switch that reports a state the server does not hold is the
/// same defect as a settings control wired to nothing. Failures are surfaced as
/// [NotificationPreferencesFailure] carrying an Italian sentence.
class NotificationPreferenceDto {
  const NotificationPreferenceDto({
    required this.type,
    required this.key,
    required this.enabled,
    required this.defaultEnabled,
  });

  /// Enum ordinal — what the PUT body must carry.
  final int type;

  /// Enum name (`TicketAssigned`). The label fallback for an ordinal this build does not know.
  final String key;

  final bool enabled;

  /// What the server applies when the user has expressed no preference. Not used to draw the
  /// switch (that is [enabled]); kept so a later "ripristina" affordance has it.
  final bool defaultEnabled;

  NotificationPreferenceDto copyWith({bool? enabled}) => NotificationPreferenceDto(
    type: type,
    key: key,
    enabled: enabled ?? this.enabled,
    defaultEnabled: defaultEnabled,
  );

  /// Returns null for a row without a usable ordinal: it could not be sent back, so listing it
  /// would offer a switch that cannot work. Everything else is tolerated.
  static NotificationPreferenceDto? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! num) return null;
    final key = raw['key'];
    final enabled = raw['enabled'];
    final fallback = enabled is bool ? enabled : true;
    return NotificationPreferenceDto(
      type: type.toInt(),
      key: key is String && key.isNotEmpty ? key : 'Type${type.toInt()}',
      // Defaulting to on matches the server's "no row = delivered" rule: a field the server stops
      // sending must not read as "the user switched this off".
      enabled: fallback,
      defaultEnabled: raw['default'] is bool ? raw['default'] as bool : true,
    );
  }

  static List<NotificationPreferenceDto> parseList(Object? body) {
    final items = body is Map ? body['items'] : null;
    if (items is! List) return const [];
    return [
      for (final raw in items)
        if (tryParse(raw) case final dto?) dto,
    ];
  }
}

/// A failed read or write, with the sentence to show.
class NotificationPreferencesFailure implements Exception {
  const NotificationPreferencesFailure(this.message, {this.offline = false});

  final String message;

  /// The request never reached the server (no connection / timeout).
  final bool offline;

  @override
  String toString() => message;
}

class NotificationPreferencesApiClient {
  NotificationPreferencesApiClient(this._dio);

  final Dio _dio;

  /// GET /api/notifications/preferences
  Future<List<NotificationPreferenceDto>> fetch() async {
    final response = await _run(
      () => _dio.get<Map<String, dynamic>>('/api/notifications/preferences'),
      fallback: 'Impossibile caricare le preferenze di notifica.',
    );
    return NotificationPreferenceDto.parseList(response.data);
  }

  /// PUT /api/notifications/preferences — sends only the types in [changes] (ordinal → enabled)
  /// and returns the full effective list the server answers with.
  Future<List<NotificationPreferenceDto>> update(Map<int, bool> changes) async {
    final response = await _run(
      () => _dio.put<Map<String, dynamic>>(
        '/api/notifications/preferences',
        data: {
          'items': [
            for (final entry in changes.entries) {'type': entry.key, 'enabled': entry.value},
          ],
        },
      ),
      fallback: 'Impossibile salvare la preferenza.',
    );
    return NotificationPreferenceDto.parseList(response.data);
  }

  Future<Response<T>> _run<T>(
    Future<Response<T>> Function() call, {
    required String fallback,
  }) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _failureFor(e, fallback);
    }
  }

  static NotificationPreferencesFailure _failureFor(DioException e, String fallback) {
    final status = ProblemDetails.statusOf(e);
    if (status == null) {
      return const NotificationPreferencesFailure(
        'Nessuna connessione: riprova quando torni online.',
        offline: true,
      );
    }
    if (status == 403) {
      return const NotificationPreferencesFailure(
        'Non hai il permesso di gestire le preferenze di notifica.',
      );
    }
    if (status == 400) {
      switch (ProblemDetails.bodyOf(e)?['code']) {
        case 'notification_type_locked':
          return const NotificationPreferencesFailure(
            'Questa notifica è obbligatoria e non può essere disattivata.',
          );
        case 'notification_type_unknown':
          return const NotificationPreferencesFailure(
            'Questo tipo di notifica non è più disponibile. Aggiorna la schermata.',
          );
      }
    }
    return NotificationPreferencesFailure(fallback);
  }
}

final notificationPreferencesApiClientProvider = Provider<NotificationPreferencesApiClient>((ref) {
  return NotificationPreferencesApiClient(ref.watch(dioProvider));
});
