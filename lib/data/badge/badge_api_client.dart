// ══════════════════════════════════════════════════════════════════════════════
// BadgeApiClient
//
// Thin Dio wrapper for the worker badge backend (tasktap-api PR #181):
//   GET  /api/badge/me                       — the caller's badge card with a freshly
//                                              rotated token (QR payload)
//   POST /api/cantieri/{cantiereId}/badge-scan — a team leader scanning a worker's badge;
//                                              body {token, clientScanId}, always 200 with
//                                              the outcome, rejected scans included
//
// Failure mapping (BadgeApiException):
//   409 {code:"badge_revoked"}  → isRevoked   (ConflictException → ErrorHandlingMiddleware
//   409 {code:"user_inactive"}  → isInactive   puts the custom code in the `code` field)
//   403 {error:"NotLead"}       → isNotLead   (BadgeController.Scan's anonymous body)
//   connection / timeout        → isOffline
// `code`, `error` and `type` are all read defensively, in that order, so a ProblemDetails-shaped
// body still maps.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import 'badge_models.dart';

/// A badge call that failed, with the server's machine code when it sent one.
class BadgeApiException implements Exception {
  const BadgeApiException({this.statusCode, this.code, required this.message, this.offline = false});

  final int? statusCode;

  /// The server's `code` (or `error`/`type`) field, e.g. `badge_revoked`, `user_inactive`, `NotLead`.
  final String? code;
  final String message;
  final bool offline;

  bool get isRevoked => statusCode == 409 && code == 'badge_revoked';
  bool get isInactive => statusCode == 409 && code == 'user_inactive';
  bool get isNotLead => statusCode == 403 && code == 'NotLead';
  bool get isOffline => offline;

  @override
  String toString() => 'BadgeApiException($statusCode, $code, $message)';
}

class BadgeApiClient {
  BadgeApiClient(this._dio);

  final Dio _dio;

  /// The caller's badge with a fresh token. Each call rotates the token.
  Future<BadgeCard> getMyBadge() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/badge/me');
      return BadgeCard.fromJson(r.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Scans [token] at [cantiereId]. [clientScanId] must be a fresh UUID v4 per attempt, reused
  /// only when retrying the same attempt.
  Future<BadgeScanOutcome> scan({
    required String cantiereId,
    required String token,
    required String clientScanId,
  }) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/api/cantieri/$cantiereId/badge-scan',
        data: {'token': token, 'clientScanId': clientScanId},
      );
      return BadgeScanOutcome.fromJson(r.data!);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static BadgeApiException _map(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) {
      final offline =
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      return BadgeApiException(message: e.message ?? 'Network error', offline: offline);
    }
    String? code;
    String? message;
    final data = e.response?.data;
    if (data is Map) {
      for (final k in const ['code', 'error', 'type']) {
        final v = data[k];
        if (v is String && v.isNotEmpty) {
          code = v;
          break;
        }
      }
      final m = data['message'] ?? data['detail'] ?? data['title'];
      if (m is String) message = m;
    }
    return BadgeApiException(
      statusCode: status,
      code: code,
      message: message ?? 'HTTP $status',
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final badgeApiClientProvider = Provider<BadgeApiClient>((ref) {
  return BadgeApiClient(ref.watch(dioProvider));
});
