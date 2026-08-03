import 'dart:async';
import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/env.dart';
import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_user.dart';
import '../../domain/auth/i_auth_repository.dart';

/// Zitadel OIDC implementation of [IAuthRepository].
///
/// Uses AppAuth (system browser, Authorization Code + PKCE) for interactive
/// sign-in and the refresh-token grant for silent renewal. The refresh token is
/// the only thing persisted (flutter_secure_storage); access/id tokens live in
/// memory and are re-minted from the refresh token on restart.
class ZitadelAuthRepository implements IAuthRepository {
  ZitadelAuthRepository({
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? storage,
    bool restore = true,
  })  : _appAuth = appAuth ?? FlutterAppAuth(),
        _storage = storage ?? const FlutterSecureStorage() {
    if (restore) unawaited(_restore());
  }

  static const _refreshTokenKey = 'tt.oidc.refresh_token';
  static const _scopes = ['openid', 'profile', 'email', 'offline_access'];

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  AuthUser? _current;

  // ── IAuthRepository ────────────────────────────────────────────────────

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<({AuthUser? user, AuthFailure? failure})> signIn() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          Env.oidcClientId,
          Env.oidcRedirectUri,
          issuer: Env.oidcIssuer,
          scopes: _scopes,
        ),
      );
      final user = _fromTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      if (user == null) {
        return (user: null, failure: const UnknownAuthError('No tokens returned'));
      }
      await _persistRefreshToken(result.refreshToken);
      _emit(user);
      return (user: user, failure: null);
    } catch (e) {
      return (user: null, failure: _mapError(e));
    }
  }

  @override
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession() async {
    final refreshToken = (_current?.refreshToken.isNotEmpty ?? false)
        ? _current!.refreshToken
        : await _storage.read(key: _refreshTokenKey);

    if (refreshToken == null || refreshToken.isEmpty) {
      return (user: null, failure: const SessionExpired());
    }

    try {
      final result = await _appAuth.token(
        TokenRequest(
          Env.oidcClientId,
          Env.oidcRedirectUri,
          issuer: Env.oidcIssuer,
          refreshToken: refreshToken,
          scopes: _scopes,
          grantType: 'refresh_token',
        ),
      );
      final user = _fromTokens(
        accessToken: result.accessToken,
        // Zitadel may rotate the refresh token; fall back to the one we sent.
        refreshToken: result.refreshToken ?? refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      if (user == null) {
        return (user: null, failure: const SessionExpired());
      }
      await _persistRefreshToken(user.refreshToken);
      _emit(user);
      return (user: user, failure: null);
    } catch (e) {
      return (user: null, failure: _mapError(e));
    }
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(key: _refreshTokenKey);
    _emit(null);
  }

  // ── internals ──────────────────────────────────────────────────────────

  /// On startup, mint a fresh session from the stored refresh token (if any).
  Future<void> _restore() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      _emit(null);
      return;
    }
    final result = await refreshSession();
    if (result.user == null) {
      await _storage.delete(key: _refreshTokenKey);
      _emit(null);
    }
  }

  Future<void> _persistRefreshToken(String? refreshToken) async {
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  void _emit(AuthUser? user) {
    _current = user;
    if (!_controller.isClosed) _controller.add(user);
  }

  AuthUser? _fromTokens({
    required String? accessToken,
    required String? refreshToken,
    required String? idToken,
    required DateTime? expiry,
  }) {
    if (accessToken == null || accessToken.isEmpty) return null;
    final claims = _decodeJwtClaims(idToken ?? accessToken);
    return AuthUser(
      id: claims['sub']?.toString() ?? '',
      email: claims['email']?.toString() ?? '',
      displayName: (claims['name'] ?? claims['preferred_username'])?.toString(),
      accessToken: accessToken,
      refreshToken: refreshToken ?? '',
      expiresAt:
          (expiry ?? DateTime.now().toUtc().add(const Duration(hours: 1))).toUtc(),
    );
  }

  /// Decodes a JWT payload without verifying the signature (the backend verifies
  /// via JWKS; here we only read identity claims for display/routing).
  Map<String, dynamic> _decodeJwtClaims(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return const {};
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      return map is Map<String, dynamic> ? map : const {};
    } catch (_) {
      return const {};
    }
  }

  AuthFailure _mapError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('cancel')) {
      // User dismissed the browser — not a real error; surface benignly.
      return const UnknownAuthError('Accesso annullato');
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('host')) {
      return const NetworkError();
    }
    if (msg.contains('invalid_grant') ||
        msg.contains('refresh') ||
        msg.contains('expired')) {
      return const SessionExpired();
    }
    return UnknownAuthError(e.toString());
  }
}
