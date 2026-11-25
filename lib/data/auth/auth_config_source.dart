// dart format width=100
import '../../core/config/env.dart';
import '../../core/config/issuer_allowlist.dart';
import '../../core/update/app_version_policy_repository.dart';
import '../api/app_version_policy_api.dart';

export '../../core/config/issuer_allowlist.dart' show kAllowedIssuerHosts;

/// The OIDC settings one sign-in / refresh runs against. Non-secret by construction: a public
/// (PKCE) client has no secret, and nothing here is ever a token.
class AuthConfig {
  const AuthConfig({
    required this.issuer,
    required this.clientId,
    required this.redirectUri,
    this.fromServer = false,
  });

  /// The compile-time dart-defines (`OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_REDIRECT_URI`).
  static const compileTime = AuthConfig(
    issuer: Env.oidcIssuer,
    clientId: Env.oidcClientId,
    redirectUri: Env.oidcRedirectUri,
  );

  final String issuer;
  final String clientId;
  final String redirectUri;

  /// True when issuer and client id came from the cached server policy.
  final bool fromServer;

  /// Issuer in the form used to compare two issuers (trimmed, lowercase host, no trailing slashes).
  static String normalizeIssuer(String issuer) => normalizeIssuerString(issuer);
}

/// Where the app gets its OIDC issuer / client id / redirect URI from.
///
/// The server-provided block of the version policy (cached by [AppVersionPolicyStore], so it is
/// available offline) wins when it is usable; otherwise the compile-time dart-defines apply. That
/// lets the identity issuer move without a store release, while a build that never fetched a
/// policy (or fetched a malformed one) behaves exactly as before.
///
/// Rules:
/// - issuer must pass `validatedIssuer` (https, default port, no user-info/query/fragment, no IP
///   literal, host under the COMPILED allow-list [kAllowedIssuerHosts] + optional
///   `OIDC_ISSUER_ALLOWED_HOSTS` + the compile-time issuer's host: a poisoned policy cannot
///   redirect sign-in to another host), and clientId must be non-empty; otherwise the WHOLE block is ignored (issuer and client id are
///   never mixed between the server and the dart-defines).
/// - redirectUri: the native redirect scheme is registered at build time (AndroidManifest
///   `appAuthRedirectScheme`, Info.plist `CFBundleURLSchemes`), so a server-provided redirectUri is
///   honoured only when its scheme equals the compiled one; any other value is ignored and the
///   compiled redirect URI is used.
class AuthConfigSource {
  AuthConfigSource({
    Future<AppVersionPolicy?> Function()? readPolicy,
    this.compileTime = AuthConfig.compileTime,
    this.readTimeout = const Duration(seconds: 2),
    List<String>? extraHosts,
  }) : _extraHosts = extraHosts,
       _readPolicy = readPolicy ?? AppVersionPolicyStore().readPolicy {
    _current = compileTime;
  }

  /// The dart-define values, used when the server config is absent or invalid.
  final AuthConfig compileTime;
  final Future<AppVersionPolicy?> Function() _readPolicy;
  final List<String>? _extraHosts;

  /// A cache read slower than this counts as "no cache" (a stuck store must not block sign-in).
  final Duration readTimeout;

  late AuthConfig _current;

  /// The config as of the last [load]; the dart-defines until the first load completes.
  AuthConfig get current => _current;

  /// Re-reads the cached policy and returns the resulting config. Never throws and never touches
  /// the network, so it works offline.
  Future<AuthConfig> load() async {
    try {
      final policy = await _readPolicy().timeout(readTimeout);
      _current = resolve(policy?.auth);
    } catch (_) {
      _current = compileTime;
    }
    return _current;
  }

  /// Pure resolution of a server block against the dart-defines. Exposed for tests.
  AuthConfig resolve(ServerAuthConfig? server) {
    if (server == null) return compileTime;
    // Applied on every read as well as before caching: a block cached by an older build, or
    // tampered with on disk, is still checked.
    final issuer = validatedIssuer(
      server.issuer,
      compileTimeIssuer: compileTime.issuer,
      extraHosts: _extraHosts,
    );
    final clientId = server.clientId?.trim() ?? '';
    if (issuer == null || clientId.isEmpty) return compileTime;
    return AuthConfig(
      issuer: issuer,
      clientId: clientId,
      redirectUri: _redirectUri(server.redirectUri),
      fromServer: true,
    );
  }

  String _redirectUri(String? serverValue) {
    final candidate = serverValue?.trim() ?? '';
    if (candidate.isEmpty) return compileTime.redirectUri;
    final serverScheme = Uri.tryParse(candidate)?.scheme.toLowerCase() ?? '';
    final compiledScheme = Uri.tryParse(compileTime.redirectUri)?.scheme.toLowerCase() ?? '';
    if (serverScheme.isNotEmpty && serverScheme == compiledScheme) return candidate;
    return compileTime.redirectUri;
  }
}
