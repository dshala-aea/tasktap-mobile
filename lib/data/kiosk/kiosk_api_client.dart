import 'package:dio/dio.dart';

import '../../core/config/env.dart';

/// One rotating attendance token, as issued by `GET /api/WorkLog/kiosk/qr` (60s HMAC window —
/// see that action's doc comment on `WorkLogController`).
class KioskQrToken {
  const KioskQrToken({required this.token, required this.expiresInSeconds});

  final String token;
  final int expiresInSeconds;
}

/// Why a kiosk request failed.
///
/// [invalidOrRevoked] is the one outcome that must end kiosk mode on this device — a 401 here
/// means the backend no longer recognises this `X-Api-Key` at all, which happens both for a
/// mistyped/garbage key at activation time AND for a key the admin has since revoked from
/// `KioskDevicesListPage`. Every other reason is transient/unrelated and the caller should just
/// keep the device pinned and retry.
enum KioskApiFailureReason {
  /// 401 — key is garbage, or was valid and has since been revoked.
  invalidOrRevoked,

  /// 402 — tenant no longer holds the Kiosk module entitlement (`EntitlementMiddleware`).
  notEntitled,

  /// No usable response reached us at all (offline, DNS, timeout). The device stays pinned;
  /// this is exactly the kind of transient failure a tablet in a plant room hits routinely.
  network,

  /// Anything else (5xx, malformed body, ...).
  unknown,
}

class KioskApiException implements Exception {
  const KioskApiException(this.reason, [this.message]);

  final KioskApiFailureReason reason;
  final String? message;

  @override
  String toString() =>
      'KioskApiException($reason${message != null ? ': $message' : ''})';
}

/// Talks to the kiosk-only backend surface using the device's own `X-Api-Key` credential.
///
/// Deliberately a separate [Dio] from `dioProvider`: that one attaches the interactive user's
/// Zitadel bearer token and reacts to a 401 by refreshing it / forcing sign-out — neither applies
/// to a kiosk tablet, which authenticates as a machine (`ApiKeyAuthenticationHandler`, ADR-0011
/// §B.3) and is never signed in as a person at all. Mixing the two Dio instances would mean every
/// kiosk poll either fights the user auth interceptor or, on a device where nobody is signed in,
/// silently sends no `Authorization` header while still tripping its 401 handling.
class KioskApiClient {
  KioskApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  /// Fetches the current rotating QR token for the device identified by [rawKey].
  ///
  /// Also doubles as the activation-time credential check — a bad or revoked key surfaces the
  /// same [KioskApiFailureReason.invalidOrRevoked] either way, so the activation screen and the
  /// display screen's background poll share one error path.
  Future<KioskQrToken> fetchQr(String rawKey) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/WorkLog/kiosk/qr',
        options: Options(headers: {'X-Api-Key': rawKey}),
      );
      final data = response.data ?? const <String, dynamic>{};
      return KioskQrToken(
        token: data['token'] as String? ?? '',
        expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 60,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  KioskApiException _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401)
      return const KioskApiException(KioskApiFailureReason.invalidOrRevoked);
    if (status == 402)
      return const KioskApiException(KioskApiFailureReason.notEntitled);
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const KioskApiException(KioskApiFailureReason.network);
      default:
        return KioskApiException(KioskApiFailureReason.unknown, e.message);
    }
  }
}
