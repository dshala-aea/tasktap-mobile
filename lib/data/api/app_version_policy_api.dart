// dart format width=100
import 'package:dio/dio.dart';

/// The version policy the API serves for one platform. Every field is nullable: no value means
/// "no minimum" / "no recommendation" / "use the generic store page".
class AppVersionPolicy {
  const AppVersionPolicy({this.minimumVersion, this.recommendedVersion, this.storeUrl, this.message});

  final String? minimumVersion;
  final String? recommendedVersion;
  final String? storeUrl;
  final String? message;

  factory AppVersionPolicy.fromJson(Map<String, dynamic> json) => AppVersionPolicy(
    minimumVersion: _text(json['minimumVersion']),
    recommendedVersion: _text(json['recommendedVersion']),
    storeUrl: _text(json['storeUrl']),
    message: _text(json['message']),
  );

  Map<String, dynamic> toJson() => {
    'minimumVersion': minimumVersion,
    'recommendedVersion': recommendedVersion,
    'storeUrl': storeUrl,
    'message': message,
  };

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

/// `GET /api/app/version-policy?platform=ios|android`. Anonymous: it is read before sign-in, so
/// it must not depend on a session. (The `auth` block of the response is not read here.)
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
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final data = response.data;
    if (data is! Map) throw const FormatException('version-policy: unexpected body');
    return AppVersionPolicy.fromJson(Map<String, dynamic>.from(data));
  }
}
