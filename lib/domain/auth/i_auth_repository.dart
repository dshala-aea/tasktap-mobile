import 'auth_failure.dart';
import 'auth_user.dart';

/// Auth-method abstraction — the PIN/QR seam.
///
/// All auth flows (email/password TODAY; PIN / QR code FUTURE) implement
/// this interface. Riverpod providers and the presentation layer only depend
/// on this type, making provider swaps zero-cost.
///
/// Implementations:
/// - [SupabaseAuthRepository] — email/password via supabase_flutter (M2).
/// - Future: PinAuthRepository, QrAuthRepository (not built in M2).
abstract interface class IAuthRepository {
  // ── Session queries ────────────────────────────────────────────────────

  /// Returns the currently signed-in user, or null when unauthenticated.
  AuthUser? get currentUser;

  /// Stream that emits the current [AuthUser] (or null) whenever auth state
  /// changes — used by the Riverpod [authStateProvider] to drive route guards.
  Stream<AuthUser?> get authStateChanges;

  // ── Auth actions ───────────────────────────────────────────────────────

  /// Sign in with email and password.
  ///
  /// Returns the signed-in [AuthUser] on success, or an [AuthFailure] on
  /// any error (network, bad credentials, account disabled, …).
  Future<({AuthUser? user, AuthFailure? failure})> signInWithEmailPassword({
    required String email,
    required String password,
  });

  /// Silently refresh the session using the stored refresh token.
  ///
  /// Returns the refreshed [AuthUser] or an [AuthFailure].
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession();

  /// Sign out and clear the local session.
  Future<void> signOut();
}
