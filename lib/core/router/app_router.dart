import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/widgets.dart';
import '../../features/altro/altro_hub_screen.dart';
import '../../features/altro/i_miei_dati_screen.dart';
import '../../features/altro/impostazioni_screen.dart';
import '../../features/altro/notifiche_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/screens/home/home_shell.dart';
import '../../features/ticket/new_ticket_form_screen.dart';
import '../../features/ticket/ticket_detail_screen.dart';
import '../../features/ticket/ticket_list_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../features/kiosk/kiosk_activation_screen.dart';
import '../../features/kiosk/kiosk_display_screen.dart';
import '../../presentation/providers/kiosk_providers.dart';
import '../../features/calendario/calendario_screen.dart';
import '../../features/timbra/timbra_screen.dart';
import '../../features/timbra/seleziona_cantiere_screen.dart';
import '../../features/timbra/scan_timbra_screen.dart';
import '../../presentation/screens/profilo/profilo_screen.dart';
import '../../features/admin/customers/admin_customer_detail_screen.dart';
import '../../features/admin/customers/admin_customer_form_screen.dart';
import '../../features/admin/locations/admin_location_list_screen.dart';
import '../../features/admin/locations/admin_location_detail_screen.dart';
import '../../features/admin/locations/admin_location_form_screen.dart';
import '../../features/admin/cantieri/admin_cantiere_list_screen.dart';
import '../../features/admin/cantieri/admin_cantiere_detail_screen.dart';
import '../../features/admin/commesse/admin_commessa_detail_screen.dart';
import '../../features/admin/cantieri/admin_cantiere_form_screen.dart';
import '../../features/admin/schedules/admin_schedule_list_screen.dart';
import '../../features/admin/schedules/admin_schedule_detail_screen.dart';
import '../../features/admin/schedules/admin_schedule_form_screen.dart';
import '../../features/admin/materiali/admin_materiale_list_screen.dart';
import '../../features/admin/materiali/admin_materiale_detail_screen.dart';
import '../../features/admin/materiali/admin_materiale_form_screen.dart';
import '../../features/admin/magazzini/admin_magazzino_list_screen.dart';
import '../../features/admin/magazzini/admin_magazzino_detail_screen.dart';
import '../../features/admin/magazzini/admin_magazzino_form_screen.dart';
import '../../features/magazzino/magazzino_screen.dart';
import '../../data/magazzino/magazzino_api_client.dart' show MagazzinoDto;
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
import '../../features/ferie/ferie_permessi_form_screen.dart';
import '../../features/ferie/ferie_permessi_list_screen.dart';
import '../../features/clienti/clienti_list_screen.dart';
import '../../features/rapportino/ai_copilot_screen.dart';
import '../../features/rapportino/rapportino_form_screen.dart';
import '../../features/rapportino/rapportini_list_screen.dart';
import '../../features/rapportino/rapportino_view_screen.dart';
import '../../features/timbra/cantiere_timbra_screen.dart';
import '../../features/cantiere/cantieri_list_screen.dart';
import '../../features/cantiere/cantiere_detail_screen.dart';
import '../../features/altro/forbidden_screen.dart';
import '../../data/entitlements/entitlement_providers.dart';
import '../../features/onboarding/onboarding_provider.dart';
import '../../features/onboarding/onboarding_screen.dart';
import 'route_requirement.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Route path constants.
abstract final class AppRoutes {
  static const String login = '/login';

  /// Shown once per account, right after first login, before Dashboard — see the router's
  /// `redirect` callback for the gate, and `docs/superpowers/specs/2026-09-17-onboarding-flow-design.md`
  /// for why this exists and why it's per-account rather than per-device.
  static const String onboarding = '/onboarding';

  /// Where the `redirect` callback's route-requirement guard (see [RouteRequirement] and
  /// `_routeRequirements` below) sends a request for a route whose module/capability requirement
  /// is not held. Must never itself appear as a `_routeRequirements` prefix — that would
  /// self-redirect-loop.
  static const String forbidden = '/forbidden';

  /// Where a device that has never been activated as a kiosk goes to redeem the credential the
  /// web admin issued (see `KioskActivationScreen`). Reached only via the hidden long-press on
  /// the logo on [LoginScreen] — never linked from anywhere inside the authenticated app.
  static const String kioskActivate = '/kiosk/activate';

  /// The kiosk's only screen once activated ([KioskDisplayScreen]) — the router's `redirect`
  /// callback forces every route here whenever `kioskModeProvider.active` is true, overriding
  /// the ordinary auth guard below entirely (a kiosk tablet never signs in as a person).
  static const String kioskDisplay = '/kiosk';

  static const String dashboard = '/dashboard';
  static const String ticket = '/ticket';
  static const String ticketDetail = '/ticket/:id';

  /// Build the detail path for a given ticket id.
  static String ticketDetailPath(String id) => '/ticket/$id';

  static const String timbra = '/timbra';

  /// Scan-to-clock-in via a kiosk totem's rotating QR (POST /api/worklog/kiosk/scan) — reached
  /// from TimbraScreen's header action, not the dashboard: this is a variant of the personal
  /// punch, not a third "start something" tile.
  static const String timbraQr = '/timbra-qr';

  /// Technician-facing cantieri (worksites) list — the Cantieri tab.
  static const String cantieri = '/cantieri';
  static const String cantieriDetail = '/cantieri/:id';

  /// Build the detail path for a given cantiere id, optionally carrying the ticket that launched
  /// it (see the cantiere chip in `ticket_detail_screen.dart`) so the eventual Timbra session
  /// downstream stays tagged with that ticket.
  static String cantieriDetailPath(String id, {String? ticketId}) =>
      ticketId == null ? '/cantieri/$id' : '/cantieri/$id?ticketId=$ticketId';

  static const String calendario = '/calendario';
  static const String altro = '/altro';
  static const String altroRapportini = '/altro/rapportini';
  static const String altroImpostazioni = '/altro/impostazioni';
  static const String altroNotifiche = '/altro/notifiche';

  /// The subject-access surface: what the company has on record about this person.
  static const String altroIMieiDati = '/altro/i-miei-dati';

  /// Path for the shared "unavailable" placeholder; pass an
  /// `({String titolo, String motivo})` record as GoRouter extra so the
  /// screen can state a real reason instead of a "coming soon" promise.
  static const String altroNonDisponibile = '/altro/non-disponibile';

  /// Path for the cantiere clock-in/out screen. Every real navigation now supplies `cantiereId` —
  /// see CantiereTimbraScreen's own header comment — but the query param stays optional here
  /// (rather than a required path segment) to avoid a route-shape change; the screen itself
  /// treats a missing id the same as a cantiere that failed to resolve.
  static const String cantiereTimbra = '/cantiere-timbra';

  /// Build the cantiere timbra path with optional query params.
  static String cantiereTimbraPath({
    String? ticketId,
    String? customerId,
    String? cantiereId,
  }) {
    final params = <String>[];
    if (ticketId != null) params.add('ticketId=$ticketId');
    if (customerId != null) params.add('customerId=$customerId');
    if (cantiereId != null) params.add('cantiereId=$cantiereId');
    return params.isEmpty
        ? cantiereTimbra
        : '$cantiereTimbra?${params.join('&')}';
  }

  /// Path for the full-screen cantiere picker — the dashboard's generic "Timbra cantiere" quick
  /// action (no cantiere context yet) now lands here instead of on CantiereTimbraScreen's
  /// now-removed inline picker. See SelezionaCantiereScreen's own header comment.
  static const String selezionaCantiere = '/seleziona-cantiere';

  /// Build the seleziona-cantiere path with optional query params (ticket context, when present).
  static String selezionaCantierePath({String? ticketId, String? customerId}) {
    final params = <String>[];
    if (ticketId != null) params.add('ticketId=$ticketId');
    if (customerId != null) params.add('customerId=$customerId');
    return params.isEmpty
        ? selezionaCantiere
        : '$selezionaCantiere?${params.join('&')}';
  }

  /// Self-service ferie/permessi against `/api/absence-requests` — already complete and tested
  /// server-side (docs/superpowers/specs/2026-08-30-ferie-permessi-design.md). No approval
  /// queue on mobile; that lives only on web, gated behind PresenzeAbsenceApprove.
  static const String altroFerie = '/altro/ferie';

  static const String altroClienti = '/altro/clienti';
  static const String altroClientiDetail = '/altro/clienti/:id';
  static const String altroMagazzino = '/altro/magazzino';

  /// Stock levels and movements (Articoli/Giacenze/Movimenti) — the read-through-to-server screen
  /// that was built (`MagazzinoScreen`) but never wired into the router until Gap 3/4 of the
  /// feature audit gave it write actions and a reason to be reachable.
  static const String altroMagazzinoGiacenze = '/altro/magazzino/giacenze';

  /// Warehouse (Magazzino entity — Sede/Furgone) admin CRUD, distinct from the materiali catalogue
  /// CRUD that already lived at [altroMagazzino]. Gap 2 of the feature audit.
  static const String altroMagazzini = '/altro/magazzino/magazzini';

  /// Build the detail path for a given customer id.
  static String clientiDetail(String id) => '/altro/clienti/$id';

  /// Build the editor path for a given draft report id (under Altro › Rapportini).
  static String rapportiniEditor(String reportId) =>
      '/altro/rapportini/editor/$reportId';

  /// Build the AI Copilot path — bound to at most one of ticketId/cantiereId (mutually exclusive,
  /// same as the backend's `POST /api/ai/conversations`).
  static String rapportiniCopilot({String? ticketId, String? cantiereId}) {
    final params = <String, String>{
      'ticketId': ?ticketId,
      'cantiereId': ?cantiereId,
    };
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return '/altro/rapportini/copilot$query';
  }

  /// Build the read-only view path for a submitted rapportino.
  static String rapportiniView(String reportId) =>
      '/altro/rapportini/view/$reportId';
}

/// Global navigator key — use for imperative navigation outside widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Path prefix → what's required to reach any route beneath it, checked centrally in
/// `buildRouter`'s `redirect` rather than per-screen. A path with no matching prefix here has no
/// route-level requirement beyond the auth check.
///
/// This is a list of `(prefix, requirement)` pairs matched via [String.startsWith], NOT a
/// `Map<String, RouteRequirement>` keyed on the literal route pattern. GoRouter substitutes a
/// dynamic segment (e.g. `:id`) with the real value in `state.matchedLocation` for an actual
/// visit, so an exact-string map keyed on `'/altro/pianificazioni/:id'` would never match a real
/// navigation there — a plain map is the wrong data structure for a route subtree that has
/// dynamic children. A prefix like `'/altro/pianificazioni'` covers every route beneath it (list,
/// `nuova`, `:id`, `:id/modifica`) in one entry, no matter how deep, since a dynamic segment in
/// the middle still starts with the parent prefix.
///
/// **Order matters**: the loop below breaks on the FIRST matching prefix, so a more specific
/// prefix must be listed before a broader one it is nested under (`/altro/rapportini-admin`
/// before `/altro/rapportini`; `/altro/magazzino/magazzini` before `/altro/magazzino`) — otherwise
/// the broader entry would shadow it and apply the wrong requirement.
///
/// [AppRoutes.forbidden] itself must NEVER be prefix-matched by an entry here — that would
/// self-redirect-loop back onto itself. None of the prefixes below start with `/forbidden`.
///
/// The mobile Admin surface (`/altro/...` admin CRUD screens — `clienti`, `sedi`, `cantieri`,
/// `squadre`, `contratti`, `commesse`, `magazzino`/`magazzini`, `pianificazioni`,
/// `rapportini-admin`) is dispatcher-only — a narrower, genuinely different audience than "anyone
/// who can use the module at all" — so each is gated on the resource's `.read` capability at
/// minimum (its own write actions are gated further, at the button level, by `CapabilityGate`).
/// `prodotti` is deliberately NOT gated here: the backend defines no `prodotti.*` capability yet
/// (see `PermissionCatalogue.All`'s own comment — "a capability nothing requires governs
/// nothing"), so there is nothing correct to check.
///
/// The end-user/operational routes (`/ticket`, `/cantieri`, `/altro/rapportini`, `/altro/ferie`)
/// are a different, broader audience — anyone whose tenant has the module, not dispatcher-only —
/// so those check module entitlement only, matching the web guard's equivalent split.
///
/// A dynamic segment defeats plain prefix matching for a *write* leaf nested past it (e.g.
/// `/altro/clienti/:id/modifica` — the `:id` varies, so no fixed prefix covers only `modifica`).
/// Each entry's optional third element, `writeRequirement`, closes that: when the visited path's
/// LAST segment is `nuovo` or `modifica` (see `_writeLeafSegments`), that stricter requirement is
/// checked instead of the base one — still prefix-matched first, so it only applies within a
/// section this table already governs. Left `null` for sections where read and write are gated
/// identically at the section level already (nothing sharper to express); given only where a
/// section mixes open read with gated write (`clienti`, `sedi`) — the base `.read` requirement
/// alone would let a held-read/denied-write user past the button-level `CapabilityGate` that hides
/// `nuovo`/`modifica` triggers in the UI, by deep-linking straight to the path.
final _routeRequirements = <(String pathPrefix, RouteRequirement requirement, RouteRequirement? writeRequirement)>[
  ('/altro/pianificazioni', const RouteRequirement.capability('pianificazione.schedule.write'), null),
  ('/altro/rapportini-admin', const RouteRequirement.capability('rapportini.report.read'), null),
  ('/altro/rapportini', const RouteRequirement.module('rapportini'), null),
  ('/altro/magazzino/magazzini', const RouteRequirement.capability('magazzino.warehouse.read'), null),
  ('/altro/magazzino', const RouteRequirement.capability('magazzino.article.read'), null),
  ('/altro/squadre', const RouteRequirement.capability('team.squadra.read'), null),
  ('/altro/cantieri', const RouteRequirement.capability('cantieri.cantiere.read'), null),
  ('/altro/contratti', const RouteRequirement.capability('contratti.contract.read'), null),
  ('/altro/commesse', const RouteRequirement.capability('commesse.commessa.read'), null),
  (
    '/altro/sedi',
    const RouteRequirement.capability('clienti.location.read'),
    const RouteRequirement.capability('clienti.location.write'),
  ),
  (
    '/altro/clienti',
    const RouteRequirement.capability('clienti.customer.read'),
    const RouteRequirement.capability('clienti.customer.write'),
  ),
  ('/altro/ferie', const RouteRequirement.module('presenze'), null),
  ('/ticket', const RouteRequirement.module('interventi'), null),
  ('/cantieri', const RouteRequirement.module('cantieri'), null),
];

/// Leaf path segments that mean "this specific visit is a write attempt" — checked against
/// `state.matchedLocation`'s LAST segment only, so a record id that happens to be the literal
/// string `nuovo` (impossible — ids are GUIDs) or `modifica` can never false-positive.
const _writeLeafSegments = {'nuovo', 'modifica'};

/// Builds and returns the [GoRouter] for the TaskTap app.
///
/// Kiosk guard runs BEFORE the auth guard: a device with `kioskModeProvider.active == true` is
/// never a person's phone — every route on it, including /login, is forced to
/// [AppRoutes.kioskDisplay] (the one exception being [AppRoutes.kioskActivate] itself mid-flow,
/// see below). Only `KioskModeNotifier.deactivate`/`_forceDeactivate` flipping `active` back to
/// false lets the ordinary auth guard run again.
///
/// Auth guard: the `redirect` callback reads [authStateProvider] from [ref].
/// - AsyncLoading: return null (stay on current route while determining state).
/// - null user (unauthenticated): redirect to /login.
/// - non-null user (authenticated): redirect away from /login to /dashboard.
///
/// Onboarding guard: runs only once a user is confirmed authenticated (ahead of the
/// route-requirement guard below), reading [onboardingCompletedProvider] keyed by that user's id.
/// - Not completed, not already on /onboarding: redirect to /onboarding.
/// - Completed, still on /onboarding: redirect to /dashboard.
GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.dashboard,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final kioskState = ref.read(kioskModeProvider);
      final isOnKioskActivate =
          state.matchedLocation == AppRoutes.kioskActivate;
      final isOnKioskDisplay = state.matchedLocation == AppRoutes.kioskDisplay;

      // While secure storage is still being read at cold start, stay put — same "don't redirect
      // yet" treatment AsyncLoading gets below.
      if (kioskState.loading) return null;

      if (kioskState.active) {
        return isOnKioskDisplay ? null : AppRoutes.kioskDisplay;
      }
      // Not active: kioskDisplay itself is unreachable (nothing to show), but activation is
      // always allowed regardless of auth state — a kiosk tablet is activated before anyone
      // ever signs in on it.
      if (isOnKioskDisplay) return AppRoutes.login;
      if (isOnKioskActivate) return null;

      final authAsync = ref.read(authStateProvider);
      final isOnLogin = state.matchedLocation == AppRoutes.login;
      final isOnOnboarding = state.matchedLocation == AppRoutes.onboarding;

      return authAsync.when(
        // While Supabase is restoring the session, stay put.
        loading: () => null,
        // On error (e.g. offline with no cached session), go to login.
        error: (err, stack) => isOnLogin ? null : AppRoutes.login,
        data: (user) {
          final isAuthenticated = user != null;
          if (!isAuthenticated && !isOnLogin) return AppRoutes.login;
          if (isAuthenticated && isOnLogin) return AppRoutes.dashboard;
          if (!isAuthenticated) return null; // unauthenticated and already on /login

          // Onboarding gate — evaluated only once we know who's signed in, and before the
          // route-requirement guard below: an account that hasn't finished onboarding gets sent
          // there regardless of what module/capability the destination route would otherwise
          // require, rather than being bounced to /forbidden first.
          final onboardingAsync = ref.read(onboardingCompletedProvider(user.id));
          final onboardingRedirect = onboardingAsync.when(
            loading: () => null,
            error: (err, stack) => null,
            data: (completed) {
              if (!completed && !isOnOnboarding) return AppRoutes.onboarding;
              if (completed && isOnOnboarding) return AppRoutes.dashboard;
              return null;
            },
          );
          if (onboardingRedirect != null) return onboardingRedirect;

          // Route-requirement guard — runs only once auth is confirmed and isn't itself
          // redirecting. Never applies to AppRoutes.forbidden itself (see _routeRequirements'
          // own doc comment on why that would self-redirect-loop).
          if (state.matchedLocation != AppRoutes.forbidden) {
            for (final (prefix, requirement, writeRequirement) in _routeRequirements) {
              if (state.matchedLocation.startsWith(prefix)) {
                final segments = state.matchedLocation.split('/');
                final isWriteLeaf = segments.isNotEmpty && _writeLeafSegments.contains(segments.last);
                final effective = isWriteLeaf && writeRequirement != null
                    ? writeRequirement
                    : requirement;
                final satisfied = effective.isSatisfied(ref);
                // satisfied == null: entitlement cache still loading — stay put, don't redirect
                // yet (same "don't know yet" treatment as kioskState.loading/authAsync.loading
                // above).
                if (satisfied == false) return AppRoutes.forbidden;
                break;
              }
            }
          }

          return null;
        },
      );
    },
    // Rebuild router on auth state, kiosk mode, onboarding-completion, OR entitlement cache
    // changes so redirects are applied to all four.
    refreshListenable: Listenable.merge([
      _AuthStateListenable(ref),
      _KioskStateListenable(ref),
      _OnboardingStateListenable(ref),
      _EntitlementStateListenable(ref),
    ]),
    routes: [
      // ── Kiosk ───────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.kioskActivate,
        builder: (context, state) => const KioskActivationScreen(),
      ),
      GoRoute(
        path: AppRoutes.kioskDisplay,
        builder: (context, state) => const KioskDisplayScreen(),
      ),

      // ── Auth ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) {
          final userId = ref.read(authStateProvider).valueOrNull?.id;
          // The redirect gate never lands here without an authenticated user (see the
          // onboarding gate above), so this is unreachable in practice — the empty-string
          // fallback just satisfies the type system rather than crashing if it somehow were.
          return OnboardingScreen(userId: userId ?? '');
        },
      ),

      // ── Cantiere timbra (pushed from cantiere detail, or from the picker below) ──
      GoRoute(
        path: AppRoutes.cantiereTimbra,
        builder: (context, state) {
          final ticketId = state.uri.queryParameters['ticketId'];
          final customerId = state.uri.queryParameters['customerId'];
          final cantiereId = state.uri.queryParameters['cantiereId'];
          return CantiereTimbraScreen(
            ticketId: ticketId,
            customerId: customerId,
            cantiereId: cantiereId,
          );
        },
      ),

      // ── Seleziona cantiere (pushed from the dashboard's generic "Timbra cantiere" action) ──
      GoRoute(
        path: AppRoutes.selezionaCantiere,
        builder: (context, state) {
          final ticketId = state.uri.queryParameters['ticketId'];
          final customerId = state.uri.queryParameters['customerId'];
          return SelezionaCantiereScreen(
            ticketId: ticketId,
            customerId: customerId,
          );
        },
      ),

      // ── Personal Timbra (pushed from a Dashboard quick action) ──────────────
      GoRoute(
        path: AppRoutes.timbra,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TimbraScreen(),
      ),

      // ── Scan-to-timbra (pushed from TimbraScreen's header action) ────────────
      GoRoute(
        path: AppRoutes.timbraQr,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ScanTimbraScreen(),
      ),

      // ── New ticket form (pushed from ticket list FAB) ─────────────────────
      GoRoute(
        path: '/ticket/new',
        builder: (context, state) => const NewTicketFormScreen(),
      ),

      // ── Forbidden (route-requirement guard's redirect target) ────────────
      GoRoute(
        path: AppRoutes.forbidden,
        builder: (context, state) => const ForbiddenScreen(),
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
                    // Full-screen, no persistent bottom nav: a dense multi-tab detail screen
                    // needs the vertical space the shell's floating pill nav would otherwise
                    // eat permanently. See parentNavigatorKey on every form/detail route below.
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => TicketDetailScreen(
                      ticketId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 2 — Cantieri
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'cantieri'),
            routes: [
              GoRoute(
                path: AppRoutes.cantieri,
                builder: (context, state) => const CantieriListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    // Full-screen, no persistent bottom nav — same reasoning as ticket detail's
                    // own `parentNavigatorKey` (see that route's comment above).
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => CantiereDetailScreen(
                      cantiereId: state.pathParameters['id']!,
                      ticketId: state.uri.queryParameters['ticketId'],
                    ),
                  ),
                ],
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
                    builder: (context, state) => const RapportiniListScreen(),
                    routes: [
                      GoRoute(
                        path: 'editor/:reportId',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => RapportinoFormScreen(
                          reportId: state.pathParameters['reportId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'copilot',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => AiCopilotScreen(
                          ticketId: state.uri.queryParameters['ticketId'],
                          cantiereId: state.uri.queryParameters['cantiereId'],
                        ),
                      ),
                      GoRoute(
                        path: 'view/:reportId',
                        parentNavigatorKey: rootNavigatorKey,
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
                    builder: (context, state) => const ImpostazioniScreen(),
                  ),
                  GoRoute(
                    path: 'notifiche',
                    builder: (context, state) => const NotificheScreen(),
                  ),
                  GoRoute(
                    path: 'i-miei-dati',
                    builder: (context, state) => const IMieiDatiScreen(),
                  ),
                  GoRoute(
                    path: 'ferie',
                    builder: (context, state) =>
                        const FeriePermessiListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const FeriePermessiFormScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'clienti',
                    builder: (context, state) => const ClientiListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminCustomerFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => AdminCustomerDetailScreen(
                          customerId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                    path: 'commesse/:id',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => AdminCommessaDetailScreen(
                      commessaId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'cantieri',
                    builder: (context, state) =>
                        const AdminCantiereListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminCantiereFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => AdminCantiereDetailScreen(
                          cantiereId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                        parentNavigatorKey: rootNavigatorKey,
                        // `extra` carries an optional pre-selected customerId when pushed from
                        // the customer detail screen's Sedi section (Gap 3 of the feature
                        // audit) — null (the global Sedi list's own FAB) leaves the picker empty
                        // as before.
                        builder: (context, state) => AdminLocationFormScreen(
                          initialCustomerId: state.extra as String?,
                        ),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => AdminLocationDetailScreen(
                          locationId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                    // `extra` is a squadraId when navigated here from that squadra's detail
                    // screen (Gap 9 of the feature audit, "Pianificazioni squadra" header
                    // action) — pre-applies the squadra filter instead of landing on the
                    // unfiltered list and making the admin reopen the filter sheet.
                    builder: (context, state) => AdminScheduleListScreen(
                      initialSquadraId: state.extra as String?,
                    ),
                    routes: [
                      GoRoute(
                        path: 'nuova',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminScheduleFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => AdminScheduleDetailScreen(
                          scheduleId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminMaterialeFormScreen(),
                      ),
                      // Stock levels and movements (Gap 3/4 of the feature audit) — a static
                      // segment, declared before `:id` below so `/magazzino/giacenze` matches
                      // this route rather than being captured as a materiale id.
                      GoRoute(
                        path: 'giacenze',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => const MagazzinoScreen(),
                      ),
                      // Warehouse (Magazzino entity) admin CRUD — Gap 2 of the feature audit.
                      // Also a static segment, ordered before `:id` for the same reason.
                      GoRoute(
                        path: 'magazzini',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminMagazzinoListScreen(),
                        routes: [
                          GoRoute(
                            path: 'nuovo',
                            parentNavigatorKey: rootNavigatorKey,
                            builder: (context, state) =>
                                const AdminMagazzinoFormScreen(),
                          ),
                          GoRoute(
                            path: ':id',
                            parentNavigatorKey: rootNavigatorKey,
                            builder: (context, state) =>
                                AdminMagazzinoDetailScreen(
                                  magazzino: state.extra as MagazzinoDto?,
                                ),
                            routes: [
                              GoRoute(
                                path: 'modifica',
                                parentNavigatorKey: rootNavigatorKey,
                                builder: (context, state) =>
                                    AdminMagazzinoFormScreen(
                                      magazzino: state.extra as MagazzinoDto?,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => AdminMaterialeDetailScreen(
                          materialeId: state.pathParameters['id']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminProdottoFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) {
                          final prodotto = state.extra as Map<String, dynamic>?;
                          return AdminProdottoDetailScreen(
                            prodotto: prodotto ?? {},
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminContractFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) {
                          final contract = state.extra as Map<String, dynamic>?;
                          return AdminContractDetailScreen(
                            contract: contract ?? {},
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
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
                    builder: (context, state) => const AdminSquadraListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nuovo',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const AdminSquadraFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) {
                          final squadra = state.extra as Map<String, dynamic>?;
                          return AdminSquadraDetailScreen(
                            squadra: squadra ?? {},
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'modifica',
                            parentNavigatorKey: rootNavigatorKey,
                            builder: (context, state) {
                              final squadra =
                                  state.extra as Map<String, dynamic>?;
                              return AdminSquadraFormScreen(squadra: squadra);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'rapportini-admin',
                    builder: (context, state) => const AdminReportListScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) {
                          final report = state.extra as Map<String, dynamic>?;
                          return AdminReportDetailScreen(report: report ?? {});
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
                                  motivo:
                                      args?.motivo ??
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

/// [Listenable] that notifies go_router whenever kiosk mode is activated/deactivated, so the
/// redirect callback's kiosk guard (see [buildRouter]) re-runs the moment
/// `KioskModeNotifier.activate`/`deactivate` flips `kioskModeProvider.active`.
class _KioskStateListenable extends ChangeNotifier {
  _KioskStateListenable(WidgetRef ref) {
    ref.listenManual(kioskModeProvider, (prev, next) => notifyListeners());
  }
}

/// [Listenable] that notifies go_router whenever the signed-in user's onboarding-completion
/// status resolves or changes, so the redirect callback's onboarding gate (see [buildRouter])
/// re-runs once the async `SharedPreferences` read completes — it starts as loading, same as the
/// kiosk/auth gates do at cold start — and immediately when
/// `OnboardingCompletedNotifier.markCompleted` flips it.
///
/// Unlike [_AuthStateListenable]/[_KioskStateListenable], the provider being watched here is a
/// *family* keyed by user id, which isn't known until [authStateProvider] resolves — so this
/// listens to auth first, then (re)subscribes to the onboarding provider for whichever user is
/// currently signed in, tearing the old subscription down if the user changes.
class _OnboardingStateListenable extends ChangeNotifier {
  _OnboardingStateListenable(WidgetRef ref) {
    ref.listenManual(authStateProvider, (previous, next) {
      final userId = next.valueOrNull?.id;
      _subscription?.close();
      _subscription = userId == null
          ? null
          : ref.listenManual(
              onboardingCompletedProvider(userId),
              (prev, next) => notifyListeners(),
            );
      notifyListeners();
    }, fireImmediately: true);
  }

  ProviderSubscription<AsyncValue<bool>>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

/// [Listenable] that notifies go_router whenever the cached entitlement resolves or changes, so
/// the route-requirement guard (`_routeRequirements`, see [buildRouter]) re-runs once an answer
/// is known.
///
/// Without this, a cold-started deep link straight into a guarded route (the exact scenario this
/// guard exists to close) would see `RouteRequirement.isSatisfied` return null while the cache is
/// still loading, correctly stay put per that null case's contract — and then never get
/// re-checked, since nothing else would tell go_router to re-run `redirect` once the cache
/// actually resolved. Mirrors [_AuthStateListenable]/[_KioskStateListenable], the two other
/// async-loading signals `redirect` already depends on.
class _EntitlementStateListenable extends ChangeNotifier {
  _EntitlementStateListenable(WidgetRef ref) {
    ref.listenManual(cachedEntitlementProvider, (prev, next) => notifyListeners());
  }
}
