import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/startup/startup_report.dart';
import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_user.dart';
import '../../domain/auth/i_auth_repository.dart';
import 'auth_config_source.dart';
import 'retained_owner.dart';

/// Zitadel OIDC implementation of [IAuthRepository].
///
/// Uses AppAuth (system browser, Authorization Code + PKCE) for interactive
/// sign-in and the refresh-token grant for silent renewal. The refresh token
/// and a small cached-identity snapshot (id/email/displayName — no tokens) are
/// the only things persisted (flutter_secure_storage); access/id tokens live
/// in memory and are re-minted from the refresh token on restart.
///
/// [signIn] is the ONLY interactive sign-in: the system browser (AppAuth, PKCE) at the issuer
/// from [AuthConfigSource]. There is no in-app password or passkey form; those endpoints stay on
/// the API only for builds that predate this flow.
///
/// Cold start is offline-tolerant by design: see [_restore].
class ZitadelAuthRepository implements IAuthRepository {
  ZitadelAuthRepository({
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? storage,
    Dio? revocationHttpClient,
    AuthConfigSource? configSource,
    bool restore = true,
  }) : _configSource = configSource ?? AuthConfigSource(),
       _appAuth = appAuth ?? FlutterAppAuth(),
       _storage = storage ?? const FlutterSecureStorage(),
       _revocationHttpClient = revocationHttpClient ?? Dio() {
    if (restore) unawaited(_restore());
  }

  static const _refreshTokenKey = 'tt.oidc.refresh_token';
  static const _cachedIdentityKey = 'tt.oidc.cached_identity';

  /// The issuer the stored refresh token was minted by. Absent on sessions stored before the issuer
  /// could change: those are read as the compile-time issuer (see [_issuerMismatch]).
  static const _issuerKey = 'tt.oidc.issuer';
  static const _scopes = ['openid', 'profile', 'email', 'offline_access'];

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;

  /// Issuer / client id / redirect URI, read fresh at every sign-in and refresh (the cached server
  /// config when valid, else the dart-defines; never a network call, so it works offline).
  final AuthConfigSource _configSource;

  /// Plain HTTP client for calls that must not go through `dioProvider`'s `AuthInterceptor`:
  /// revoking the refresh token at sign-out (see [_revokeRefreshToken]) and the issuer reachability
  /// probe. Neither needs a bearer token, and `AuthInterceptor`'s 401-retry-then-forced-signout
  /// logic is the wrong behavior for them.
  final Dio _revocationHttpClient;

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  AuthUser? _current;

  // ── IAuthRepository ────────────────────────────────────────────────────

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<({AuthUser? user, AuthFailure? failure})> signIn({String? loginHint}) async {
    try {
      final cfg = await _configSource.load();
      final hint = loginHint?.trim();
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          cfg.clientId,
          cfg.redirectUri,
          issuer: cfg.issuer,
          scopes: _scopes,
          loginHint: (hint == null || hint.isEmpty) ? null : hint,
          // Not ephemeral: the browser session is shared with the identity service (suite SSO,
          // passkey autofill). `asWebAuthenticationSession` is the non-ephemeral agent.
          externalUserAgent: ExternalUserAgent.asWebAuthenticationSession,
        ),
      );
      final user = _fromTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      if (user == null) {
        return (
          user: null,
          failure: const UnknownAuthError('No tokens returned'),
        );
      }
      await _persistRefreshToken(result.refreshToken, cfg.issuer);
      await _persistCachedIdentity(user);
      _emit(user);
      return (user: user, failure: null);
    } catch (e) {
      // Nothing was written before this point, so a cancelled / offline / failed attempt leaves any
      // stored session, the cached identity and every queue exactly as they were.
      return (user: null, failure: _mapSignInError(e));
    }
  }

  /// A failed interactive sign-in is never a statement about a stored session: it maps to calm,
  /// non-destructive values (cancel, offline, or a generic retry), never to [SessionExpired].
  AuthFailure _mapSignInError(Object e) {
    if (e is FlutterAppAuthUserCancelledException) return const SignInCancelled();
    final mapped = _mapError(e);
    if (mapped is SessionExpired || mapped is UnknownAuthError) {
      // Neither says anything about a session, and the raw text of a native SDK error is no help
      // to a technician: a short fixed reason, the detail goes to the debug log only.
      debugPrint('Browser sign-in failed: $e');
      return const UnknownAuthError('accesso non riuscito, riprova');
    }
    return mapped;
  }

  /// The in-flight refresh, if any — shared by every concurrent caller instead of each starting
  /// its own token exchange. See [refreshSession] for why this matters.
  Future<({AuthUser? user, AuthFailure? failure})>? _inFlightRefresh;

  @override
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession() {
    // Single-flight guard: on reconnect, ~10 independent watchers (home_shell.dart) each fire an
    // API call at once. If the access token expired while offline, every one of those requests
    // 401s and — without this guard — each independently called this method, all redeeming the
    // SAME refresh token concurrently. Zitadel rotates refresh tokens on use, so only one of those
    // concurrent redemptions can actually succeed; the rest come back as an ambiguous failure that
    // `_mapError` cannot always classify as a clean `SessionExpired` (see its own doc comment), so
    // `AuthInterceptor` never signs the user out and the session is left permanently 401ing with no
    // redirect to `/login`. Coalescing concurrent callers onto ONE exchange removes the race
    // entirely — there is never more than one redemption of a given refresh token at a time.
    return _inFlightRefresh ??= _doRefreshSession().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<({AuthUser? user, AuthFailure? failure})> _doRefreshSession() async {
    final refreshToken = (_current?.refreshToken.isNotEmpty ?? false)
        ? _current!.refreshToken
        : await _storage.read(key: _refreshTokenKey);

    if (refreshToken == null || refreshToken.isEmpty) {
      return (user: null, failure: const SessionExpired());
    }

    final cfg = await _configSource.load();

    // A refresh token is only good at the issuer that minted it. If the issuer moved (server
    // config), never present it to the new one and never keep using the old session: the user
    // signs in again. Local data is untouched either way (see [_issuerMismatch]).
    if (await _issuerMismatch(cfg)) {
      // Offline, a changed config alone must not sign anybody out: only demand the re-login once
      // the new issuer actually answers (we could not sign in there otherwise). Until then the
      // session stays as the cached/offline one and the reconnect watcher retries.
      if (!await _issuerReachable(cfg.issuer)) return (user: null, failure: const NetworkError());
      return (user: null, failure: const SessionExpired());
    }

    try {
      final result = await _appAuth
          .token(
            TokenRequest(
              cfg.clientId,
              cfg.redirectUri,
              issuer: cfg.issuer,
              refreshToken: refreshToken,
              scopes: _scopes,
              grantType: 'refresh_token',
            ),
          )
          .timeout(_refreshTimeout);
      final fresh = _fromTokens(
        accessToken: result.accessToken,
        // Zitadel may rotate the refresh token; fall back to the one we sent.
        refreshToken: result.refreshToken ?? refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      if (fresh == null) {
        return (user: null, failure: const SessionExpired());
      }
      // A refresh response does not always carry an id_token, and the access token may be opaque:
      // the claims then decode to nothing and the user comes back with an EMPTY id. Keep the
      // identity we already know instead (in memory, else the cached one).
      final inMemory = _current;
      final known = (inMemory != null && inMemory.id.isNotEmpty)
          ? inMemory
          : _cachedAsUser(await _readCachedIdentity().catchError((_) => null));
      final user = withKnownIdentity(fresh, known);
      await _persistRefreshToken(user.refreshToken, cfg.issuer);
      await _persistCachedIdentity(user);
      _emit(user);
      return (user: user, failure: null);
    } on TimeoutException {
      // The native call hung. NetworkError, never SessionExpired: a hang says nothing about the
      // refresh token, so callers keep it. Returning here also completes the future behind
      // `_inFlightRefresh`, which frees the single-flight slot — without this bound a hung
      // native call kept every later refreshSession() caller coalesced onto a dead future.
      return (user: null, failure: const NetworkError());
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
    await _deleteIssuer();
    _emit(null);
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
      // Only revoke at the issuer (and with the client id) that minted the token. After an issuer
      // move the stored token belongs to another issuer: skip rather than send it, with a client id
      // from the new config, to the wrong place.
      final cfg = await _configSource.load();
      if (await _issuerMismatch(cfg)) return;
      final issuer = cfg.issuer;
      await _revocationHttpClient.post<void>(
        '$issuer/oauth/v2/revoke',
        data: <String, dynamic>{
          'token': refreshToken,
          'token_type_hint': 'refresh_token',
          'client_id': cfg.clientId,
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
      debugPrint(
        'Zitadel refresh-token revocation failed (best-effort, sign-out continues): $e',
      );
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
  ///
  /// HARDENING (App Store rejection of build 1.0 (50): stuck on the splash screen): this runs
  /// unawaited from the constructor and `authStateProvider` stays `AsyncLoading` until it emits,
  /// so it MUST always emit something. The whole body is therefore guarded: keychain reads are
  /// bounded by [_storageTimeout], the native refresh by [_refreshTimeout]. A refresh timeout is
  /// treated exactly like a [NetworkError] (cached-identity fallback, else signed out). A
  /// keychain read failure/timeout emits null (login) and deletes NOTHING — an unreadable
  /// keychain says nothing about the token's validity.
  ///
  /// A native refresh that finishes after its timeout is discarded (the await is abandoned, the
  /// single-flight slot is freed); the cached/offline user stays and [AuthReconnectWatcher] / the
  /// 401 path perform the real refresh later. No double emit.
  ///
  /// Honest caveat to "only [SessionExpired] wipes the token": when this very first restore never
  /// completes (timeout/NetworkError) AND there is no cached identity to fall back to (the first
  /// restore after install never finished), the code below still falls through to the sign-out
  /// path and deletes the stored token. That is pre-existing [NetworkError] behaviour, kept as is.
  ///
  /// The native call is itself bounded inside [_doRefreshSession] (which also frees the
  /// single-flight slot); the [_refreshTimeout] wait below is kept only as a backstop for the
  /// non-native steps of [refreshSession] (keychain read/writes).
  Future<void> _restore() async {
    try {
      await _restoreUnguarded();
    } catch (e, st) {
      reportStartupFailure(
        'Auth session restore failed (signing out locally)',
        e,
        st,
      );
      // Nothing was emitted yet (every emit below returns right after) -> unblock the router.
      if (_current == null) _emit(null);
    }
  }

  static const _storageTimeout = Duration(seconds: 5);

  /// ONE bound for "a refresh must finish": used on the native `_appAuth.token` call and as the
  /// restore backstop.
  static const _refreshTimeout = Duration(seconds: 12);

  Future<void> _restoreUnguarded() async {
    final refreshToken = await _storage
        .read(key: _refreshTokenKey)
        .timeout(_storageTimeout);
    if (refreshToken == null || refreshToken.isEmpty) {
      _emit(null);
      return;
    }

    // Issuer moved (server config): do NOT probe or decide here, that would hold the splash for
    // several seconds. Keep the cached identity exactly as for an unreachable provider; the next
    // refresh (reconnect watcher / 401 path) probes the new issuer and, if it answers, returns
    // SessionExpired. The stored token is never presented to the wrong issuer meanwhile
    // (`_doRefreshSession` checks again).
    final cfg = await _configSource.load();
    final ({AuthUser? user, AuthFailure? failure}) result;
    if (await _issuerMismatch(cfg)) {
      result = (user: null, failure: const NetworkError());
    } else {
      result = await refreshSession().timeout(
        _refreshTimeout,
        onTimeout: () => (user: null, failure: const NetworkError()),
      );
    }
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

    // The credentials below are about to go while the local database stays — deliberately, because
    // a dead refresh token routinely turns up with the outboxes full (offline audit F1). Name its
    // owner FIRST, while the cached identity still exists: `SessionRecoveryController` gates the
    // next sign-in on that marker, and without it a different account on a shared device inherits
    // this one's tickets, customers and sync cursor with no prompt. The interceptor's forced path
    // does this through `SessionEnder.endForced`; a session that died while the app was closed
    // never reaches the interceptor, so this path has to do it too (`retained_owner.dart`).
    Map<String, dynamic>? identity;
    try {
      identity = await _readCachedIdentity();
    } catch (_) {
      // An unreadable keychain names nobody; the teardown still has to finish (the router is
      // waiting on an emit).
    }
    await recordRetainedOwner(identity?['id']?.toString());

    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _cachedIdentityKey);
    await _deleteIssuer();
    _emit(null);
  }

  /// Stores the refresh token together with the issuer that minted it. The two writes are not
  /// atomic; that fails closed: a crash between them leaves the old (or no) issuer next to the new
  /// token, which at worst reads as a mismatch and asks the user to sign in again.
  Future<void> _persistRefreshToken(String? refreshToken, String issuer) async {
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
      await _storage.write(key: _issuerKey, value: AuthConfig.normalizeIssuer(issuer));
    }
  }

  Future<void> _deleteIssuer() async {
    try {
      await _storage.delete(key: _issuerKey);
    } catch (_) {
      // Best-effort: a leftover issuer is only ever compared, never trusted as a credential.
    }
  }

  /// True when the stored session was minted by a different issuer than [cfg]'s. A session stored
  /// before the issuer was persisted has no stored value and is read as the compile-time issuer. An
  /// unreadable keychain says nothing, so it is never a mismatch.
  Future<bool> _issuerMismatch(AuthConfig cfg) async {
    final String? stored;
    try {
      stored = await _storage.read(key: _issuerKey).timeout(_storageTimeout);
    } catch (_) {
      return false;
    }
    final sessionIssuer = (stored == null || stored.isEmpty)
        ? _configSource.compileTime.issuer
        : stored;
    return AuthConfig.normalizeIssuer(sessionIssuer) != AuthConfig.normalizeIssuer(cfg.issuer);
  }

  /// Whether [issuer] answers at all (any HTTP status counts). Used only to tell "offline" from
  /// "online with a moved issuer"; never throws.
  Future<bool> _issuerReachable(String issuer) async {
    try {
      await _revocationHttpClient
          .get<void>(
            '${AuthConfig.normalizeIssuer(issuer)}/.well-known/openid-configuration',
            options: Options(
              validateStatus: (_) => true,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          )
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Persists identity claims only — never accessToken/idToken/refreshToken —
  /// so a cold-start-offline session has something to display without ever
  /// putting a bearer token on disk.
  Future<void> _persistCachedIdentity(AuthUser user) async {
    // Never overwrite a good cached identity with an id-less one: the cache is what an offline cold
    // start restores from, and an empty id there poisons every later start.
    if (user.id.isEmpty) return;
    final json = jsonEncode({
      'id': user.id,
      'email': user.email,
      'displayName': user.displayName,
    });
    await _storage.write(key: _cachedIdentityKey, value: json);
  }

  Future<Map<String, dynamic>?> _readCachedIdentity() async {
    final raw = await _storage
        .read(key: _cachedIdentityKey)
        .timeout(_storageTimeout);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  AuthUser? _cachedAsUser(Map<String, dynamic>? cached) {
    final id = cached?['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return AuthUser(
      id: id,
      email: cached?['email']?.toString() ?? '',
      displayName: cached?['displayName']?.toString(),
      accessToken: '',
      refreshToken: '',
      expiresAt: DateTime.now().toUtc(),
    );
  }

  /// [fresh] with the identity fields [known] supplies wherever the refresh response left them
  /// empty. Tokens always come from [fresh]. Exposed for tests.
  ///
  /// Why it matters beyond auth: the user id keys per-account local state, notably the
  /// "onboarding completed" flag. An empty id keys a flag that was never set, so the onboarding
  /// flow reappeared on cold start whenever the refresh response had no usable claims.
  @visibleForTesting
  static AuthUser withKnownIdentity(AuthUser fresh, AuthUser? known) {
    if (known == null || fresh.id.isNotEmpty) return fresh;
    return AuthUser(
      id: known.id,
      email: fresh.email.isNotEmpty ? fresh.email : known.email,
      displayName: fresh.displayName ?? known.displayName,
      accessToken: fresh.accessToken,
      refreshToken: fresh.refreshToken,
      expiresAt: fresh.expiresAt,
    );
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
      expiresAt:
          (expiry ?? DateTime.now().toUtc().add(const Duration(hours: 1)))
              .toUtc(),
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
      FlutterAppAuthPlatformException(:final platformErrorDetails) =>
        platformErrorDetails.error,
      FlutterAppAuthUserCancelledException(:final platformErrorDetails) =>
        platformErrorDetails.error,
      _ => null,
    };
    if (structuredError == FlutterAppAuthOAuthError.invalidGrant) {
      // The identity provider itself said the refresh token is dead — a positively confirmed
      // session failure, not a guess. This is the only structured signal _restore() trusts enough
      // to wipe the stored token.
      return const SessionExpired();
    }

    final msg = e.toString().toLowerCase();
    if (e is TimeoutException || msg.contains('timeout')) {
      // A hung provider call is an unreachable identity provider, not a dead refresh token.
      // Classifying it as SessionExpired (or as an unclassified error that callers might treat
      // as terminal) would sign the technician out on a slow network; keep the offline-first
      // fallback that _restore() and AuthInterceptor already implement.
      return const NetworkError();
    }
    if (msg.contains('cancel')) {
      // User dismissed the browser — not a real error; surface benignly.
      return const SignInCancelled();
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
