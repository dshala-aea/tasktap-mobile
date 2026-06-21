import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/providers/auth_providers.dart';
import '../../presentation/screens/home/home_shell.dart';
import '../../presentation/screens/interventi/interventi_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../presentation/screens/oggi/oggi_screen.dart';
import '../../presentation/screens/profilo/profilo_screen.dart';
import '../../presentation/screens/rapportini/rapportini_screen.dart';

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
/// Auth guard: the `redirect` callback reads [authStateProvider] from [ref].
/// - AsyncLoading: return null (stay on current route while determining state).
/// - null user (unauthenticated): redirect to /login.
/// - non-null user (authenticated): redirect away from /login to /oggi.
///
/// This is the only place auth-to-route mapping lives, so adding PIN/QR auth
/// later requires no routing changes — only [IAuthRepository] changes.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.oggi,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final isOnLogin = state.matchedLocation == AppRoutes.login;

      return authAsync.when(
        // While Supabase is restoring the session, stay put.
        loading: () => null,
        // On error (e.g. offline with no cached session), go to login.
        error: (err, stack) => isOnLogin ? null : AppRoutes.login,
        data: (user) {
          final isAuthenticated = user != null;
          if (!isAuthenticated && !isOnLogin) return AppRoutes.login;
          if (isAuthenticated && isOnLogin) return AppRoutes.oggi;
          return null;
        },
      );
    },
    // Rebuild router on auth state changes so redirects are applied.
    refreshListenable: _AuthStateListenable(ref),
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

/// [Listenable] that notifies go_router whenever auth state changes.
///
/// go_router's [refreshListenable] re-evaluates the `redirect` callback on
/// every notification, which is what drives the login → home transition and
/// the forced /login redirect when the token refresh fails.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(WidgetRef ref) {
    ref.listenManual(authStateProvider, (prev, next) => notifyListeners());
  }
}
