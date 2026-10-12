import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// The teardown every "end this session" path runs — the logout button and the interceptor's forced
/// sign-out alike. See [SessionEnder] for why there is only one.
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
  return ref.watch(authStateProvider).valueOrNull;
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

  Future<void> signIn() async {
    state = const LoginState(isLoading: true);
    final result = await _repo.signIn();
    if (result.failure != null) {
      state = LoginState(failure: result.failure);
    } else {
      // Success — authStateProvider stream emits and router redirects.
      state = const LoginState();
    }
  }

  Future<void> signInWithPassword(String loginName, String password) async {
    state = const LoginState(isLoading: true);
    final result = await _repo.signInWithPassword(loginName, password);

    if (result.failure is AdditionalFactorRequired) {
      // The account needs more than a password — fall back to the browser flow, which can
      // satisfy MFA/passkey/whatever Zitadel's hosted UI supports. No error shown; this is a
      // transition, not a failure the technician needs to see or act on.
      await signIn();
      return;
    }

    if (result.failure != null) {
      state = LoginState(failure: result.failure);
    } else {
      state = const LoginState();
    }
  }

  Future<void> signOut() async {
    // One sequence, shared with the forced path — the interceptor ends a session through the same
    // `SessionEnder` (see `sessionEnderProvider`), because when this teardown lived here and a
    // narrower one lived there, a forced sign-out left the previous user's database and prefs on
    // the device.
    await _ref.read(sessionEnderProvider).end();
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
