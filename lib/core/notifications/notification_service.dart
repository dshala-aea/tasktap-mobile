import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../router/app_router.dart';

/// Background message handler — must be a top-level function, registered by main.dart via
/// `FirebaseMessaging.onBackgroundMessage` before `runApp`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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

  /// The last failure that affected push, or null if none has occurred.
  ///
  /// [isAvailable] alone cannot be told apart from "the app never tried": a missing APNs token, a
  /// Firebase config error and a bootstrap timeout all collapsed into the same `false`, and the
  /// reason went to a `debugPrint` that a TestFlight build never shows anyone. Impostazioni now
  /// surfaces this, so the failure is diagnosable from the handset.
  static String? lastError;

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

    // Warmed in the BACKGROUND, never awaited. On iOS `getToken()` waits for APNs registration to
    // complete, and when that registration is stuck — App ID without the Push capability, no APNs
    // key uploaded to the Firebase project, a profile that never matched the capability — the call
    // does not throw, it HANGS. `initialize()` is awaited by `initializePush` in main.dart under a
    // 5-second budget, so a hang did not merely lose a token: it timed out the whole bootstrap,
    // left `isAvailable` false and never wired the listeners below. The app then told the
    // technician "not available on this device" on a device where the only actual fault was that
    // APNs had not answered yet, and no push could arrive even if it had.
    //
    // Availability therefore means one thing only: Firebase started and the listeners are wired.
    // A token that arrives late is still registered — `onTokenRefresh` fires for it.
    unawaited(_warmToken());

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
    //
    // Guarded AND bounded, for the same reason as the token fetch above: a throw or a hang here
    // aborts `initialize()`, and the bootstrap turns that into "push unavailable" — for a
    // cold-start deep link that is merely absent. Nothing below depends on the result.
    try {
      final initialMessage = await _messaging.getInitialMessage().timeout(_coldStartBudget);
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      debugPrint('FCM getInitialMessage failed: $e');
    }

    // Foreground presentation is an Apple-only concern: on iOS a notification that arrives while
    // the app is open is delivered to `onMessage` but shown to nobody unless these options say
    // otherwise.
    //
    // The guard here used to be `Platform.isAndroid` — the one platform that has no implementation
    // of this method at all. Its only implementation in firebase_messaging is
    // `ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m`, and the
    // doc comment above it reads "Sets the presentation options for Apple notifications". So the
    // call went to the platform that cannot honour it and was skipped on the platform that is the
    // entire reason it exists.
    //
    // Bounded and non-fatal like the two steps above. It used to be left unguarded on the argument
    // that a throw would at least be recorded — but a throw here takes down `initialize()`, which
    // the bootstrap reports as "push unavailable", which is a wildly out-of-proportion price for
    // a foreground-presentation preference on a device that can receive notifications perfectly
    // well. A failure is still named (lastError, shown by Impostazioni) and it never disables
    // anything.
    if (Platform.isIOS) {
      try {
        await _messaging
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            )
            .timeout(_coldStartBudget);
      } catch (e) {
        lastError = 'Notifiche in primo piano: $e';
        debugPrint('setForegroundNotificationPresentationOptions failed: $e');
      }
    }
  }

  /// How long any single cold-start step inside [initialize] may take.
  ///
  /// Smaller than the bootstrap's own 5-second budget in main.dart on purpose: one slow APNs/plugin
  /// call must not consume the whole budget and leave the steps after it unrun.
  static const Duration _coldStartBudget = Duration(seconds: 2);

  /// Whether the OS already allows notifications, without asking.
  ///
  /// `authorized` and `provisional` both deliver; `notDetermined` means the dialog has never been
  /// shown, and `denied` means it has and the answer was no.
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  /// Raw OS authorization status, for a caller that needs to tell "never asked" apart from "said
  /// no" — [hasPermission] deliberately collapses both to `false` for its one existing caller
  /// ("can I skip the purpose sheet"), which is correct there and not enough for onboarding's own
  /// three-state UI.
  Future<AuthorizationStatus> authorizationStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
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
        status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    if (!granted) return false;

    // The token could not be fetched at startup if permission was not held then.
    _currentToken ??= await _tryGetToken();

    // ...and for the same reason the login-time registration ran with no token and returned
    // silently. Register now that there is one, or a freshly installed device that grants
    // permission AFTER login (onboarding, or the Impostazioni switch) stays unknown to the
    // backend until the next cold start: permission granted, nothing ever delivered. This is the
    // normal first-run path on iOS, where permission is never held at login; Android below 13
    // holds it from install, which is why it never showed there. `registerDeviceToken` is an
    // upsert on the backend, so a caller that registers again afterwards is harmless.
    final accessToken = _lastAccessToken;
    if (_currentToken != null && accessToken != null) {
      await registerDeviceToken(accessToken);
    }
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

    // Android shows nothing for a push that arrives while the app is open (the OS only draws a
    // notification for a backgrounded app), so the technician was never told at the moment it
    // happened. iOS presents it itself via setForegroundNotificationPresentationOptions above —
    // a banner here as well would show it twice.
    if (Platform.isAndroid) onForegroundBanner?.call(notification.title, notification.body);
  }

  /// Asks the UI to tell the user about a push that arrived while the app is open (Android only).
  /// Same wiring reason as [onForegroundMessage]: `main.dart` owns the navigator, not this service.
  void Function(String? title, String? body)? onForegroundBanner;

  /// Called when a push arrives while the app is in the foreground.
  ///
  /// A callback rather than a direct provider read: this service is a singleton created before
  /// the Riverpod container exists, so it cannot reach a provider itself. `main.dart` wires this
  /// to a refresh of the notification mirror.
  void Function()? onForegroundMessage;

  /// Handle notification tap — deep-link to the relevant screen.
  void _handleNotificationTap(RemoteMessage message) {
    final intent = intentFromPushData(message.data);
    if (intent == null) return;

    // Store the deep-link intent; the router will consume it.
    _pendingDeepLink = intent;
    // Tell main.dart there is something to drain; it decides whether the app is ready.
    onDeepLinkPending?.call();

    debugPrint('FCM deep-link: ${intent.entityType}/${intent.entityId}');
  }

  /// Called whenever a push tap stores a new pending deep-link (background or cold start).
  /// `main.dart` wires this to a [DeepLinkDrainer]; the intent stays in [consumePendingDeepLink]'s
  /// slot until the drainer finds the app ready, so a tap before auth is not lost.
  void Function()? onDeepLinkPending;

  /// Pending deep-link waiting for the app to be ready to navigate.
  DeepLinkIntent? _pendingDeepLink;

  /// Drop a parked deep-link (logout / user change) so it can never open for someone else.
  void clearPendingDeepLink() => _pendingDeepLink = null;

  /// Consume the pending deep-link (called by the router).
  DeepLinkIntent? consumePendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = null;
    return link;
  }

  /// Fetch the token once at startup, if the OS already allows notifications. Never throws and
  /// never blocks [initialize]; the result is only ever a cached token for the first registration.
  Future<void> _warmToken() async {
    try {
      if (!await hasPermission()) return;
      _currentToken = await _tryGetToken();
      debugPrint('FCM token: $_currentToken');

      // A token that arrives after the login-time registration has nobody to hand it to:
      // `registerDeviceToken` ran while this was still in flight. Register it here so a slow APNs
      // does not cost the device its registration until the next cold start. `onTokenRefresh`
      // covers the same case, but only if Firebase decides to emit it — this does not depend on it.
      final accessToken = _lastAccessToken;
      if (_currentToken != null && accessToken != null) {
        await registerDeviceToken(accessToken);
      }
    } catch (e) {
      lastError = 'Token: $e';
      debugPrint('FCM token warm-up failed: $e');
    }
  }

  /// How long a single token fetch may take before it is abandoned.
  ///
  /// Bounded rather than relied upon: `getToken()` on iOS resolves only once APNs has registered
  /// the device, and a misconfigured one never answers at all (see [initialize]). A caller that
  /// awaits this — [ensurePermission], after the technician granted — must not hold the settings
  /// sheet open indefinitely for a token that a later `onTokenRefresh` will deliver anyway.
  static const Duration tokenFetchTimeout = Duration(seconds: 15);

  /// Fetch the FCM token, or null when the platform will not issue one yet.
  ///
  /// On iOS `getToken()` throws `[firebase_messaging/apns-token-not-set]` whenever APNs registration
  /// has not completed. That is the permanent state when the App ID lacks the Push Notifications
  /// capability, when no APNs key is uploaded to the Firebase project, or when the build carries a
  /// `development` aps-environment under a distribution profile. Unguarded, a single such failure
  /// propagated straight out of [initialize] and disabled the whole subsystem — no permission
  /// prompt, no listeners, no deep links, and Impostazioni reporting notifications as unsupported
  /// on a handset that supports them perfectly well. A missing token is a missing token; it is not
  /// a reason to refuse to ask for permission.
  ///
  /// The same fault also HANGS instead of throwing on some iOS devices, which is why the fetch is
  /// bounded by [tokenFetchTimeout] as well as caught.
  Future<String?> _tryGetToken() => fetchToken(
    () => _messaging.getToken(),
    timeout: tokenFetchTimeout,
    recordError: (message) => lastError = message,
  );

  /// [fetch], bounded and recorded — the testable half of [_tryGetToken].
  ///
  /// Returns null on any failure (throw or timeout) and names it through [recordError], so
  /// Impostazioni can show a real cause instead of a generic "not available on this device".
  @visibleForTesting
  static Future<String?> fetchToken(
    Future<String?> Function() fetch, {
    Duration timeout = tokenFetchTimeout,
    void Function(String message)? recordError,
  }) async {
    try {
      return await fetch().timeout(timeout);
    } on TimeoutException {
      recordError?.call('Token: nessuna risposta da APNs entro $timeout');
      debugPrint('FCM getToken timed out after $timeout');
      return null;
    } catch (e) {
      recordError?.call('Token: $e');
      debugPrint('FCM getToken failed: $e');
      return null;
    }
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

/// Routes for notification types that carry no related entity, keyed by the
/// `NotificationTypeEnum` name. A new such type needs only an entry here; types with an entity
/// resolve through [DeepLinkIntent.resolveRoute] instead. `WorkLogCorrected` deliberately has no
/// entry: it is informational (see [kInformationalNotificationTypes]).
const Map<String, String> kNotificationTypeRoutes = {
  // "N ticket in ritardo" daily digest: no single ticket, so open the list. The list has no
  // overdue filter parameter today.
  'TicketOverdueDigest': AppRoutes.ticket,
};

/// Types that only inform: with no entity and no type route, their tap opens the notification's
/// own detail page (see [DeepLinkIntent.notificationId]) so the full text is readable.
const Set<String> kInformationalNotificationTypes = {'WorkLogCorrected'};

/// The push payload → deep-link decision, kept pure so it is testable without
/// Firebase.
///
/// The backend sends `notificationId`, `type` and, when there is one, the
/// `relatedEntityType`/`relatedEntityId` pair. An entity-less push therefore has
/// enough to open the notification's own page.
DeepLinkIntent? intentFromPushData(Map<String, dynamic> data) {
  if (data.isEmpty) return null;
  return DeepLinkIntent.fromNotification(
    // The backend puts the NotificationTypeEnum *name* in `type`.
    type: data['type'] as String?,
    entityType: data['relatedEntityType'] as String?,
    entityId: data['relatedEntityId'] as String?,
    notificationId: data['notificationId'] as String?,
  );
}

/// Deep-link intent parsed from a notification tap.
class DeepLinkIntent {
  const DeepLinkIntent({
    required this.entityType,
    required this.entityId,
    this.notificationId,
    this.notificationType,
  });

  final String entityType;
  final String entityId;

  /// Present when the intent resolves to the notification's own detail page rather than an
  /// entity: the page loads by id alone, so a push tap works without the list.
  final String? notificationId;

  /// The `NotificationTypeEnum` name, when the caller has it. `AbsenceRequestSubmitted` and
  /// `AbsenceRequestDecided` share the same entity type but belong on different screens; without
  /// this the intent cannot tell an approver's worklist from a requester's own history.
  final String? notificationType;

  /// The one place list taps and push taps decide what a notification opens.
  ///
  /// A submitted request goes to the approver's queue even without an id (the queue needs none).
  /// Otherwise a complete entity pair wins; otherwise a type-only route from
  /// [kNotificationTypeRoutes]; otherwise the notification's detail page when [notificationId] is
  /// present; otherwise null.
  static DeepLinkIntent? fromNotification({
    String? type,
    String? entityType,
    String? entityId,
    String? notificationId,
  }) {
    if (type == 'AbsenceRequestSubmitted') {
      // Smart working reuses the absence submission type; the entity pair is the only thing that
      // says which queue. A payload with neither falls back to the absence tab, which is the
      // screen's own default and still shows whatever is pending.
      final kind = entityType == 'SmartWorkingRequest'
          ? 'SmartWorkingRequest'
          : 'AbsenceRequest';
      return DeepLinkIntent(
        entityType: kind,
        entityId: entityId ?? '',
        notificationType: type,
      );
    }
    if (entityType != null &&
        entityType.isNotEmpty &&
        entityId != null &&
        entityId.isNotEmpty) {
      final entity = DeepLinkIntent(
        entityType: entityType,
        entityId: entityId,
        notificationType: type,
      );
      // An entity type with no mobile destination (Magazzino, User, …) must not
      // swallow the tap: fall through so the notification's own page can open.
      if (entity.resolveRoute() != null) return entity;
    }
    if (type != null && kNotificationTypeRoutes.containsKey(type)) {
      return DeepLinkIntent(entityType: type, entityId: '', notificationType: type);
    }
    if (notificationId != null && notificationId.isNotEmpty) {
      return DeepLinkIntent(
        entityType: '',
        entityId: '',
        notificationId: notificationId,
      );
    }
    return null;
  }

  /// Resolve the route path for this deep-link.
  String? resolveRoute() {
    if (entityType.isEmpty) {
      final id = notificationId;
      return id == null || id.isEmpty
          ? null
          : AppRoutes.notificaDettaglioPath(id);
    }
    return switch (entityType) {
      'Ticket' => AppRoutes.ticketDetailPath(entityId),
      'Schedule' => AppRoutes.calendario,
      // The report itself, not the list: the view screen loads by id and already surfaces a
      // rejected report's reason, so one destination serves Reviewed/Rejected/Cancelled alike.
      'Report' => AppRoutes.rapportiniView(entityId),
      'Cantiere' => AppRoutes.cantieriDetailPath(entityId),
      // A submitted request belongs to the approver's worklist; a decision belongs to the
      // requester's own history. Same entity type, different destination.
      'AbsenceRequest' => notificationType == 'AbsenceRequestSubmitted'
          ? AppRoutes.approvazioni(tab: 'assenze')
          : AppRoutes.altroFerie,
      'SmartWorkingRequest' => notificationType == 'AbsenceRequestSubmitted'
          ? AppRoutes.approvazioni(tab: 'smart-working')
          : AppRoutes.altroSmartWorking,
      // WorkLog, ProdottoAssistenza, User, Magazzino, Tenant, License: admin-side, no mobile screen.
      _ => kNotificationTypeRoutes[entityType],
    };
  }
}

/// Riverpod provider exposing the notification service singleton.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
