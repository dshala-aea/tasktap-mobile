// dart format width=100
import 'dart:async';

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
  EntitlementService({
    required Dio dio,
    required EntitlementRepository repository,
    this.onTenantTimeZone,
    this.currentSessionId,
  }) : _dio = dio,
       _repository = repository;

  final Dio _dio;
  final EntitlementRepository _repository;

  /// Receives the raw `tenantTimeZone` of every successfully parsed `/auth/me` (null when the key
  /// is absent or not a string) so the receiver can adopt it or fall back to the default. Called
  /// only after the rest of the refresh succeeded; a throwing callback never fails the refresh.
  final FutureOr<void> Function(String? tenantTimeZone)? onTenantTimeZone;

  /// Identity of the signed-in session. When given, a response whose session differs from the one
  /// that issued the request (signed out, or another user signed in meanwhile) is not applied to
  /// anything: it belongs to the previous tenant (cache, internal user id and zone alike). With no
  /// guard supplied this is a no-op and behaviour is unchanged.
  final String? Function()? currentSessionId;

  /// Pulls `/api/Auth/me` and caches what it says.
  ///
  /// Returns true when the cache was updated. Returns false — without touching the cache — on any
  /// network error, any non-200, or a body that does not carry the fields we need. A partial or
  /// unexpected body is treated as a failure rather than written through, because writing
  /// `features: []` from a malformed response would silently strip every module the tenant has.
  Future<bool> refresh() async {
    Response<Map<String, dynamic>> response;
    final sessionAtRequest = currentSessionId?.call();

    try {
      response = await _dio.get<Map<String, dynamic>>('/api/Auth/me');
    } on DioException catch (e) {
      // The one deliberate exception to "every failure is a no-op": a 400 carrying the specific
      // structured code TenantMiddleware sends only when it positively resolved this sub to an
      // existing-but-inactive Users row — never for an unrelated 400 (missing tenant association
      // entirely), and never for a network error, timeout, or any other status. Anything less
      // specific than this exact code stays a transient failure, same as before.
      final body = e.response?.data;
      if (e.response?.statusCode == 400 && body is Map && body['code'] == 'AccountDeactivated') {
        await _repository.markAccountDeactivated();
        return true;
      }
      return false;
    }

    final body = response.data;
    if (response.statusCode != 200 || body == null) return false;

    final features = _stringList(body['features']);
    final capabilities = _stringList(body['capabilities']);
    final seatType = body['seatType'];
    final clockInMethod = body['clockInMethod'] as String?;
    final subscription = body['subscription'];
    final subscriptionStatus = subscription is Map ? subscription['status'] as String? : null;

    // `features` always carries at least the always-on modules when the server answers properly,
    // so an empty list means we did not get what we asked for.
    if (features == null || capabilities == null || seatType is! String || features.isEmpty) {
      return false;
    }

    // Nothing is persisted for a session that ended while the request was in flight.
    if (!_stillCurrent(sessionAtRequest)) return false;

    await _repository.write(
      features: features,
      capabilities: capabilities,
      seatType: seatType,
      fetchedAt: DateTime.now().toUtc(),
      subscriptionStatus: subscriptionStatus,
      clockInMethod: clockInMethod,
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
      if (!_stillCurrent(sessionAtRequest)) return false;
      await prefs.setString(internalUserIdPrefsKey, internalUserId);
    }

    await _applyTenantTimeZone(body['tenantTimeZone'], sessionAtRequest);

    return true;
  }

  /// True when the session that issued the request is still the signed-in one. Always true when
  /// no [currentSessionId] was supplied.
  bool _stillCurrent(String? sessionAtRequest) {
    final sessionNow = currentSessionId;
    if (sessionNow == null) return true;
    final now = sessionNow();
    return now != null && now == sessionAtRequest;
  }

  Future<void> _applyTenantTimeZone(Object? raw, String? sessionAtRequest) async {
    final callback = onTenantTimeZone;
    if (callback == null) return;
    try {
      if (!_stillCurrent(sessionAtRequest)) return;
      // Awaited so refresh() does not report success before the zone is persisted.
      await callback(raw is String ? raw : null);
    } catch (_) {
      // The zone is an enhancement of this refresh, never a reason to fail it.
    }
  }

  /// Null rather than empty when the value is missing or the wrong shape — the caller treats null
  /// as "the server did not answer this", which must not overwrite a good cache.
  List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }
}
