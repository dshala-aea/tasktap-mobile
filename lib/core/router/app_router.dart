import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/home/home_shell.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../presentation/screens/oggi/oggi_screen.dart';
import '../../presentation/screens/interventi/interventi_screen.dart';
import '../../presentation/screens/rapportini/rapportini_screen.dart';
import '../../presentation/screens/profilo/profilo_screen.dart';

/// Route path constants.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String oggi = '/oggi';
  static const String interventi = '/interventi';
  static const String rapportini = '/rapportini';
  static const String profilo = '/profilo';
}

/// Global navigator key — use for imperative navigation outside widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds and returns the [GoRouter] for the TaskTap app.
///
/// Auth guarding is a seam for M2 — for now all routes are accessible.
GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.oggi,
    debugLogDiagnostics: false,
    routes: [
      // ── Auth ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),

      // ── Main Shell (bottom nav) ──────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'oggi'),
            routes: [
              GoRoute(
                path: AppRoutes.oggi,
                builder: (context, state) => const OggiScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey:
                GlobalKey<NavigatorState>(debugLabel: 'interventi'),
            routes: [
              GoRoute(
                path: AppRoutes.interventi,
                builder: (context, state) => const InterventiScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey:
                GlobalKey<NavigatorState>(debugLabel: 'rapportini'),
            routes: [
              GoRoute(
                path: AppRoutes.rapportini,
                builder: (context, state) => const RapportiniScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'profilo'),
            routes: [
              GoRoute(
                path: AppRoutes.profilo,
                builder: (context, state) => const ProfiloScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
