// dart format width=100
import 'package:dio/dio.dart';

import 'app_version_interceptor.dart' show noAuthExtraKey;

/// The non-secret OIDC settings the policy endpoint carries (`auth` block). Every field is
/// nullable and unvalidated here: `AuthConfigSource` decides whether the block is usable.
class ServerAuthConfig {
  const ServerAuthConfig({this.issuer, this.clientId, this.redirectUri});

  final String? issuer;
  final String? clientId;
  final String? redirectUri;

  static ServerAuthConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    return ServerAuthConfig(
      issuer: AppVersionPolicy._text(json['issuer']),
      clientId: AppVersionPolicy._text(json['clientId']),
      redirectUri: AppVersionPolicy._text(json['redirectUri']),
    );
  }

  Map<String, dynamic> toJson() => {
    'issuer': issuer,
    'clientId': clientId,
    'redirectUri': redirectUri,
  };
}

/// The version policy the API serves for one platform. Every field is nullable: no value means
/// "no minimum" / "no recommendation" / "use the generic store page".
class AppVersionPolicy {
  const AppVersionPolicy({
    this.minimumVersion,
    this.recommendedVersion,
    this.storeUrl,
    this.message,
    this.auth,
  });

  final String? minimumVersion;
  final String? recommendedVersion;
  final String? storeUrl;
  final String? message;

  /// The server-provided OIDC settings; null when the response has none (or a cache written
  /// before this field existed).
  final ServerAuthConfig? auth;

  factory AppVersionPolicy.fromJson(Map<String, dynamic> json) => AppVersionPolicy(
    minimumVersion: _text(json['minimumVersion']),
    recommendedVersion: _text(json['recommendedVersion']),
    storeUrl: _text(json['storeUrl']),
    message: _text(json['message']),
    auth: ServerAuthConfig.fromJson(json['auth']),
  );

  Map<String, dynamic> toJson() => {
    'minimumVersion': minimumVersion,
    'recommendedVersion': recommendedVersion,
    'storeUrl': storeUrl,
    'message': message,
    'auth': auth?.toJson(),
  };

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

/// `GET /api/app/version-policy?platform=ios|android`. Anonymous: it is read before sign-in, so
/// it must not depend on a session. The `auth` block is kept on the model and cached with the policy.
class AppVersionPolicyApi {
  AppVersionPolicyApi(this._dio);

  final Dio _dio;

  /// Throws on any failure (network, non-200, malformed body); the repository treats every throw as
  /// "keep the cached policy".
  Future<AppVersionPolicy> fetch(String platform) async {
    final response = await _dio.get<Object?>(
      '/api/app/version-policy',
      queryParameters: {'platform': platform},
      // Launch/resume refresh: fail fast, it is background work and the cache covers a miss.
      // Anonymous: no bearer token is sent, and a 401 here must not refresh or end the session
      // (`AuthInterceptor` skips requests carrying the noAuth extra). No redirects are followed,
      // and only a 200 counts. The version/platform headers and the gate interceptor still apply.
      options: Options(
        extra: {noAuthExtraKey: true},
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status == 200,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final data = response.data;
    if (data is! Map) throw const FormatException('version-policy: unexpected body');
    return AppVersionPolicy.fromJson(Map<String, dynamic>.from(data));
  }
}
