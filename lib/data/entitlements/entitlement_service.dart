// dart format width=100
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entitlement_repository.dart';

/// SharedPreferences key for the signed-in user's INTERNAL database Guid (`User.Id` on the
/// backend), as opposed to `AuthUser.id` (the Zitadel OIDC `sub` claim — a large numeric string,
/// never a Guid). The two were conflated at several call sites (report-creation staff/author
/// fields, cantiere-lead checks, the van lookup) before this key existed: nothing anywhere on
/// device exposed the real internal id, so those call sites silently wrote the OIDC sub into
/// columns that must hold a Guid, matching nothing in the local `colleagues`/`users` mirror.
/// See `internalUserIdProvider` (auth_providers.dart) for the reading side.
const internalUserIdPrefsKey = 'internal_user_id';

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

    // The response's `user.id` is the backend's internal Users.Id (a Guid) — distinct from the
    // OIDC sub that AuthUser.id carries. Persisted separately (not through EntitlementRepository,
    // which is scoped to entitlement fields) so report-creation and every other "who am I,
    // internally" call site has a real value to read instead of falling back to the sub. Best
    // effort: a missing/malformed `user` object does not fail the whole refresh, since
    // entitlements themselves are still good.
    final user = body['user'];
    final internalUserId = user is Map ? user['id'] as String? : null;
    if (internalUserId != null && internalUserId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(internalUserIdPrefsKey, internalUserId);
    }

    return true;
  }

  /// Null rather than empty when the value is missing or the wrong shape — the caller treats null
  /// as "the server did not answer this", which must not overwrite a good cache.
  List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }
}
