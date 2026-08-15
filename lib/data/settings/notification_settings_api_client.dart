import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

/// The user's notification preferences, stored server-side so they follow them between devices.
///
/// ## What this does and does not buy, today
///
/// `GET`/`PUT /api/NotificationSettings` were live with no caller: the Impostazioni toggles wrote
/// only to `SharedPreferences`, so a technician who reinstalled the app or picked up a second
/// handset silently got the defaults back. Persisting them here fixes that.
///
/// It does **not** yet change which notifications arrive. `IUserNotificationSettingsService` is
/// injected into `NotificationSettingsController` and nowhere else in the backend — the columns
/// are written and read back, but no send path consults them. So the per-category flags are a
/// recorded preference waiting for the server to honour it, not a filter.
///
/// The one flag that does take effect is push, and it takes effect *on the device*: toggling it
/// registers or unregisters the FCM token (see `ImpostazioniNotifier._syncPushRegistration`).
/// That behaviour is unchanged and does not depend on this endpoint.
class NotificationSettingsDto {
  const NotificationSettingsDto({
    required this.enablePush,
    required this.ticketNotifications,
    required this.documentNotifications,
  });

  final bool enablePush;

  /// Ticket/intervento notifications — the app's "Interventi" toggle.
  final bool ticketNotifications;

  /// Document notifications — the app's "Rapportini" toggle.
  ///
  /// A rapportino is a document in the backend's vocabulary, not a worklog: `WorkLogNotifications`
  /// covers timbrature and approvals, which this app surfaces separately and does not offer a
  /// toggle for. Mapping rapportini onto the worklog flag would have silenced the wrong channel.
  final bool documentNotifications;

  factory NotificationSettingsDto.fromJson(Map<String, dynamic> json) => NotificationSettingsDto(
    // Defaulting to true matches the server's own get-or-create defaults. A field the server
    // stops sending must not read as "the user switched this off".
    enablePush: json['enablePush'] as bool? ?? true,
    ticketNotifications: json['ticketNotifications'] as bool? ?? true,
    documentNotifications: json['documentNotifications'] as bool? ?? true,
  );
}

class NotificationSettingsApiClient {
  NotificationSettingsApiClient(this._dio);

  final Dio _dio;

  /// GET /api/NotificationSettings
  Future<NotificationSettingsDto> fetch() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/NotificationSettings');
    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da NotificationSettings');
    return NotificationSettingsDto.fromJson(data);
  }

  /// PUT /api/NotificationSettings
  ///
  /// Every field on the request is nullable and the server only applies the ones present, so this
  /// sends exactly the three the app has toggles for and leaves the rest (email, SMS, in-app,
  /// schedule, licence, mention, worklog) at whatever the office web app set them to. Sending the
  /// full set with client-side defaults would silently reset preferences this app never showed.
  Future<void> update({bool? enablePush, bool? ticketNotifications, bool? documentNotifications}) {
    return _dio.put<dynamic>(
      '/api/NotificationSettings',
      data: {
        'enablePush': ?enablePush,
        'ticketNotifications': ?ticketNotifications,
        'documentNotifications': ?documentNotifications,
      },
    );
  }
}

final notificationSettingsApiClientProvider = Provider<NotificationSettingsApiClient>((ref) {
  return NotificationSettingsApiClient(ref.watch(dioProvider));
});
