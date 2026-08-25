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
/// It DOES change which notifications arrive: `NotificationService.CreateNotificationAsync`
/// reads `UserNotificationSettings` directly (not through `IUserNotificationSettingsService`,
/// which only backs `NotificationSettingsController`'s own read/write) and consults the matching
/// per-category flag before delivering — every category flag below included. A prior version of
/// this comment claimed otherwise for `ticketNotifications`/`documentNotifications`; that was
/// wrong, not merely stale — verified against `NotificationService.CanDeliverNotification`
/// directly before correcting it.
///
/// Delivery is a channel × category gate: a category flag decides whether the notification is
/// created for delivery at all (`CanDeliverNotification`), and each channel flag independently
/// decides whether *that* channel fires for it (`NotificationService.CreateNotificationAsync`
/// `:94,103,133`) — so e.g. a technician can keep "Interventi" on but turn off "Email" and still
/// get it as push/in-app.
///
/// Push additionally takes effect *on the device*: toggling it registers or unregisters the FCM
/// token (see `ImpostazioniNotifier._syncPushRegistration`), on top of the server-side gate above.
///
/// `enableSMS` is deliberately excluded from this DTO — there is no SMS provider wired anywhere in
/// the backend's send path, so a toggle for it would control a channel that cannot deliver
/// anything. Not an oversight; see the entitlement/notifications audit.
class NotificationSettingsDto {
  const NotificationSettingsDto({
    required this.enableInApp,
    required this.enablePush,
    required this.enableEmail,
    required this.ticketNotifications,
    required this.scheduleNotifications,
    required this.licenseNotifications,
    required this.workLogNotifications,
    required this.documentNotifications,
    required this.mentionNotifications,
  });

  /// In-app delivery — the SignalR-pushed entry into the technician's own Notifiche list
  /// (independent of push/email; "Notifiche in app" in the app's vocabulary).
  final bool enableInApp;

  final bool enablePush;

  final bool enableEmail;

  /// Ticket/intervento notifications — the app's "Interventi" toggle.
  final bool ticketNotifications;

  /// Schedule notifications — the app's "Pianificazione" toggle (reminders and start-of-shift
  /// alerts for entries on the Calendario).
  final bool scheduleNotifications;

  /// Licence/subscription notifications — the app's "Licenza e abbonamento" toggle.
  final bool licenseNotifications;

  /// Work-log notifications — the app's "Ore e presenze" toggle. This is `WorkLogSubmitted`
  /// (submission/approval of hours), distinct from `documentNotifications` below.
  final bool workLogNotifications;

  /// Document notifications — the app's "Rapportini" toggle.
  ///
  /// A rapportino is a document in the backend's vocabulary, not a worklog: `WorkLogNotifications`
  /// covers timbrature and approvals, which this app surfaces separately via
  /// [workLogNotifications]. Mapping rapportini onto the worklog flag would have silenced the
  /// wrong channel.
  final bool documentNotifications;

  /// Mention notifications — the app's "Menzioni" toggle (comments/notes that @-mention the user).
  final bool mentionNotifications;

  factory NotificationSettingsDto.fromJson(Map<String, dynamic> json) => NotificationSettingsDto(
    // Defaulting to true matches the server's own get-or-create defaults. A field the server
    // stops sending must not read as "the user switched this off".
    enableInApp: json['enableInApp'] as bool? ?? true,
    enablePush: json['enablePush'] as bool? ?? true,
    enableEmail: json['enableEmail'] as bool? ?? true,
    ticketNotifications: json['ticketNotifications'] as bool? ?? true,
    scheduleNotifications: json['scheduleNotifications'] as bool? ?? true,
    licenseNotifications: json['licenseNotifications'] as bool? ?? true,
    workLogNotifications: json['workLogNotifications'] as bool? ?? true,
    documentNotifications: json['documentNotifications'] as bool? ?? true,
    mentionNotifications: json['mentionNotifications'] as bool? ?? true,
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
  /// sends exactly the nine the app has toggles for (everything except `enableSMS`, which has no
  /// UI here — see the class doc on [NotificationSettingsDto]) and leaves any other server field
  /// untouched. Sending the full set with client-side defaults would silently reset preferences
  /// this app never showed.
  Future<void> update({
    bool? enableInApp,
    bool? enablePush,
    bool? enableEmail,
    bool? ticketNotifications,
    bool? scheduleNotifications,
    bool? licenseNotifications,
    bool? workLogNotifications,
    bool? documentNotifications,
    bool? mentionNotifications,
  }) {
    return _dio.put<dynamic>(
      '/api/NotificationSettings',
      data: {
        'enableInApp': ?enableInApp,
        'enablePush': ?enablePush,
        'enableEmail': ?enableEmail,
        'ticketNotifications': ?ticketNotifications,
        'scheduleNotifications': ?scheduleNotifications,
        'licenseNotifications': ?licenseNotifications,
        'workLogNotifications': ?workLogNotifications,
        'documentNotifications': ?documentNotifications,
        'mentionNotifications': ?mentionNotifications,
      },
    );
  }
}

final notificationSettingsApiClientProvider = Provider<NotificationSettingsApiClient>((ref) {
  return NotificationSettingsApiClient(ref.watch(dioProvider));
});
