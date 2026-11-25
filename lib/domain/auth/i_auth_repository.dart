import 'auth_failure.dart';
import 'auth_user.dart';

/// Auth-method abstraction — the PIN/QR seam.
///
/// All auth flows (system-browser OIDC TODAY; PIN / QR code FUTURE) implement
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

  /// The one interactive sign-in: the system browser (OIDC Authorization Code + PKCE, non-ephemeral
  /// so the identity service's own browser session is reused). Credentials are entered at the
  /// identity provider, never in-app.
  ///
  /// [loginHint] (the last used email, when known) pre-fills the identity provider's login page.
  ///
  /// Returns the signed-in [AuthUser] on success, or an [AuthFailure] on any error. Cancelling,
  /// being offline or any other failure is non-destructive: no stored session, cached identity or
  /// queued work is touched.
  Future<({AuthUser? user, AuthFailure? failure})> signIn({String? loginHint});

  /// Silently refresh the session using the stored refresh token.
  ///
  /// Returns the refreshed [AuthUser] or an [AuthFailure].
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession();

  /// Sign out and clear the local session.
  Future<void> signOut();
}
