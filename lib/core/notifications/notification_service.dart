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

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentToken;
  bool _initialized = false;

  /// The most recent access token passed to [registerDeviceToken], cached so
  /// that an FCM token refresh (which fires independently of auth state) can
  /// re-register without needing the caller to thread the token through.
  String? _lastAccessToken;

  /// Initialize FCM: request permission, get token, set up listeners.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request permission (iOS primarily; Android always grants).
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('FCM permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied — push notifications disabled');
      return;
    }

    // Get the initial token.
    _currentToken = await _messaging.getToken();
    debugPrint('FCM token: $_currentToken');

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

    // TODO: show a local in-app banner (Snack-bar or flutter_local_notifications)
    // For now, just log. The in-app notification list will be refreshed via
    // the notificheProvider polling mechanism.
    debugPrint('FCM foreground: ${notification.title} — ${notification.body}');
  }

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
    _pendingDeepLink = DeepLinkIntent(
      entityType: entityType,
      entityId: entityId,
    );

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
    return Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ));
  }
}

/// Deep-link intent parsed from a notification tap.
class DeepLinkIntent {
  const DeepLinkIntent({
    required this.entityType,
    required this.entityId,
  });

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
