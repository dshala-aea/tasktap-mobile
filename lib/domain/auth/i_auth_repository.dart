import 'auth_failure.dart';
import 'auth_user.dart';

/// Auth-method abstraction — the PIN/QR seam.
///
/// All auth flows (email/password TODAY; PIN / QR code FUTURE) implement
/// this interface. Riverpod providers and the presentation layer only depend
/// on this type, making provider swaps zero-cost.
///
/// Implementations:
/// - [ZitadelAuthRepository] — OIDC (Auth Code + PKCE) via flutter_appauth.
/// - Future: PinAuthRepository, QrAuthRepository.
abstract interface class IAuthRepository {
  // ── Session queries ────────────────────────────────────────────────────

  /// Returns the currently signed-in user, or null when unauthenticated.
  AuthUser? get currentUser;

  /// Stream that emits the current [AuthUser] (or null) whenever auth state
  /// changes — used by the Riverpod [authStateProvider] to drive route guards.
  Stream<AuthUser?> get authStateChanges;

  // ── Auth actions ───────────────────────────────────────────────────────

  /// Start the interactive sign-in flow (OIDC: opens the system browser for
  /// Authorization Code + PKCE). Credentials are entered at the identity
  /// provider, never in-app.
  ///
  /// Returns the signed-in [AuthUser] on success, or an [AuthFailure] on any
  /// error (network, cancelled, …).
  Future<({AuthUser? user, AuthFailure? failure})> signIn();

  /// Native in-app password sign-in — submits credentials directly instead of opening the
  /// system browser. See `ZitadelAuthRepository.signInWithPassword`'s own doc comment for the
  /// full flow and its fallback triggers.
  ///
  /// Returns the signed-in [AuthUser] on success. On failure, [AuthFailure] is
  /// [AdditionalFactorRequired] when the caller should fall back to [signIn] (the account needs
  /// more than a password), or any other [AuthFailure] when it should not (wrong credentials,
  /// network error, unexpected upstream error).
  Future<({AuthUser? user, AuthFailure? failure})> signInWithPassword(String loginName, String password);

  /// Silently refresh the session using the stored refresh token.
  ///
  /// Returns the refreshed [AuthUser] or an [AuthFailure].
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession();

  /// Sign out and clear the local session.
  Future<void> signOut();
}
