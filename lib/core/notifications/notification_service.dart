import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../router/app_router.dart';

/// Background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled by the OS notification tray.
  // No in-app processing needed here.
  debugPrint('FCM background message: ${message.messageId}');
}

/// Manages FCM push notification lifecycle:
/// - Initializes Firebase Messaging
/// - Obtains and registers the device token with the backend
/// - Handles foreground messages
/// - Handles notification taps (deep-linking)
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Set to `true` by `runTaskTapApp()` in main.dart only after
  /// `Firebase.initializeApp()` *actually succeeds*. Firebase init is an
  /// explicitly supported failure path (missing config, no Play Services,
  /// offline at cold start — main.dart degrades gracefully via try/catch),
  /// so the FIREBASE_ENABLED dart-define alone doesn't tell you it's safe
  /// to touch [instance].
  ///
  /// [instance]'s constructor eagerly reads `FirebaseMessaging.instance`
  /// (below), which throws `[core/no-app]` the moment it's first accessed
  /// if Firebase was never initialized — including in widget tests, which
  /// never call `runTaskTapApp()` at all. **Every** call site that touches
  /// [instance] must check this flag first; there is no other guard.
  static bool isAvailable = false;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentToken;
  bool _initialized = false;

  /// The most recent access token passed to [registerDeviceToken], cached so
  /// that an FCM token refresh (which fires independently of auth state) can
  /// re-register without needing the caller to thread the token through.
  String? _lastAccessToken;

  /// Wire up FCM without asking for anything.
  ///
  /// This used to call `requestPermission` as its first act, and it is called from
  /// `runTaskTapApp()` — so the OS notification dialog was the first thing a technician saw, before
  /// the app had drawn a single screen and with nothing on it saying what would be sent or why.
  /// That is a transparency failure and, in practice, the surest way to be denied: an unexplained
  /// prompt is the one people refuse, and on iOS it cannot be shown a second time.
  ///
  /// The ask now lives behind the "Notifiche push" setting, where [ensurePermission] is called
  /// after a sheet has stated the purpose. Everything here is listeners and token plumbing, none of
  /// which prompts; the token is fetched only if permission is *already* held from a previous run.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (await hasPermission()) {
      _currentToken = await _messaging.getToken();
      debugPrint('FCM token: $_currentToken');
    }

    // Listen for token refreshes.
    _messaging.onTokenRefresh.listen((newToken) {
      _currentToken = newToken;
      debugPrint('FCM token refreshed: $newToken');
      final accessToken = _lastAccessToken;
      if (accessToken != null) {
        registerDeviceToken(accessToken);
      }
    });

    // Handle foreground messages.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app was in background/terminated.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was opened from a notification (terminated state).
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // Configure Android notification channel.
    if (Platform.isAndroid) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Whether the OS already allows notifications, without asking.
  ///
  /// `authorized` and `provisional` both deliver; `notDetermined` means the dialog has never been
  /// shown, and `denied` means it has and the answer was no.
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
  }

  /// Asks the OS, once the caller has already explained why.
  ///
  /// Returns whether notifications can now be delivered. **Do not call this without showing
  /// `askPermissionPurpose` first** — that is the whole point of it being separate from
  /// [initialize].
  Future<bool> ensurePermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final status = settings.authorizationStatus;
    debugPrint('FCM permission: $status');

    final granted =
        status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
    if (!granted) return false;

    // The token could not be fetched at startup if permission was not held then.
    _currentToken ??= await _messaging.getToken();
    return true;
  }

  /// Register the current FCM token with the TaskTap backend.
  ///
  /// Called after login and on token refresh. Safe to call multiple times
  /// — the backend upserts by (userId, deviceToken).
  Future<void> registerDeviceToken(String accessToken) async {
    _lastAccessToken = accessToken;
    final token = _currentToken;
    if (token == null || accessToken.isEmpty || Env.apiBaseUrl.isEmpty) return;

    try {
      final dio = _createDio(accessToken);
      await dio.post(
        '/api/devices',
        data: {
          'deviceToken': token,
          'platform': Platform.operatingSystem,
          'deviceName': await _getDeviceName(),
        },
      );
      debugPrint('FCM token registered with backend');
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }
  }

  /// Unregister the current device token on logout.
  Future<void> unregisterDeviceToken(String accessToken) async {
    final token = _currentToken;
    if (token == null || accessToken.isEmpty || Env.apiBaseUrl.isEmpty) return;

    try {
      final dio = _createDio(accessToken);
      // List devices to find our registration, then delete it.
      final response = await dio.get('/api/devices');
      final devices = (response.data as List).cast<Map<String, dynamic>>();
      for (final device in devices) {
        if (device['deviceToken'] == token) {
          await dio.delete('/api/devices/${device['id']}');
          debugPrint('FCM token unregistered from backend');
          break;
        }
      }
    } catch (e) {
      debugPrint('Failed to unregister FCM token: $e');
    }
  }

  /// Handle a foreground notification — show an in-app banner or update state.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM foreground message: ${message.messageId}');

    final notification = message.notification;
    if (notification == null) return;

    debugPrint('FCM foreground: ${notification.title} — ${notification.body}');

    // Pull the new notification into the local mirror so the badge and the list reflect it now.
    //
    // The comment that stood here claimed "the in-app notification list will be refreshed via the
    // notificheProvider polling mechanism". No such polling exists — the list refreshed only when
    // somebody opened the Notifiche screen, so a technician who never opened it saw a stale or
    // zero badge no matter what had been delivered. A push arriving is exactly the moment we know
    // there is something new to fetch.
    onForegroundMessage?.call();
  }

  /// Called when a push arrives while the app is in the foreground.
  ///
  /// A callback rather than a direct provider read: this service is a singleton created before
  /// the Riverpod container exists, so it cannot reach a provider itself. `main.dart` wires this
  /// to a refresh of the notification mirror.
  void Function()? onForegroundMessage;

  /// Handle notification tap — deep-link to the relevant screen.
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;

    final entityType = data['relatedEntityType'] as String?;
    final entityId = data['relatedEntityId'] as String?;

    if (entityType == null || entityId == null || entityId.isEmpty) return;

    // Navigate based on entity type.
    // This uses a global navigator key or a routing callback.
    // For now, store the deep-link intent; the router will consume it.
    _pendingDeepLink = DeepLinkIntent(entityType: entityType, entityId: entityId);

    debugPrint('FCM deep-link: $entityType/$entityId');
  }

  /// Pending deep-link to be consumed by the router on next build.
  DeepLinkIntent? _pendingDeepLink;

  /// Consume the pending deep-link (called by the router).
  DeepLinkIntent? consumePendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = null;
    return link;
  }

  Future<String> _getDeviceName() async {
    // Best-effort device name. Platform locale isn't always available.
    try {
      final platform = Platform.operatingSystemVersion;
      return '${Platform.operatingSystem} $platform';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  Dio _createDio(String accessToken) {
    return Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }
}

/// Deep-link intent parsed from a notification tap.
class DeepLinkIntent {
  const DeepLinkIntent({required this.entityType, required this.entityId});

  final String entityType;
  final String entityId;

  /// Resolve the route path for this deep-link.
  String? resolveRoute() {
    return switch (entityType) {
      'Ticket' => AppRoutes.ticketDetailPath(entityId),
      'Schedule' => AppRoutes.calendario,
      'Report' => AppRoutes.altroRapportini,
      'Location' => AppRoutes.altroClienti,
      _ => null,
    };
  }
}

/// Riverpod provider exposing the notification service singleton.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
