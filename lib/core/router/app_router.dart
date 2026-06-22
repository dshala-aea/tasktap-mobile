import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/screens/home/home_shell.dart';
import '../../features/ticket/ticket_detail_screen.dart';
import '../../features/ticket/ticket_list_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../presentation/screens/placeholder/altro_screen.dart';
import '../../presentation/screens/placeholder/calendario_placeholder_screen.dart';
import '../../features/timbra/timbra_screen.dart';
import '../../presentation/screens/profilo/profilo_screen.dart';
import '../../features/rapportino/rapportino_form_screen.dart';
import '../../presentation/screens/rapportini/rapportini_screen.dart';

/// Route path constants.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String ticket = '/ticket';
  static const String ticketDetail = '/ticket/:id';

  /// Build the detail path for a given ticket id.
  static String ticketDetailPath(String id) => '/ticket/$id';

  static const String timbra = '/timbra';
  static const String calendario = '/calendario';
  static const String altro = '/altro';
  static const String altroProfilo = '/altro/profilo';
  static const String altroRapportini = '/altro/rapportini';

  /// Build the editor path for a given draft report id (under Altro › Rapportini).
  static String rapportiniEditor(String reportId) =>
      '/altro/rapportini/editor/$reportId';
}

/// Global navigator key — use for imperative navigation outside widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds and returns the [GoRouter] for the TaskTap app.
///
/// Auth guard: the `redirect` callback reads [authStateProvider] from [ref].
/// - AsyncLoading: return null (stay on current route while determining state).
/// - null user (unauthenticated): redirect to /login.
/// - non-null user (authenticated): redirect away from /login to /dashboard.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.dashboard,
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
          if (isAuthenticated && isOnLogin) return AppRoutes.dashboard;
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

      // ── Main Shell (5-tab pill bottom nav) ───────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          // 0 — Dashboard
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'dashboard'),
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // 1 — Ticket
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'ticket'),
            routes: [
              GoRoute(
                path: AppRoutes.ticket,
                builder: (context, state) => const TicketListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => TicketDetailScreen(
                      ticketId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 2 — Timbra
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'timbra'),
            routes: [
              GoRoute(
                path: AppRoutes.timbra,
                builder: (context, state) => const TimbraScreen(),
              ),
            ],
          ),
          // 3 — Calendario (placeholder)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'calendario'),
            routes: [
              GoRoute(
                path: AppRoutes.calendario,
                builder: (context, state) =>
                    const CalendarioPlaceholderScreen(),
              ),
            ],
          ),
          // 4 — Altro (hub + Rapportini + Profilo sub-routes)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'altro'),
            routes: [
              GoRoute(
                path: AppRoutes.altro,
                builder: (context, state) => const AltroScreen(),
                routes: [
                  GoRoute(
                    path: 'rapportini',
                    builder: (context, state) => const RapportiniScreen(),
                    routes: [
                      GoRoute(
                        path: 'editor/:reportId',
                        builder: (context, state) => RapportinoFormScreen(
                          reportId: state.pathParameters['reportId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'profilo',
                    builder: (context, state) => const ProfiloScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// [Listenable] that notifies go_router whenever auth state changes.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(WidgetRef ref) {
    ref.listenManual(authStateProvider, (prev, next) => notifyListeners());
  }
}
