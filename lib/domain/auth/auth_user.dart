/// Immutable representation of an authenticated user in the domain layer.
///
/// This is intentionally decoupled from supabase_flutter's [User] type so
/// that the auth provider (Supabase, PIN, QR, …) can be swapped without
/// touching domain or presentation code.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Supabase / backend user UUID.
  final String id;

  /// User email address.
  final String email;

  /// Optional display name from user metadata.
  final String? displayName;

  /// JWT access token — attached to every API request.
  final String accessToken;

  /// Refresh token — used to renew the session silently.
  final String refreshToken;

  /// UTC expiry of the current access token.
  final DateTime expiresAt;

  /// Returns true when the access token has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  String toString() => 'AuthUser(id: $id, email: $email, expiresAt: $expiresAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          accessToken == other.accessToken;

  @override
  int get hashCode => Object.hash(id, accessToken);
}
