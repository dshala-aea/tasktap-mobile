import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
/// - [buildRouter] (go_router with bottom-nav shell)
class TaskTapApp extends StatefulWidget {
  const TaskTapApp({super.key});

  @override
  State<TaskTapApp> createState() => _TaskTapAppState();
}

class _TaskTapAppState extends State<TaskTapApp> {
  late final _router = buildRouter();

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
