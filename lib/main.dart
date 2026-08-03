import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/env.dart';
import 'core/crash_reporting/crash_reporter.dart';
import 'core/crash_reporting/sentry_crash_reporter.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/auth_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Crash reporting (Sentry) ────────────────────────────────────────────────
  //
  // Sentry is only initialised when SENTRY_DSN is provided via --dart-define.
  // Without the DSN the app uses a no-op CrashReporter so that unit tests and
  // local development runs work without any Sentry account.
  //
  // Build / release example:
  //   flutter build apk
  //     --dart-define=SENTRY_DSN=https://...@sentry.io/...
  //     --dart-define=SUPABASE_URL=...
  //     --dart-define=SUPABASE_ANON_KEY=...
  //     --dart-define=API_BASE_URL=...
  if (Env.sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = Env.sentryDsn;
        // Only send traces in release mode to keep dev logs clean.
        options.tracesSampleRate = 0.2;
        // Attach stack traces to all captured messages.
        options.attachStacktrace = true;
      },
      // appRunner wraps the whole app so Sentry can catch Flutter framework
      // errors (FlutterError.onError) and async zone errors automatically.
      appRunner: () => runTaskTapApp(),
    );
    // Register the Sentry implementation as the active CrashReporter.
    CrashReporter.setInstance(const SentryCrashReporter());
  } else {
    // No DSN — use the default no-op CrashReporter; still start the app.
    await runTaskTapApp();
  }
}

/// Initialise Supabase and launch the Flutter widget tree.
///
/// Extracted so it can be called both from inside the Sentry [appRunner]
/// callback and from the no-DSN code path.
Future<void> runTaskTapApp() async {
  // ── Firebase ────────────────────────────────────────────────────────────────
  //
  // Firebase is initialised FIRST so that FirebaseMessaging can be used
  // immediately after Supabase auth completes. The platform-specific config
  // files (google-services.json / GoogleService-Info.plist) must be present.
  // Firebase is optional: when the dart-define FIREBASE_ENABLED is absent or
  // "false", push notifications are silently disabled.
  const firebaseEnabled = String.fromEnvironment(
    'FIREBASE_ENABLED',
    defaultValue: 'true',
  );
  if (firebaseEnabled == 'true') {
    try {
      await Firebase.initializeApp();
      await NotificationService.instance.initialize();
      NotificationService.isAvailable = true;
    } catch (e) {
      // Firebase is optional — app still works without push notifications.
      debugPrint('Firebase init failed (push disabled): $e');
    }
  }

  // Auth is Zitadel OIDC (see ZitadelAuthRepository) — no SDK init needed here;
  // the session is restored from the stored refresh token by the repository.
  // FCM device-token registration is driven off the Riverpod auth state inside
  // TaskTapApp (a listener needs the ProviderScope, created below).

  runApp(
    const ProviderScope(
      child: TaskTapApp(),
    ),
  );
}

/// Root application widget.
///
/// Wires together:
/// - [ProviderScope] (Riverpod DI root — wraps this widget in main)
/// - [buildAppTheme] (TaskTap brand design system)
/// - [buildRouter] (go_router with auth guard + bottom-nav shell)
class TaskTapApp extends ConsumerStatefulWidget {
  const TaskTapApp({super.key});

  @override
  ConsumerState<TaskTapApp> createState() => _TaskTapAppState();
}

class _TaskTapAppState extends ConsumerState<TaskTapApp> {
  late final _router = buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    // Register the FCM device token whenever a user becomes authenticated
    // (replaces the old Supabase auth-state listener). Guarded on
    // `NotificationService.isAvailable` — see its doc comment for why the
    // FIREBASE_ENABLED dart-define alone isn't a safe enough check.
    ref.listen(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (NotificationService.isAvailable && user != null) {
        NotificationService.instance.registerDeviceToken(user.accessToken);
      }
    });

    // Check for pending deep-links from notification taps.
    if (NotificationService.isAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final deepLink = NotificationService.instance.consumePendingDeepLink();
        if (deepLink != null) {
          final route = deepLink.resolveRoute();
          if (route != null) {
            _router.go(route);
          }
        }
      });
    }

    return MaterialApp.router(
      title: 'TaskTap',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
