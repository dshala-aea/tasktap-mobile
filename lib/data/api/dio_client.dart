import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info_provider.dart';
import '../../core/config/env.dart';
import '../../core/update/update_required_state.dart';
import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/auth_user.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../../presentation/providers/auth_providers.dart';
import '../sync/connectivity_provider.dart' show isOnlineProvider;
import 'app_version_interceptor.dart';

// ── Dio provider ───────────────────────────────────────────────────────────

/// Provides a configured [Dio] instance with:
/// - Base URL from [Env.apiBaseUrl]
/// - Authorization: Bearer {access_token} on every request
/// - 401 → silent token refresh → retry once → /login only if the refresh itself was refused
///   (not merely unreachable — see [AuthInterceptor.onError])
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  // Share the single repository instance so the interceptor sees the same
  // session (access token) that the login flow established.
  final authRepo = ref.watch(authRepositoryProvider);
  // `isOnline` is read lazily, only when a request is about to leave with an expired (or nearly
  // expired) access token: it gates the proactive refresh (see [AuthInterceptor.onRequest]).
  final interceptor = AuthInterceptor(
    dio: dio,
    authRepo: authRepo,
    isOnline: () => ref.read(isOnlineProvider),
  );
  // A forced sign-out is NOT a logout, and must not wipe like one: it fires after a long offline
  // period precisely while the queues are full of unsent work (audit F1). `endForced` drops only
  // the credentials and marks the local data's owner; `SessionRecoveryController` decides at the
  // next sign-in. Read through the provider rather than building the teardown here, so there is
  // one teardown class. `ref.read`, not `watch`: this runs long after the Dio instance was built,
  // and re-creating the client's interceptor on a dependency change is not something this
  // provider should do.
  interceptor.onForcedSignOut = () =>
      ref.read(sessionEnderProvider).endForced();
  dio.interceptors.add(interceptor);

  // Tell the server which build is calling (X-App-Version). Observation only: the version comes
  // from the cached PackageInfo read, and a failed read sends the request without it.
  dio.interceptors.add(
    AppVersionInterceptor(
      () async => (await ref.read(appInfoProvider.future)).displayVersion,
    ),
  );

  // Read the server's version gate (X-App-Update-Required header / 426 app_update_required) into
  // app-wide state. Observation only: errors still propagate so the queues keep their items.
  // Only this client is gated: the other Dio clients (notification_service, kiosk_api_client,
  // reachability) never send X-App-Version, and the server never blocks a request without it.
  dio.interceptors.add(
    AppUpdateGateInterceptor(
      onUpdateRequired: () =>
          ref.read(updateRequiredProvider.notifier).markRequired(),
      onUpdateAvailable: () =>
          ref.read(updateAvailableProvider.notifier).markAvailable(),
    ),
  );

  // What the network actually did, in debug builds only.
  //
  // A screen that shows no data looks the same whether the request 401'd, timed out, or was never
  // made — and the app has no way to tell you which. One line per request and per failure turns
  // "the API doesn't work on the phone" into a status code and a path.
  //
  // Method, path and status only: never headers (the bearer token is one) and never bodies (they
  // carry customer data, and logcat is readable by anything with the right permission on an older
  // Android). Stripped from release builds by the assert trick, so nothing reaches a technician's
  // device.
  assert(() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('→ ${options.method} ${options.uri.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '← ${response.statusCode} ${response.requestOptions.uri.path}',
          );
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint(
            '✗ ${error.type.name} ${error.response?.statusCode ?? ''} '
            '${error.requestOptions.uri} — ${error.message}',
          );
          handler.next(error);
        },
      ),
    );
    return true;
  }());

  return dio;
});

// ── Auth interceptor ───────────────────────────────────────────────────────

/// Dio interceptor that:
/// 1. Attaches the current JWT as `Authorization: Bearer <token>`.
/// 2. On 401: silently refreshes the token once, retries the request.
/// 3. If that refresh fails with anything other than a confirmed [SessionExpired] — a
///    [NetworkError] (Zitadel merely unreachable: a cold start racing the radio still
///    registering, a tunnel, airplane mode) or an [UnknownAuthError] (a malformed token
///    response, a JSON parsing hiccup, a Zitadel 5xx): leaves the session alone and lets this
///    one request fail. None of these are proof the refresh token itself is dead — the same
///    distinction [IAuthRepository]'s own offline-restore path already makes on cold start;
///    forcing sign-out here would silently undo it one layer up, requiring a fresh interactive
///    login (which itself needs network) on an ordinary transient glitch.
/// 4. Only a confirmed [SessionExpired] (the identity provider positively said `invalid_grant`)
///    calls [AuthInterceptor.onForcedSignOut] so the app can route to /login.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.authRepo,
    this.isOnline,
    this.preflightMargin = const Duration(seconds: 60),
  });

  /// `RequestOptions.extra` key marking a request as anonymous (no bearer, no refresh on 401).
  static const noAuthExtra = noAuthExtraKey;

  /// Set on a request whose proactive refresh already failed: carries that [AuthFailure] so the
  /// 401 that follows is judged on it instead of redeeming the refresh token a second time.
  static const _preflightFailureExtra = '_preflightRefreshFailure';

  /// Set on a request that went through the proactive refresh (never done twice for one request).
  static const _preflightDoneExtra = '_preflightDone';

  final Dio dio;
  final IAuthRepository authRepo;

  /// Whether the backend is reachable right now. Null means "unknown": no proactive refresh is ever
  /// attempted (the 401 path below still recovers). Offline it must stay false: nothing is
  /// attempted and nothing is prompted, the request just fails like any offline request.
  final bool Function()? isOnline;

  /// A request leaving with an access token that expires within this margin refreshes it first.
  final Duration preflightMargin;

  /// Observable — set this callback to react to forced sign-out. `dioProvider` points it at the
  /// shared [SessionEnder] (`sessionEnderProvider`), so the forced path ends the session exactly the
  /// way the logout button does; see [AuthInterceptor._endSession] for what happens when nothing
  /// set it.
  Future<void> Function()? onForcedSignOut;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Requests marked `extra: {'noAuth': true}` (the anonymous version-policy probe) never carry
    // the bearer token.
    if (options.extra[noAuthExtra] == true) return handler.next(options);
    final user = authRepo.currentUser;
    if (user != null && _needsPreflight(user, options)) {
      // Not awaited: the handler is completed when the refresh settles. Every path inside
      // completes it, so a request can never hang here.
      unawaited(_refreshThenSend(options, handler));
      return;
    }
    _attachBearer(options, user);
    handler.next(options);
  }

  void _attachBearer(RequestOptions options, AuthUser? user) {
    if (user != null) {
      options.headers['Authorization'] = 'Bearer ${user.accessToken}';
    }
  }

  /// True when this request would leave with an access token that is expired (or empty: the
  /// offline-restored session) or about to be, while the device is online and a refresh token
  /// exists. Sending it anyway would burn the first request, and a queue's retry budget with it,
  /// on a 401 that was predictable.
  bool _needsPreflight(AuthUser user, RequestOptions options) {
    if (options.extra['_retried'] == true || options.extra[_preflightDoneExtra] == true) {
      return false;
    }
    if (user.refreshToken.isEmpty) return false;
    final online = isOnline;
    if (online == null) return false;
    final soon = DateTime.now().toUtc().add(preflightMargin);
    final stale = user.accessToken.isEmpty || user.expiresAt.isBefore(soon);
    // Checked last: the connectivity read is only needed when the token is actually stale.
    return stale && online();
  }

  Future<void> _refreshThenSend(RequestOptions options, RequestInterceptorHandler handler) async {
    options.extra[_preflightDoneExtra] = true;
    try {
      // Concurrent requests coalesce onto ONE token exchange inside the repository
      // (single-flight), so a flush of many calls costs one refresh.
      final result = await authRepo.refreshSession();
      if (result.user == null && result.failure != null) {
        options.extra[_preflightFailureExtra] = result.failure;
      }
    } catch (_) {
      // A refresh that throws is no reason to fail the request here: it goes out as it would
      // have without the proactive step and the 401 path decides.
    }
    _attachBearer(options, authRepo.currentUser);
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    // An anonymous request cannot say anything about the session: a 401 on it must never refresh
    // the token or end the session.
    if (err.requestOptions.extra[noAuthExtra] == true) return handler.next(err);

    // Only handle 401 Unauthorized — and only once (not on retry).
    if (response?.statusCode == 401 &&
        err.requestOptions.extra['_retried'] != true) {
      final refreshResult = await _refreshForRetry(err.requestOptions);

      if (refreshResult.user != null) {
        // Token refreshed — retry the original request.
        final options = err.requestOptions
          ..extra['_retried'] = true
          ..headers['Authorization'] =
              'Bearer ${refreshResult.user!.accessToken}';

        try {
          final retryResponse = await dio.fetch(options);
          return handler.resolve(retryResponse);
        } on DioException catch (retryErr) {
          return handler.next(retryErr);
        }
      } else if (refreshResult.failure is SessionExpired) {
        // The identity provider positively confirmed the refresh token is dead (invalid_grant) —
        // the only failure that means the session is actually gone (see
        // ZitadelAuthRepository._restore's identical narrowing). End the session and let the app
        // route to /login.
        await _endSession();
        return handler.next(err);
      } else {
        // NetworkError (Zitadel unreachable) or anything _mapError couldn't classify precisely
        // (UnknownAuthError — a malformed token response, a JSON parsing hiccup, a Zitadel 5xx
        // during refresh) — none of these are proof the refresh token itself is bad, only that
        // this one refresh attempt didn't work. Treating them as a real auth failure was forcing
        // a fresh interactive login (which itself needs network) on ordinary transient glitches —
        // exactly the offline lockout _restore() was written to prevent, just reintroduced one
        // layer up. Leave the session alone; this request fails for now, and the next request (or
        // AuthReconnectWatcher, once connectivity actually returns) gets a real chance to refresh.
        return handler.next(err);
      }
    }

    handler.next(err);
  }

  /// The session to retry a 401'd request with.
  ///
  /// Not always a new token exchange: if the proactive step already failed for this request its
  /// failure is reused, and if another caller has refreshed in the meantime (the bearer this request
  /// carried is no longer the current one) the current session is used as is. Either way the refresh
  /// token is redeemed at most once for a burst of failing requests.
  Future<({AuthUser? user, AuthFailure? failure})> _refreshForRetry(
    RequestOptions request,
  ) async {
    final earlier = request.extra[_preflightFailureExtra];
    if (earlier is AuthFailure) return (user: null, failure: earlier);

    final current = authRepo.currentUser;
    final sent = request.headers['Authorization'];
    if (current != null &&
        current.accessToken.isNotEmpty &&
        !current.isExpired &&
        sent != null &&
        sent != 'Bearer ${current.accessToken}') {
      return (user: current, failure: null);
    }
    return authRepo.refreshSession();
  }

  /// End the session after a confirmed [SessionExpired].
  ///
  /// The hook is the forced ending (`SessionEnder.endForced`: credentials dropped, local data
  /// and prefs kept, owner marked for the next sign-in); the local `signOut` is only the fallback
  /// for an interceptor nobody wired, which is the case in this file's own tests. The two agree on
  /// the part that matters here — neither wipes the local database, because this path can fire
  /// while unsent work is still queued. The wipe belongs to the consented logout path.
  ///
  /// Note this used to be documented as "leaves the signed-out user's rows on the device" and
  /// fixed by wiping there; that fix traded a tenant-isolation leak for data loss (audit F1). The
  /// leak is now closed at the *next sign-in* instead (`SessionRecoveryController`), where it can
  /// be done without destroying the queue.
  Future<void> _endSession() async {
    final hook = onForcedSignOut;
    if (hook != null) {
      await hook();
    } else {
      await authRepo.signOut();
    }
  }
}
