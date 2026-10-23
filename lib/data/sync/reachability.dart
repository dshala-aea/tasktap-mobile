// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// Reachability
//
// "Online" used to mean "the radio has a non-none interface", which is true on a captive portal,
// on Wi-Fi whose upstream is down, and on a hotel network nobody has paid for. Every freshness
// decision in the app was made on that answer, so the app would announce itself online and then
// fail every call it made — and, worse, [isOnlineProvider] would skip the offline fallbacks that
// exist for exactly that situation.
//
// This asks the backend instead: a tiny anonymous GET to `/health` (mapped in Program.cs, outside
// every tenant, entitlement and rate-limit path). It never throws — an unreachable backend is an
// answer, not an error — and it is cached for a few seconds so a screen that watches several
// providers does not turn one state into a burst of probes.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';

/// Whether the backend answers — not merely whether an interface is up.
abstract class ReachabilityProbe {
  /// True when the backend just answered its health endpoint (or did so within the cache window).
  /// Never throws.
  Future<bool> isReachable();
}

/// Probes `GET {API_BASE_URL}/health`.
///
/// A 2xx alone is not enough: a captive portal answers 200 with its own HTML on every address it
/// intercepts. The backend's payload is `{"status":"healthy"}`, so the body is checked too — it is
/// the only signal that distinguishes "the API answered" from "something intercepted the request".
class HealthEndpointProbe implements ReachabilityProbe {
  HealthEndpointProbe({Dio? dio, String? baseUrl, this.timeout = const Duration(seconds: 4)})
    : _baseUrl = baseUrl ?? Env.apiBaseUrl,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: timeout,
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          );

  final Dio _dio;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<bool> isReachable() async {
    if (_baseUrl.isEmpty) return false;
    try {
      final response = await _dio.get<dynamic>(
        '$_baseUrl/health',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          followRedirects: true,
          // Set on the request, not just the default client, so an injected Dio (tests, a shared
          // client) cannot turn a 5xx into a thrown DioException before the status check runs.
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return false;
      final data = response.data;
      return data is Map && data['status'] == 'healthy';
    } catch (_) {
      // No response, timeout, TLS failure, malformed body: all mean "the backend is not there".
      return false;
    }
  }
}

/// Remembers the last answer for [ttl] so callers can ask cheaply and often.
///
/// Both answers are cached. Caching only the positive one would let a dead network turn every
/// watched provider into its own probe; caching the negative one delays the switch back to online
/// by at most [ttl], and the caller re-asks on a timer.
class CachedReachabilityProbe implements ReachabilityProbe {
  CachedReachabilityProbe(
    this._inner, {
    this.ttl = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReachabilityProbe _inner;
  final Duration ttl;
  final DateTime Function() _clock;

  bool? _last;
  DateTime? _at;

  @override
  Future<bool> isReachable() async {
    final at = _at;
    if (_last != null && at != null && _clock().difference(at) < ttl) return _last!;
    final answer = await _inner.isReachable();
    _last = answer;
    _at = _clock();
    return answer;
  }
}

/// The app-wide probe. Tests override this with a fake; nothing else should construct one.
final reachabilityProbeProvider = Provider<ReachabilityProbe>((ref) {
  return CachedReachabilityProbe(HealthEndpointProbe());
});
