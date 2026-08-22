// dart format width=100
import 'package:dio/dio.dart';

import 'entitlement_repository.dart';

/// Refreshes the cached entitlement from the server.
///
/// Separate from [EntitlementRepository] so the fetch can fail without the cache noticing. Every
/// failure path here is a no-op on storage: the app keeps the last confirmed answer rather than
/// downgrading to "nothing granted" because a request timed out on a building site.
class EntitlementService {
  EntitlementService({required Dio dio, required EntitlementRepository repository})
    : _dio = dio,
      _repository = repository;

  final Dio _dio;
  final EntitlementRepository _repository;

  /// Pulls `/api/Auth/me` and caches what it says.
  ///
  /// Returns true when the cache was updated. Returns false — without touching the cache — on any
  /// network error, any non-200, or a body that does not carry the fields we need. A partial or
  /// unexpected body is treated as a failure rather than written through, because writing
  /// `features: []` from a malformed response would silently strip every module the tenant has.
  Future<bool> refresh() async {
    Response<Map<String, dynamic>> response;

    try {
      response = await _dio.get<Map<String, dynamic>>('/api/Auth/me');
    } on DioException {
      return false;
    }

    final body = response.data;
    if (response.statusCode != 200 || body == null) return false;

    final features = _stringList(body['features']);
    final capabilities = _stringList(body['capabilities']);
    final seatType = body['seatType'];
    final subscription = body['subscription'];
    final subscriptionStatus = subscription is Map ? subscription['status'] as String? : null;

    // `features` always carries at least the always-on modules when the server answers properly,
    // so an empty list means we did not get what we asked for.
    if (features == null || capabilities == null || seatType is! String || features.isEmpty) {
      return false;
    }

    await _repository.write(
      features: features,
      capabilities: capabilities,
      seatType: seatType,
      fetchedAt: DateTime.now().toUtc(),
      subscriptionStatus: subscriptionStatus,
    );

    return true;
  }

  /// Null rather than empty when the value is missing or the wrong shape — the caller treats null
  /// as "the server did not answer this", which must not overwrite a good cache.
  List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }
}
