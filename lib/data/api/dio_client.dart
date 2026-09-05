import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../domain/auth/auth_failure.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../../presentation/providers/auth_providers.dart';

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
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ),
  );

  // Share the single repository instance so the interceptor sees the same
  // session (access token) that the login flow established.
  final authRepo = ref.watch(authRepositoryProvider);
  dio.interceptors.add(AuthInterceptor(dio: dio, authRepo: authRepo));

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
          debugPrint('← ${response.statusCode} ${response.requestOptions.uri.path}');
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
  AuthInterceptor({required this.dio, required this.authRepo});

  final Dio dio;
  final IAuthRepository authRepo;

  /// Observable — set this callback to react to forced sign-out.
  void Function()? onForcedSignOut;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final user = authRepo.currentUser;
    if (user != null) {
      options.headers['Authorization'] = 'Bearer ${user.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;

    // Only handle 401 Unauthorized — and only once (not on retry).
    if (response?.statusCode == 401 && err.requestOptions.extra['_retried'] != true) {
      // Attempt silent refresh.
      final refreshResult = await authRepo.refreshSession();

      if (refreshResult.user != null) {
        // Token refreshed — retry the original request.
        final options = err.requestOptions
          ..extra['_retried'] = true
          ..headers['Authorization'] = 'Bearer ${refreshResult.user!.accessToken}';

        try {
          final retryResponse = await dio.fetch(options);
          return handler.resolve(retryResponse);
        } on DioException catch (retryErr) {
          return handler.next(retryErr);
        }
      } else if (refreshResult.failure is SessionExpired) {
        // The identity provider positively confirmed the refresh token is dead (invalid_grant) —
        // the only failure that means the session is actually gone (see
        // ZitadelAuthRepository._restore's identical narrowing). Force sign-out and navigate to
        // login.
        await authRepo.signOut();
        onForcedSignOut?.call();
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
}
