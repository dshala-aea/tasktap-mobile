import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_user.dart';
import '../../domain/auth/i_auth_repository.dart';

/// Supabase-backed implementation of [IAuthRepository].
///
/// Session persistence: supabase_flutter stores the session in
/// SharedPreferences / flutter_secure_storage automatically (depending on
/// the platform storage setting). The session is restored on app restart
/// even without a network connection (cached JWT).
///
/// Token refresh: supabase_flutter auto-refreshes the JWT before expiry.
/// We also expose [refreshSession] for the dio 401 interceptor.
class SupabaseAuthRepository implements IAuthRepository {
  SupabaseAuthRepository(this._client);

  final sb.SupabaseClient _client;

  sb.GoTrueClient get _auth => _client.auth;

  // ── IAuthRepository ────────────────────────────────────────────────────

  @override
  AuthUser? get currentUser {
    final session = _auth.currentSession;
    final user = _auth.currentUser;
    if (session == null || user == null) return null;
    return _mapToAuthUser(user, session);
  }

  @override
  Stream<AuthUser?> get authStateChanges {
    return _auth.onAuthStateChange.map((event) {
      final session = event.session;
      final user = session?.user;
      if (session == null || user == null) return null;
      return _mapToAuthUser(user, session);
    });
  }

  @override
  Future<({AuthUser? user, AuthFailure? failure})> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = response.session;
      final user = response.user;
      if (session == null || user == null) {
        return (user: null, failure: const InvalidCredentials());
      }
      return (user: _mapToAuthUser(user, session), failure: null);
    } on sb.AuthException catch (e) {
      return (user: null, failure: _mapAuthException(e));
    } catch (e) {
      return (
        user: null,
        failure: UnknownAuthError(e.toString()),
      );
    }
  }

  @override
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession() async {
    try {
      final response = await _auth.refreshSession();
      final session = response.session;
      final user = response.user;
      if (session == null || user == null) {
        return (user: null, failure: const SessionExpired());
      }
      return (user: _mapToAuthUser(user, session), failure: null);
    } on sb.AuthException catch (e) {
      return (user: null, failure: _mapAuthException(e));
    } catch (e) {
      return (
        user: null,
        failure: UnknownAuthError(e.toString()),
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── Private helpers ────────────────────────────────────────────────────

  AuthUser _mapToAuthUser(sb.User user, sb.Session session) {
    final meta = user.userMetadata;
    final displayName =
        meta?['full_name'] as String? ?? meta?['name'] as String?;
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      displayName: displayName,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
      expiresAt: session.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(
              session.expiresAt! * 1000,
              isUtc: true,
            )
          : DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  AuthFailure _mapAuthException(sb.AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials') ||
        msg.contains('wrong password') ||
        msg.contains('email not confirmed') ||
        // Supabase returns this generic message for bad creds
        msg.contains('invalid email or password')) {
      return const InvalidCredentials();
    }
    if (msg.contains('user not found') || msg.contains('no user found')) {
      return const EmailNotFound();
    }
    if (msg.contains('disabled') || msg.contains('banned')) {
      return const AccountDisabled();
    }
    if (msg.contains('rate limit') ||
        msg.contains('too many') ||
        msg.contains('exceeded')) {
      return const TooManyRequests();
    }
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('socket')) {
      return const NetworkError();
    }
    if (msg.contains('refresh') ||
        msg.contains('token') ||
        msg.contains('session')) {
      return const SessionExpired();
    }
    return UnknownAuthError(e.message);
  }
}
