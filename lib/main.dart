import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase.
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
