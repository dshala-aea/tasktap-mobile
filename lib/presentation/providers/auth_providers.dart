import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/time/business_time_providers.dart';
import '../../data/auth/session_ender.dart';
import '../../data/auth/zitadel_auth_repository.dart';
import '../../data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import '../../data/sync/sync_service.dart';
import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_user.dart';
import '../../domain/auth/i_auth_repository.dart';

// ── Repository provider ────────────────────────────────────────────────────

/// Provides the [IAuthRepository] implementation.
///
/// Override in tests:
/// ```dart
/// ProviderScope(
///   overrides: [authRepositoryProvider.overrideWithValue(fakeRepo)],
///   child: MyApp(),
/// )
/// ```
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return ZitadelAuthRepository();
});

// ── Session teardown ────────────────────────────────────────────────────────

/// The one object every "end this session" path goes through — the logout button (`end()`, which
/// wipes) and the interceptor's forced sign-out (`endForced()`, which keeps the local data). See
/// [SessionEnder] for why they are deliberately different endings.
///
/// A provider rather than a bare function so both callers get the *same* collaborators the app is
/// really using: `dioProvider` (a `Provider<Dio>`, built once) reads this from inside the
/// interceptor's error path, where `ref` is still valid.
final sessionEnderProvider = Provider<SessionEnder>((ref) {
  return SessionEnder(
    repo: ref.watch(authRepositoryProvider),
    db: ref.watch(appDatabaseProvider),
    resetBusinessZone: () => ref.read(businessZoneIdProvider.notifier).reset(),
  );
});

// ── Auth state stream ──────────────────────────────────────────────────────

/// Stream of the current [AuthUser] (or null when signed out).
///
/// Used by the go_router `redirect` callback to enforce route guards:
/// - null   → redirect to /login
/// - non-null → allow access to the app shell
final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// ── Current user ───────────────────────────────────────────────────────────

/// Synchronous snapshot of the current user.
///
/// Returns null while loading or when unauthenticated.
final currentUserProvider = Provider<AuthUser?>((ref) {
  return ref.watch(authStateProvider).value;
});

/// The signed-in user's INTERNAL database Guid (`Users.Id` on the backend) — never the Zitadel
/// OIDC `sub` claim `currentUserProvider.id` carries. Use this, not `currentUserProvider.id`,
/// anywhere a value needs to match a row in the local `colleagues`/`users` mirror or a
/// server-side foreign key expecting the real user Guid (report author/staff rows, cantiere crew
/// lookups, per-technician resource lookups like the assigned van). `currentUserProvider` is
/// still the right choice for "is anyone signed in" / route guards / anything reading the OIDC
/// token itself.
///
/// Persisted by `EntitlementService.refresh()` from `/api/Auth/me`'s `user.id` field — see that
/// method's doc comment for why entitlement refresh, not a dedicated endpoint, is what populates
/// this. Null before the first successful refresh (fresh install, never online yet) or after
/// sign-out (`LoginNotifier.signOut` clears all of SharedPreferences, this key included).
final internalUserIdProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(internalUserIdPrefsKey);
});

// ── Login state notifier ───────────────────────────────────────────────────

/// Last email used to sign in on this device; sent as the OIDC `login_hint`. A plain preference,
/// never a token. (Same key the login screen used to prefill its email field.)
const lastLoginEmailPrefsKey = 'login.last_email';

/// State for the login screen.
class LoginState {
  const LoginState({this.isLoading = false, this.failure});

  final bool isLoading;
  final AuthFailure? failure;

  LoginState copyWith({bool? isLoading, AuthFailure? failure}) {
    return LoginState(
      isLoading: isLoading ?? this.isLoading,
      // Pass null explicitly to clear the failure.
      failure: failure,
    );
  }

  LoginState clearFailure() => LoginState(isLoading: isLoading);
}

/// Notifier that drives the login screen's loading + error state.
class LoginNotifier extends StateNotifier<LoginState> {
  LoginNotifier(this._repo, this._ref) : super(const LoginState());

  final IAuthRepository _repo;
  final Ref _ref;

  /// The one sign-in: the system browser at the identity service. [loginHint] comes from the last
  /// used email, kept in the same plain preference the login screen has always used (an editable
  /// convenience, never a token).
  Future<void> signIn() async {
    state = const LoginState(isLoading: true);
    final hint = await _readLastEmail();
    final result = hint == null
        ? await _repo.signIn()
        : await _repo.signIn(loginHint: hint);
    final user = result.user;
    // A successful sign-in lets the router tear the login screen (and this autoDispose notifier)
    // down before we get here; writing `state` then would throw.
    if (!mounted) {
      if (user != null) await _rememberEmail(user.email);
      return;
    }
    if (result.failure != null) {
      // Cancelled / offline / failed: the stored session, the cached identity and the queues were
      // not touched by the repository; the screen just shows a calm message.
      state = LoginState(failure: result.failure);
    } else {
      // Success — authStateProvider stream emits and router redirects.
      if (user != null) await _rememberEmail(user.email);
      if (mounted) state = const LoginState();
    }
  }

  Future<String?> _readLastEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(lastLoginEmailPrefsKey)?.trim();
      return (email == null || email.isEmpty) ? null : email;
    } catch (_) {
      // A preference that cannot be read is not worth blocking sign-in over.
      return null;
    }
  }

  Future<void> _rememberEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastLoginEmailPrefsKey, trimmed);
    } catch (_) {
      // The convenience of a prefill must never fail a sign-in.
    }
  }

  Future<void> signOut() async {
    // The CONSENTED ending: the logout dialog already told the technician how much unsent work
    // this discards (see `UnsentWorkCounter` / `logout_flow.dart`). The forced path goes through
    // the same `SessionEnder` but `endForced()`, which keeps the local data — a dead session is
    // not consent to lose a day's work (audit F1).
    await _ref.read(sessionEnderProvider).end();
    // `loginProvider` is autoDispose and nothing is listening to it on the sign-out path: the
    // ending itself is what tears the authenticated tree down, so this notifier is usually already
    // disposed by the time the await returns (the router has moved to the login screen, which
    // builds a fresh one). Writing `state` then throws "Tried to use LoginNotifier after dispose
    // was called" — and, in a test container, fails the sign-out itself for a state write nobody
    // would ever read. Everything that matters (the repository sign-out, the wipe, the zone reset)
    // already happened inside `end()`.
    if (!mounted) return;
    state = const LoginState();
  }

  void clearError() {
    state = state.clearFailure();
  }
}

final loginProvider =
    StateNotifierProvider.autoDispose<LoginNotifier, LoginState>((ref) {
      return LoginNotifier(ref.watch(authRepositoryProvider), ref);
    });
