import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/env.dart';
import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_user.dart';
import '../../domain/auth/i_auth_repository.dart';
import 'pkce.dart';

/// Zitadel OIDC implementation of [IAuthRepository].
///
/// Uses AppAuth (system browser, Authorization Code + PKCE) for interactive
/// sign-in and the refresh-token grant for silent renewal. The refresh token
/// and a small cached-identity snapshot (id/email/displayName — no tokens) are
/// the only things persisted (flutter_secure_storage); access/id tokens live
/// in memory and are re-minted from the refresh token on restart.
///
/// [signInWithPassword] additionally drives a native in-app password flow: it captures an
/// `authRequestId` from Zitadel's authorize redirect, submits credentials to the TaskTap backend's
/// BFF endpoint, and exchanges the resulting authorization code for tokens via AppAuth — all
/// without ever opening the system browser.
///
/// Cold start is offline-tolerant by design: see [_restore].
class ZitadelAuthRepository implements IAuthRepository {
  ZitadelAuthRepository({
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? storage,
    Dio? revocationHttpClient,
    bool restore = true,
  }) : _appAuth = appAuth ?? FlutterAppAuth(),
       _storage = storage ?? const FlutterSecureStorage(),
       _revocationHttpClient = revocationHttpClient ?? Dio() {
    if (restore) unawaited(_restore());
  }

  static const _refreshTokenKey = 'tt.oidc.refresh_token';
  static const _cachedIdentityKey = 'tt.oidc.cached_identity';
  static const _scopes = ['openid', 'profile', 'email', 'offline_access'];

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;

  /// Plain HTTP client for calls that must not go through `dioProvider`'s `AuthInterceptor` —
  /// revoking the refresh token at sign-out (see [_revokeRefreshToken]), and the native-login
  /// BFF calls below ([signInWithPassword]). Revocation needs no bearer token; a login attempt
  /// has none yet to attach — either way, `AuthInterceptor`'s 401-retry-then-forced-signout logic
  /// is the wrong behavior for both, since neither is an authenticated-session request.
  final Dio _revocationHttpClient;

  final StreamController<AuthUser?> _controller = StreamController<AuthUser?>.broadcast();

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
      await _persistCachedIdentity(user);
      _emit(user);
      return (user: user, failure: null);
    } catch (e) {
      return (user: null, failure: _mapError(e));
    }
  }

  @override
  Future<({AuthUser? user, AuthFailure? failure})> signInWithPassword(
    String loginName,
    String password,
  ) async {
    final pkce = Pkce.generate();

    final String authRequestId;
    try {
      authRequestId = await _captureAuthRequestId(pkce.challenge);
    } catch (e) {
      // _captureAuthRequestId throws typed AuthFailure values (e.g. UnknownAuthError), not Dart
      // Exceptions — pass those straight through instead of re-mapping via _mapError, which does
      // `e.toString().toLowerCase()` and would turn a typed failure into a useless
      // "Instance of 'UnknownAuthError'" message (AuthFailure has no custom toString()).
      if (e is AuthFailure) return (user: null, failure: e);
      return (user: null, failure: _mapError(e));
    }

    final String code;
    try {
      final response = await _revocationHttpClient.post<dynamic>(
        '${Env.apiBaseUrl}/api/MobileAuth/login',
        data: {'authRequestId': authRequestId, 'loginName': loginName, 'password': password},
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = response.data;
      final rawCode = data is Map ? data['code'] : null;
      if (rawCode is! String || rawCode.isEmpty) {
        return (user: null, failure: const UnknownAuthError('Malformed login response'));
      }
      code = rawCode;
    } on DioException catch (e) {
      final rawResponseData = e.response?.data;
      final backendCode = rawResponseData is Map && rawResponseData['code'] is String
          ? rawResponseData['code'] as String
          : null;
      return (user: null, failure: switch (backendCode) {
        'additional_factor_required' => const AdditionalFactorRequired(),
        'invalid_credentials' => const InvalidCredentials(),
        _ => _mapError(e),
      });
    }

    try {
      final result = await _appAuth.token(
        TokenRequest(
          Env.oidcClientId,
          Env.oidcRedirectUri,
          issuer: Env.oidcIssuer,
          authorizationCode: code,
          codeVerifier: pkce.verifier,
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
      await _persistCachedIdentity(user);
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
      await _persistCachedIdentity(user);
      _emit(user);
      return (user: user, failure: null);
    } catch (e) {
      return (user: null, failure: _mapError(e));
    }
  }

  @override
  Future<void> signOut() async {
    // Best-effort, and BEFORE local state is cleared: the refresh token being revoked is the same
    // one about to be discarded below, and there is nothing left to send it with afterwards.
    await _revokeRefreshToken();
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _cachedIdentityKey);
    _emit(null);
  }

  // ── internals ──────────────────────────────────────────────────────────

  /// GETs the OAuth authorize endpoint with redirects disabled and reads the auth request id off
  /// the resulting 302's Location header — the same redirect [_appAuth]'s own `authorize()` would
  /// otherwise open a full browser to render. Never rendered here; only the header is read. The
  /// query parameter is named `authRequest` on this deployment's Zitadel Login V2 configuration,
  /// with `authRequestId` accepted as a fallback name — see the comment at the read site below.
  Future<String> _captureAuthRequestId(String codeChallenge) async {
    final uri = Uri.parse('${Env.oidcIssuer}/oauth/v2/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': Env.oidcClientId,
        'redirect_uri': Env.oidcRedirectUri,
        'scope': _scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    final response = await _revocationHttpClient.get<void>(
      uri.toString(),
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final location = response.headers.value('location');
    if (location == null) {
      throw const UnknownAuthError('No redirect from authorize endpoint');
    }
    // The deployed Zitadel instance's Login V2 configuration
    // (ZITADEL_OIDC_DEFAULTLOGINURLV2 in the backend's docker-compose.coolify.yml) names this
    // query parameter `authRequest`, not the `authRequestId` its docs/older versions use — read
    // that name first, falling back to `authRequestId` in case a differently configured
    // environment (or a future Zitadel version) reverts to it.
    final redirectParams = Uri.parse(location).queryParameters;
    final authRequestId = redirectParams['authRequest'] ?? redirectParams['authRequestId'];
    if (authRequestId == null || authRequestId.isEmpty) {
      throw const UnknownAuthError('No authRequestId in authorize redirect');
    }
    return authRequestId;
  }

  /// Revoke the current refresh token at Zitadel's OAuth revocation endpoint.
  ///
  /// `POST /api/auth/logout` on the TaskTap backend is client-side only (see the audit finding
  /// this closes) — no server-side token revocation exists there either, so without this a
  /// captured refresh token would keep minting new access tokens after a technician signs out on
  /// this device. Zitadel's revocation endpoint is the actual place that can invalidate it.
  ///
  /// `flutter_appauth` wraps AppAuth's authorization/token/end-session calls only; it exposes no
  /// revocation helper (verified against its published API — `EndSessionRequest` opens the IdP's
  /// *browser* logout page, which is a different flow with a different UX cost, not a silent
  /// revoke). So this sends the standard RFC 7009 request by hand: `POST {issuer}/oauth/v2/revoke`
  /// with `token` + `token_type_hint=refresh_token` + `client_id` — no client secret, matching
  /// every other call this repository makes to a public/PKCE-only client.
  ///
  /// Deliberately best-effort: offline, an unreachable IdP, or a revocation the server itself
  /// rejects must never block or fail the user-visible sign-out. The technician is leaving this
  /// device regardless, and [signOut] clears local state unconditionally right after this call
  /// returns — including when it throws.
  Future<void> _revokeRefreshToken() async {
    final refreshToken = _current?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return;

    try {
      await _revocationHttpClient.post<void>(
        '${Env.oidcIssuer}/oauth/v2/revoke',
        data: <String, dynamic>{
          'token': refreshToken,
          'token_type_hint': 'refresh_token',
          'client_id': Env.oidcClientId,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          // Any HTTP status is a completed, non-exceptional attempt as far as sign-out is
          // concerned — a 4xx from an already-expired/rotated token is not a reason to retry or
          // to treat this as failed in a way that would need surfacing.
          validateStatus: (_) => true,
        ),
      );
    } catch (e) {
      debugPrint('Zitadel refresh-token revocation failed (best-effort, sign-out continues): $e');
    }
  }

  /// On startup, mint a fresh session from the stored refresh token (if any).
  ///
  /// WHY only [SessionExpired] triggers sign-out (do not "simplify" this
  /// away): this app is offline-first — clocking in, viewing cached tickets,
  /// etc. all work with zero network. If a technician's phone reboots on a
  /// job site with no signal, [refreshSession] will fail here with a
  /// [NetworkError] (see [_mapError]) purely because Zitadel is unreachable —
  /// that says *nothing* about whether the stored refresh token is still
  /// good. The same is true of a whole family of native AppAuth SDK glitches
  /// (a server hiccup, a malformed token response, a JSON parsing failure)
  /// that [_mapError] cannot always name precisely — none of them are proof
  /// the refresh token itself is dead. Treating any of these the same as a
  /// real auth failure would wipe the token and bounce the user to /login,
  /// which needs an interactive OIDC browser round trip — which itself needs
  /// network. Net effect would be: no signal (or any transient glitch) on
  /// restart -> locked out of the entire app, including the purely local
  /// features that have nothing to do with the network at all.
  ///
  /// So anything short of a confirmed [SessionExpired] keeps the refresh
  /// token on disk and falls back to the last-known identity (cached
  /// alongside it, tokens never included) so the app can run
  /// signed-in-but-offline. [AuthReconnectWatcher] retries the real refresh
  /// the moment connectivity returns (via the existing
  /// `connectivityProvider.onReconnect` hook — see
  /// `lib/data/auth/auth_reconnect_watcher.dart`); the ordinary 401 → silent
  /// refresh path in `AuthInterceptor` also naturally retries it on the next
  /// API call. Only [SessionExpired] — which [_mapError] only returns when
  /// Zitadel has positively responded with the OAuth `invalid_grant` error
  /// code, i.e. the refresh token really is revoked/expired/dead — means the
  /// session is actually gone, and only then do we wipe the token and sign
  /// out.
  Future<void> _restore() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      _emit(null);
      return;
    }

    final result = await refreshSession();
    if (result.user != null) {
      // refreshSession() already persisted + emitted the fresh session.
      return;
    }

    if (result.failure is! SessionExpired) {
      final cached = await _readCachedIdentity();
      if (cached != null) {
        _emit(_offlineUserFrom(cached, refreshToken));
        return;
      }
      // No cached identity to fall back to (e.g. the very first restore
      // after install never completed) — nothing to show as signed-in, so
      // fall through to the normal sign-out path below.
    }

    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _cachedIdentityKey);
    _emit(null);
  }

  Future<void> _persistRefreshToken(String? refreshToken) async {
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  /// Persists identity claims only — never accessToken/idToken/refreshToken —
  /// so a cold-start-offline session has something to display without ever
  /// putting a bearer token on disk.
  Future<void> _persistCachedIdentity(AuthUser user) async {
    final json = jsonEncode({'id': user.id, 'email': user.email, 'displayName': user.displayName});
    await _storage.write(key: _cachedIdentityKey, value: json);
  }

  Future<Map<String, dynamic>?> _readCachedIdentity() async {
    final raw = await _storage.read(key: _cachedIdentityKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  /// Builds a signed-in-but-offline [AuthUser] from the cached identity and
  /// the still-stored refresh token. `accessToken` is deliberately empty —
  /// access tokens are never persisted — so `expiresAt` is set to "now"
  /// (already expired): nothing here pretends the access token is valid.
  /// Callers that need the API (via `AuthInterceptor`) will hit a 401 and
  /// trigger a real [refreshSession] once the network is actually back.
  AuthUser _offlineUserFrom(Map<String, dynamic> cached, String refreshToken) {
    return AuthUser(
      id: cached['id']?.toString() ?? '',
      email: cached['email']?.toString() ?? '',
      displayName: cached['displayName']?.toString(),
      accessToken: '',
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc(),
    );
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
      expiresAt: (expiry ?? DateTime.now().toUtc().add(const Duration(hours: 1))).toUtc(),
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
    // Prefer flutter_appauth's structured error over string-sniffing e.toString() when it's
    // available: `platformErrorDetails.error` is only ever populated from a real OAuth error
    // response from the identity provider (AuthorizationException's OAUTH_TOKEN_ERRORS category on
    // Android) — never from its GeneralErrors category (network/server/JSON/parsing glitches),
    // which leaves `error` null and only sets a free-text `errorDescription`. Sniffing that text for
    // keywords is exactly what let a native SDK hiccup get misclassified as SessionExpired before.
    final structuredError = switch (e) {
      FlutterAppAuthPlatformException(:final platformErrorDetails) => platformErrorDetails.error,
      FlutterAppAuthUserCancelledException(:final platformErrorDetails) => platformErrorDetails.error,
      _ => null,
    };
    if (structuredError == FlutterAppAuthOAuthError.invalidGrant) {
      // The identity provider itself said the refresh token is dead — a positively confirmed
      // session failure, not a guess. This is the only structured signal _restore() trusts enough
      // to wipe the stored token.
      return const SessionExpired();
    }

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
    if (msg.contains('invalid_grant') || msg.contains('refresh') || msg.contains('expired')) {
      return const SessionExpired();
    }
    return UnknownAuthError(e.toString());
  }
}
