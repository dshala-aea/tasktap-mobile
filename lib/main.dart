import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/crash_reporting/crash_reporter.dart';
import 'core/crash_reporting/sentry_crash_reporter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

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
  // ── Supabase ──────────────────────────────────────────────────────────────
  //
  // Credentials come from --dart-define at build time (see lib/core/config/env.dart).
  // supabase_flutter persists the session automatically using SharedPreferences
  // and, when available, flutter_secure_storage so the user stays signed in
  // across app restarts and can use the app offline (cached JWT).
  //
  // authFlowType: pkce is the recommended secure flow for mobile apps.
  if (Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // Keep the session alive in the background.
        autoRefreshToken: true,
      ),
    );
  }

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
    return MaterialApp.router(
      title: 'TaskTap',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
