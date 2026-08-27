import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'core/location/location_service.dart';
import 'core/security/biometric_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/env.dart';
import 'core/crash_reporting/crash_reporter.dart';
import 'core/crash_reporting/sentry_crash_reporter.dart';
import 'core/notifications/notification_service.dart';
import 'features/altro/notifiche_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/suspended_banner.dart';
import 'presentation/providers/auth_providers.dart';
import 'features/altro/impostazioni_provider.dart';

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
  const firebaseEnabled = String.fromEnvironment('FIREBASE_ENABLED', defaultValue: 'true');
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

  // ── Date formatting ─────────────────────────────────────────────────────────
  //
  // Every screen that shows a date builds it with DateFormat(..., 'it'), and intl ships no locale
  // data until it is asked to load some. Without this the first such widget throws
  //
  //     LocaleDataException: Locale data has not been initialized,
  //     call initializeDateFormatting(<locale>).
  //
  // which is an exception during build, so the screen is replaced by an error box rather than
  // showing a wrong date. Twenty-five call sites across the app depend on this one line.
  //
  // Intl.defaultLocale is set alongside it so the handful of DateFormat calls that pass no locale
  // format the same way as the ones that do, instead of falling back to en_US.
  await initializeDateFormatting('it', null);
  Intl.defaultLocale = 'it';

  // Auth is Zitadel OIDC (see ZitadelAuthRepository) — no SDK init needed here;
  // the session is restored from the stored refresh token by the repository.
  // FCM device-token registration is driven off the Riverpod auth state inside
  // TaskTapApp (a listener needs the ProviderScope, created below).

  runApp(
    ProviderScope(
      overrides: [
        // Bind the core GPS gate to the Impostazioni setting. Declared in core so
        // core/location does not import a feature; bound here, once, so no call site has to
        // remember the setting exists — which is exactly how it ended up controlling nothing.
        gpsPreferenceProvider.overrideWith(
          (ref) => ref.watch(impostazioniProvider.select((s) => s.geoLocazione)),
        ),
      ],
      child: const TaskTapApp(),
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

    // A push arriving in the foreground is the moment we know there is something new; pull it
    // into the local mirror so the badge and the list update without waiting for the technician
    // to open the Notifiche screen. Nothing polled before this, despite a comment claiming it did.
    if (NotificationService.isAvailable) {
      NotificationService.instance.onForegroundMessage = () =>
          ref.read(notificheProvider.notifier).refresh();
    }

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

    // Impostazioni → "Tema scuro". The switch existed, was persisted to SharedPreferences, and
    // nothing read it — so it has been reporting a preference the app never honoured. It drives
    // themeMode now. Explicit light/dark rather than ThemeMode.system: the setting is a choice the
    // technician made, and silently overriding it with the phone's would be the same defect again.
    final darkTheme = ref.watch(impostazioniProvider.select((s) => s.temaScuro));

    final biometricLock = ref.watch(impostazioniProvider.select((s) => s.autenticazioneBiometrica));

    return MaterialApp.router(
      title: 'TaskTap',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: darkTheme ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
      // Inside MaterialApp via `builder`, not around it: the lock needs the theme and the
      // Directionality, and wrapping outside would also cover the navigator the router owns.
      //
      // The suspended banner lives here rather than in HomeShell so it covers every route the
      // router owns — including pushed forms like "Nuovo ticket" — not just the 5 tab branches.
      // A technician who is mid-wizard on a suspended tenant must see the same warning a
      // dashboard visit would have shown, not discover the block only when the final submit 403s.
      builder: (context, child) => BiometricLock(
        enabled: biometricLock,
        // Themed backdrop, not transparent: SuspendedBanner now paints its own safe area (see
        // its own doc comment) and returns SizedBox.shrink() when the tenant isn't suspended —
        // with nothing behind that empty state, the status-bar strip would fall back to
        // whatever the platform default is rather than matching the page underneath.
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              const SuspendedBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}
