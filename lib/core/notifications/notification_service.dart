import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apns_diagnostics.dart';
import 'push_reporting.dart';
import 'push_resume_recheck.dart';

/// Background message handler — must be a top-level function, registered by main.dart via
/// `FirebaseMessaging.onBackgroundMessage` before `runApp`.
///
/// Nothing is reported to the crash reporter from here on purpose: the OS runs this in a fresh
/// isolate where nothing in `main()` has executed, so the Sentry SDK is not initialised and a
/// capture would go nowhere (or throw). A data-only push that the tray never shows therefore
/// leaves no trace anywhere — the foreground handler below reports the same condition instead.
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
    } catch (e, st) {
      debugPrint('FCM getInitialMessage failed: $e');
      reportPushFailure(PushStage.initialMessage, e, stackTrace: st, onceKey: 'initial-message');
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
      } catch (e, st) {
        lastError = 'Notifiche in primo piano: $e';
        debugPrint('setForegroundNotificationPresentationOptions failed: $e');
        reportPushFailure(
          PushStage.foregroundPresentation,
          e,
          stackTrace: st,
          onceKey: 'foreground-presentation',
        );
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

    // The permission outcome is a milestone, not noise: without it "no notifications arrived"
    // cannot be told apart from "the technician said no", and on iOS the dialog can only be shown
    // once, so the answer recorded here is permanent for that install.
    reportPushEvent(
      PushStage.permission,
      'requestPermission → ${status.name}',
      tags: {'push.authorization': status.name},
      onceKey: 'permission:${status.name}',
    );

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
    } else if (_currentToken != null) {
      // Token in hand, nobody signed in yet: registration is deferred to the auth listener, and
      // saying so stops this state being read as a failure later.
      reportPushEvent(
        PushStage.deviceRegistration,
        'token issued before sign-in; registration deferred',
        onceKey: 'deferred-until-login',
      );
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

    // Every one of these used to be a silent `return`, and each describes a handset that will
    // never receive a notification. "Registered nothing, said nothing" is exactly how the iOS
    // first-run fault survived several releases, so the reason is now reported once per app run.
    final skip = registrationSkipReason(
      token: token,
      accessToken: accessToken,
      apiBaseUrl: Env.apiBaseUrl,
    );
    if (skip != null) {
      reportPushEvent(
        PushStage.deviceRegistration,
        'skipped: $skip',
        // The authorization status is what separates "the technician said no" (nothing to fix)
        // from "granted, but APNs still has not issued a token" (everything to fix).
        tags: token == null
            ? {
                'push.authorization': await _authorizationTag(),
                'push.apns_token': await _apnsTokenState(),
                ...await _apnsDiagnostics.tags(),
              }
            : null,
        onceKey: 'skip:$skip',
      );
      return;
    }

    try {
      final dio = _createDio(accessToken);
      final response = await dio.post(
        '/api/devices',
        data: {
          'deviceToken': token,
          'platform': Platform.operatingSystem,
          'deviceName': await _getDeviceName(),
        },
      );
      debugPrint('FCM token registered with backend');
      reportPushEvent(
        PushStage.deviceRegistration,
        'registered with the backend (HTTP ${response.statusCode})',
        tags: {'fcm.token': maskToken(token), 'push.http_status': '${response.statusCode}'},
        onceKey: 'registered:${maskToken(token)}',
      );
    } on DioException catch (e, st) {
      // The backend's own words are usually the answer — a 400 naming the rejected field, a 401
      // from an expired access token — and Dio's message drops the body, so it is carried here.
      final status = e.response?.statusCode;
      final body = _bodySnippet(e.response?.data);
      reportPushFailure(
        PushStage.deviceRegistration,
        'POST /api/devices → HTTP ${status ?? 'no response'}${body.isEmpty ? '' : ': $body'}',
        stackTrace: st,
        tags: {'push.http_status': '${status ?? 'none'}', 'fcm.token': maskToken(token)},
        onceKey: 'register-failed:${status ?? 'no-response'}',
      );
    } catch (e, st) {
      reportPushFailure(
        PushStage.deviceRegistration,
        e,
        stackTrace: st,
        tags: {'fcm.token': maskToken(token)},
        onceKey: 'register-failed',
      );
    }
  }

  /// Why this device cannot be registered right now, or null when it can.
  ///
  /// Extracted from [registerDeviceToken] so the three conditions are one testable list rather than
  /// three consecutive silent returns. On iOS the first one is the normal state of a fresh install
  /// until the technician answers the permission dialog, which is why it is a reason to try again
  /// later and not an exception.
  @visibleForTesting
  static String? registrationSkipReason({
    required String? token,
    required String accessToken,
    required String apiBaseUrl,
  }) {
    if (token == null) return 'no FCM token yet';
    if (accessToken.isEmpty) return 'no access token';
    if (apiBaseUrl.isEmpty) return 'API_BASE_URL was not set at build time';
    return null;
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
    } catch (e, st) {
      debugPrint('Failed to unregister FCM token: $e');
      // A registration that outlives the sign-out is a push that reaches the wrong technician,
      // which is why this is an error event and not a breadcrumb.
      reportPushFailure(
        PushStage.deviceUnregistration,
        e,
        stackTrace: st,
        tags: {'fcm.token': maskToken(token)},
        onceKey: 'unregister-failed',
      );
    }
  }

  /// Foreground re-check, called by the home shell on `AppLifecycleState.resumed`. Registers the
  /// device when permission was granted outside the app (iOS Settings) or the APNs token only
  /// arrived after the first attempt. Never prompts, and the in-app switch wins. See
  /// [PushResumeRecheck].
  Future<void> onAppResumed() => (_resumeRecheck ??= PushResumeRecheck(
    accessToken: () => _lastAccessToken,
    pushPreferenceEnabled: () async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kPushPreferenceKey) ?? true;
    },
    permissionGranted: hasPermission,
    hasToken: () => _currentToken != null,
    fetchToken: () async {
      _currentToken ??= await _tryGetToken();
      return _currentToken != null;
    },
    register: registerDeviceToken,
  )).onResumed();

  PushResumeRecheck? _resumeRecheck;

  /// Handle a foreground notification — show an in-app banner or update state.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM foreground message: ${message.messageId}');

    pushBreadcrumb(
      'message received (notification: ${message.notification != null ? 'yes' : 'no'}, '
      'data keys: ${message.data.keys.join(',')})',
      stage: PushStage.foregroundMessage,
    );

    final notification = message.notification;
    if (notification == null) {
      // A data-only push is presented by nobody: the tray does not draw one, and this handler has
      // no text to show. It is worth an event because it is invisible from the outside — a payload
      // without a `notification` block looks exactly like "pushes do not arrive" on a handset that
      // is receiving every one of them. (The background handler cannot report this: it runs in an
      // isolate where Sentry is not initialised.)
      reportPushEvent(
        PushStage.foregroundMessage,
        'data-only push with no notification block: nothing can be displayed',
        tags: {'push.data_keys': message.data.keys.take(5).join(',')},
        onceKey: 'data-only-push',
      );
      return;
    }

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
      if (!await hasPermission()) {
        // The normal first run on iOS: permission has not been asked yet, so APNs has not issued
        // anything and there is nothing to warm. Reported as a breadcrumb only — it is the
        // expected state, not a fault, but it explains a session with no token at all.
        pushBreadcrumb('token warm-up skipped: notification permission not granted yet');
        return;
      }
      _currentToken = await _tryGetToken();
      debugPrint('FCM token: $_currentToken');

      if (_currentToken != null) {
        pushBreadcrumb('token issued ${maskToken(_currentToken)}', stage: PushStage.tokenFetch);
      }

      // A token that arrives after the login-time registration has nobody to hand it to:
      // `registerDeviceToken` ran while this was still in flight. Register it here so a slow APNs
      // does not cost the device its registration until the next cold start. `onTokenRefresh`
      // covers the same case, but only if Firebase decides to emit it — this does not depend on it.
      final accessToken = _lastAccessToken;
      if (_currentToken != null && accessToken != null) {
        await registerDeviceToken(accessToken);
      }
    } catch (e, st) {
      lastError = 'Token: $e';
      debugPrint('FCM token warm-up failed: $e');
      reportPushFailure(
        PushStage.tokenFetch,
        e,
        stackTrace: st,
        tags: {'push.apns_token': await _apnsTokenState(), ...await _apnsDiagnostics.tags()},
        onceKey: 'warm-token-failed',
      );
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
  ///
  /// The failure is reported here rather than inside [fetchToken] so that the report can carry the
  /// APNs state, which is the one field that tells the two Apple causes apart (see
  /// [_apnsTokenState]).
  Future<String?> _tryGetToken() => fetchAndReportToken(
    () => _messaging.getToken(),
    isIOS: Platform.isIOS,
    readApnsToken: () => _messaging.getAPNSToken(),
  );

  /// [fetchToken] plus the report of a token that is STILL missing afterwards — the testable
  /// half of [_tryGetToken].
  ///
  /// Nothing is reported while the APNs token is merely late: that is the normal first-run path
  /// (see [fetchToken]). A report here means the wait window ran out too, which is a real fault,
  /// and it carries the `push.apns_token` tag so the Apple-side and Firebase-side causes stay
  /// distinguishable.
  @visibleForTesting
  static Future<String?> fetchAndReportToken(
    Future<String?> Function() fetch, {
    required bool isIOS,
    required Future<String?> Function() readApnsToken,
    Duration timeout = tokenFetchTimeout,
    Duration apnsWait = apnsTokenWait,
    Duration apnsPollInterval = apnsTokenPollInterval,
    Future<void> Function(Duration) delay = _realDelay,
    ApnsDiagnostics? apnsDiagnostics,
  }) async {
    final token = await fetchToken(
      fetch,
      timeout: timeout,
      recordError: (message) => lastError = message,
      isIOS: isIOS,
      readApnsToken: readApnsToken,
      apnsWait: apnsWait,
      apnsPollInterval: apnsPollInterval,
      delay: delay,
      onApnsPending: () => pushBreadcrumb('apns token pending, waiting', stage: PushStage.tokenFetch),
      onApnsResolved: (waited) => pushBreadcrumb(
        'token issued after waiting ${waited.inMilliseconds / 1000}s for the APNs token',
        stage: PushStage.tokenFetch,
      ),
    );

    if (token == null) {
      reportPushFailure(
        PushStage.tokenFetch,
        // `lastError` already names the cause (throw or timeout); falling back covers the silent
        // "platform returned null" case, which on iOS also means no APNs token has arrived.
        lastError ?? 'platform issued no FCM token',
        tags: {
          'push.apns_token': await _apnsState(isIOS, readApnsToken),
          ...await (apnsDiagnostics ?? ApnsDiagnostics(isIOS: isIOS)).tags(),
        },
        onceKey: 'token-fetch-failed',
      );
    }
    return token;
  }

  /// Whether APNs has issued a token for this install.
  ///
  /// This is the field that decides who owns an iOS delivery failure, and neither `getToken()`
  /// nor the thrown error says it:
  ///
  ///   `absent`  — APNs never registered this handset. The App ID lacks the Push capability, the
  ///               provisioning profile was not regenerated after it, or the signed app carries a
  ///               `development` aps-environment under a distribution profile. Fixing it is an
  ///               Apple Developer portal / signing change; no code in this app can.
  ///   `present` — Apple is fine, and a failing `getToken()` points at the Firebase project
  ///               instead (no APNs authentication key uploaded, wrong Team ID).
  ///
  /// Bounded because this is read from inside failure paths, where a hung call would turn one
  /// diagnosable fault into a stuck bootstrap.
  Future<String> _apnsTokenState() =>
      _apnsState(Platform.isIOS, () => _messaging.getAPNSToken());

  static Future<String> _apnsState(bool isIOS, Future<String?> Function() read) async {
    if (!isIOS) return 'n/a';
    try {
      final apns = await read().timeout(const Duration(seconds: 2));
      return apns == null ? 'absent' : 'present';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Native APNs registration outcome (`push.apns_error`, `push.apns_registered`); see [ApnsDiagnostics].
  final ApnsDiagnostics _apnsDiagnostics = ApnsDiagnostics();

  /// The OS authorization status as a tag-safe string, or `unknown` if it cannot be read.
  Future<String> _authorizationTag() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus.name;
    } catch (_) {
      return 'unknown';
    }
  }

  /// A short, single-line rendering of a failed response body, for the error message.
  ///
  /// Long enough to carry an ASP.NET validation problem's field name, short enough not to ship a
  /// page of HTML into a crash report.
  static String _bodySnippet(Object? body) {
    if (body == null) return '';
    final text = body is String ? body : body.toString();
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length <= 200 ? collapsed : '${collapsed.substring(0, 200)}…';
  }

  /// How long to wait for the APNs device token before a missing FCM token is called a fault.
  ///
  /// Inside the [tokenFetchTimeout] bound (15 s) with room for the two `getToken()` calls around
  /// it, so the settings sheet never hangs longer than before.
  static const Duration apnsTokenWait = Duration(seconds: 8);

  /// How often the APNs token is polled while waiting.
  static const Duration apnsTokenPollInterval = Duration(milliseconds: 500);

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  /// Polls [read] until it yields a token or [timeout] is spent; null when it never does.
  ///
  /// One immediate read, then one per [interval]. [delay] is injectable so a test does not sleep.
  /// A read that throws counts as "not yet": this runs inside a failure path.
  @visibleForTesting
  static Future<String?> waitForApnsToken(
    Future<String?> Function() read, {
    Duration timeout = apnsTokenWait,
    Duration interval = apnsTokenPollInterval,
    Future<void> Function(Duration) delay = _realDelay,
  }) async {
    final polls = interval <= Duration.zero ? 0 : timeout.inMicroseconds ~/ interval.inMicroseconds;
    for (var i = 0; ; i++) {
      try {
        final token = await read();
        if (token != null) return token;
      } catch (_) {
        // Not yet.
      }
      if (i >= polls) return null;
      await delay(interval);
    }
  }

  static bool _isApnsNotSet(Object error) => error.toString().contains('apns-token-not-set');

  /// [fetch], bounded and recorded — the testable half of [_tryGetToken].
  ///
  /// Returns null on any failure (throw or timeout) and names it through [recordError], so
  /// Impostazioni can show a real cause instead of a generic "not available on this device".
  ///
  /// iOS only, and only when [readApnsToken] is given: a first answer of "no token" /
  /// `apns-token-not-set` is usually just the APNs device token still in flight (permission was
  /// granted a moment ago, so iOS has only now started registering). The fetch then waits for the
  /// APNs token ([apnsWait], polled every [apnsPollInterval]) and asks [fetch] ONCE more. A token
  /// that is still missing after that is the real fault and is returned as null. Other errors, and
  /// a hang (the misconfiguration case), are not waited on. The whole sequence stays inside
  /// [timeout].
  @visibleForTesting
  static Future<String?> fetchToken(
    Future<String?> Function() fetch, {
    Duration timeout = tokenFetchTimeout,
    void Function(String message)? recordError,
    bool? isIOS,
    Future<String?> Function()? readApnsToken,
    Duration apnsWait = apnsTokenWait,
    Duration apnsPollInterval = apnsTokenPollInterval,
    Future<void> Function(Duration) delay = _realDelay,
    void Function()? onApnsPending,
    void Function(Duration waited)? onApnsResolved,
  }) async {
    final waits = (isIOS ?? Platform.isIOS) && readApnsToken != null;

    Future<String?> run() async {
      String? firstError;
      try {
        final first = await fetch();
        if (first != null || !waits) return first;
      } catch (e) {
        if (!waits || !_isApnsNotSet(e)) rethrow;
        firstError = 'Token: $e';
        debugPrint('FCM getToken failed, waiting for the APNs token: $e');
      }

      onApnsPending?.call();
      var polls = 0;
      final apns = await waitForApnsToken(
        () {
          polls++;
          return readApnsToken();
        },
        timeout: apnsWait,
        interval: apnsPollInterval,
        delay: delay,
      );
      if (apns == null) {
        if (firstError != null) recordError?.call(firstError);
        return null;
      }
      onApnsResolved?.call(apnsPollInterval * (polls - 1));
      return fetch();
    }

    try {
      return await run().timeout(timeout);
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
