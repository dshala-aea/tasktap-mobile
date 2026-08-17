import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/zitadel_auth_repository.dart';
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
  LoginNotifier(this._repo) : super(const LoginState());

  final IAuthRepository _repo;

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

  Future<void> signOut() async {
    await _repo.signOut();
    state = const LoginState();
  }

  void clearError() {
    state = state.clearFailure();
  }
}

final loginProvider = StateNotifierProvider.autoDispose<LoginNotifier, LoginState>((ref) {
  return LoginNotifier(ref.watch(authRepositoryProvider));
});
