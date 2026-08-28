import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';
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
    // Unregister this device's FCM token BEFORE signing out — the access token this call needs
    // is gone the moment signOut() completes, and a device that stays registered keeps receiving
    // push for an account no longer signed in on it. Mirrors the same guard/token-source
    // `_syncPushRegistration` already uses in impostazioni_provider.dart.
    if (NotificationService.isAvailable) {
      final token = _repo.currentUser?.accessToken;
      if (token != null && token.isNotEmpty) {
        await NotificationService.instance.unregisterDeviceToken(token);
      }
    }
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
