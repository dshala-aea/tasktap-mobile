import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/widgets.dart';
import '../../features/altro/altro_hub_screen.dart';
import '../../features/altro/impostazioni_screen.dart';
import '../../features/altro/notifiche_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/screens/home/home_shell.dart';
import '../../features/ticket/new_ticket_form_screen.dart';
import '../../features/ticket/ticket_detail_screen.dart';
import '../../features/ticket/ticket_list_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../features/calendario/calendario_screen.dart';
import '../../features/timbra/timbra_screen.dart';
import '../../presentation/screens/profilo/profilo_screen.dart';
import '../../features/admin/customers/admin_customer_detail_screen.dart';
import '../../features/admin/customers/admin_customer_form_screen.dart';
import '../../features/admin/locations/admin_location_list_screen.dart';
import '../../features/admin/locations/admin_location_detail_screen.dart';
import '../../features/admin/locations/admin_location_form_screen.dart';
import '../../features/admin/cantieri/admin_cantiere_list_screen.dart';
import '../../features/admin/cantieri/admin_cantiere_detail_screen.dart';
import '../../features/admin/cantieri/admin_cantiere_form_screen.dart';
import '../../features/admin/schedules/admin_schedule_list_screen.dart';
import '../../features/admin/schedules/admin_schedule_detail_screen.dart';
import '../../features/admin/schedules/admin_schedule_form_screen.dart';
import '../../features/admin/materiali/admin_materiale_list_screen.dart';
import '../../features/admin/materiali/admin_materiale_detail_screen.dart';
import '../../features/admin/materiali/admin_materiale_form_screen.dart';
import '../../features/admin/prodotti/admin_prodotto_list_screen.dart';
import '../../features/admin/prodotti/admin_prodotto_detail_screen.dart';
import '../../features/admin/prodotti/admin_prodotto_form_screen.dart';
import '../../features/admin/contracts/admin_contract_list_screen.dart';
import '../../features/admin/contracts/admin_contract_detail_screen.dart';
import '../../features/admin/contracts/admin_contract_form_screen.dart';
import '../../features/admin/squadre/admin_squadra_list_screen.dart';
import '../../features/admin/squadre/admin_squadra_detail_screen.dart';
import '../../features/admin/squadre/admin_squadra_form_screen.dart';
import '../../features/admin/reports/admin_report_list_screen.dart';
import '../../features/admin/reports/admin_report_detail_screen.dart';
import '../../features/clienti/clienti_list_screen.dart';
import '../../features/rapportino/rapportino_form_screen.dart';
import '../../features/rapportino/rapportini_list_screen.dart';
import '../../features/rapportino/rapportino_view_screen.dart';
import '../../features/timbra/cantiere_timbra_screen.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
  static const String altroImpostazioni = '/altro/impostazioni';
  static const String altroNotifiche = '/altro/notifiche';

  /// Path for the shared "unavailable" placeholder; pass an
  /// `({String titolo, String motivo})` record as GoRouter extra so the
  /// screen can state a real reason instead of a "coming soon" promise.
  static const String altroNonDisponibile = '/altro/non-disponibile';

  /// Path for the cantiere clock-in/out screen.
  static const String cantiereTimbra = '/cantiere-timbra';

  /// Build the cantiere timbra path with optional query params.
  static String cantiereTimbraPath({String? ticketId, String? customerId}) {
    final params = <String>[];
    if (ticketId != null) params.add('ticketId=$ticketId');
    if (customerId != null) params.add('customerId=$customerId');
    return params.isEmpty ? cantiereTimbra : '$cantiereTimbra?${params.join('&')}';
  }

  static const String altroClienti = '/altro/clienti';
  static const String altroClientiDetail = '/altro/clienti/:id';
  static const String altroMagazzino = '/altro/magazzino';

  /// Build the detail path for a given customer id.
  static String clientiDetail(String id) => '/altro/clienti/$id';

  /// Build the editor path for a given draft report id (under Altro › Rapportini).
  static String rapportiniEditor(String reportId) =>
      '/altro/rapportini/editor/$reportId';

  /// Build the read-only view path for a submitted rapportino.
  static String rapportiniView(String reportId) =>
      '/altro/rapportini/view/$reportId';
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

      // ── Cantiere timbra (pushed from ticket detail) ──────────────────────
      GoRoute(
        path: AppRoutes.cantiereTimbra,
        builder: (context, state) {
          final ticketId = state.uri.queryParameters['ticketId'];
          final customerId = state.uri.queryParameters['customerId'];
          return CantiereTimbraScreen(
            ticketId: ticketId,
            customerId: customerId,
          );
        },
      ),

      // ── New ticket form (pushed from ticket list FAB) ─────────────────────
      GoRoute(
        path: '/ticket/new',
        builder: (context, state) => const NewTicketFormScreen(),
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
          // 3 — Calendario
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'calendario'),
            routes: [
              GoRoute(
                path: AppRoutes.calendario,
                builder: (context, state) => const CalendarioScreen(),
              ),
            ],
          ),
          // 4 — Altro (hub + Rapportini + Profilo + Impostazioni + Notifiche)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'altro'),
            routes: [
              GoRoute(
                path: AppRoutes.altro,
                builder: (context, state) => const AltroHubScreen(),
                routes: [
                  GoRoute(
                    path: 'rapportini',
                    builder: (context, state) =>
                        const RapportiniListScreen(),
                    routes: [
                      GoRoute(
                        path: 'editor/:reportId',
                        builder: (context, state) => RapportinoFormScreen(
                          reportId: state.pathParameters['reportId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'view/:reportId',
                        builder: (context, state) => RapportinoViewScreen(
                          reportId: state.pathParameters['reportId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'profilo',
                    builder: (context, state) => const ProfiloScreen(),
                  ),
                  GoRoute(
                    path: 'impostazioni',
                    builder: (context, state) =>
                        const ImpostazioniScreen(),
                  ),
                  GoRoute(
                    path: 'notifiche',
                    builder: (context, state) =>
                        const NotificheScreen(),
                  ),
                  GoRoute(
                    path: 'clienti',
                    builder: (context, state) => const ClientiListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        builder: (context, state) =>
                            const AdminCustomerFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => AdminCustomerDetailScreen(
                          customerId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) =>
                                AdminCustomerFormScreen(
                              customerId: state.pathParameters['id']!,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'cantieri',
                    builder: (context, state) =>
                        const AdminCantiereListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        builder: (context, state) =>
                            const AdminCantiereFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            AdminCantiereDetailScreen(
                          cantiereId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) =>
                                AdminCantiereFormScreen(
                              cantiereId: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'sedi',
                    builder: (context, state) =>
                        const AdminLocationListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuova',
                        builder: (context, state) =>
                            const AdminLocationFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            AdminLocationDetailScreen(
                          locationId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) =>
                                AdminLocationFormScreen(
                              locationId: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'pianificazioni',
                    builder: (context, state) =>
                        const AdminScheduleListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuova',
                        builder: (context, state) =>
                            const AdminScheduleFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            AdminScheduleDetailScreen(
                          scheduleId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) =>
                                AdminScheduleFormScreen(
                              scheduleId: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'magazzino',
                    builder: (context, state) =>
                        const AdminMaterialeListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        builder: (context, state) =>
                            const AdminMaterialeFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            AdminMaterialeDetailScreen(
                          materialeId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) =>
                                AdminMaterialeFormScreen(
                              materialeId: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'prodotti',
                    builder: (context, state) =>
                        const AdminProdottoListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        builder: (context, state) =>
                            const AdminProdottoFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) {
                          final prodotto =
                              state.extra as Map<String, dynamic>?;
                          return AdminProdottoDetailScreen(
                            prodotto: prodotto ?? {},
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) {
                              final prodotto =
                                  state.extra as Map<String, dynamic>?;
                              return AdminProdottoFormScreen(
                                prodotto: prodotto,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'contratti',
                    builder: (context, state) =>
                        const AdminContractListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        builder: (context, state) =>
                            const AdminContractFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) {
                          final contract =
                              state.extra as Map<String, dynamic>?;
                          return AdminContractDetailScreen(
                            contract: contract ?? {},
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) {
                              final contract =
                                  state.extra as Map<String, dynamic>?;
                              return AdminContractFormScreen(
                                contract: contract,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'squadre',
                    builder: (context, state) =>
                        const AdminSquadraListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        builder: (context, state) =>
                            const AdminSquadraFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) {
                          final squadra =
                              state.extra as Map<String, dynamic>?;
                          return AdminSquadraDetailScreen(
                            squadra: squadra ?? {},
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            builder: (context, state) {
                              final squadra =
                                  state.extra as Map<String, dynamic>?;
                              return AdminSquadraFormScreen(
                                squadra: squadra,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'rapportini-admin',
                    builder: (context, state) =>
                        const AdminReportListScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) {
                          final report =
                              state.extra as Map<String, dynamic>?;
                          return AdminReportDetailScreen(
                            report: report ?? {},
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'non-disponibile',
                    builder: (context, state) {
                      final args =
                          state.extra as ({String titolo, String motivo})?;
                      final titolo = args?.titolo ?? 'Sezione non disponibile';
                      return Scaffold(
                        backgroundColor: context.colors.bg2,
                        body: SafeArea(
                          child: Column(
                            children: [
                              ScreenHeader(title: titolo, showBack: true),
                              Expanded(
                                child: UnavailableState(
                                  titolo: titolo,
                                  motivo: args?.motivo ??
                                      'Questa funzione non è ancora stata implementata nel client mobile.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
