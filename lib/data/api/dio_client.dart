import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../../presentation/providers/auth_providers.dart';

// ── Dio provider ───────────────────────────────────────────────────────────

/// Provides a configured [Dio] instance with:
/// - Base URL from [Env.apiBaseUrl]
/// - Authorization: Bearer {access_token} on every request
/// - 401 → silent token refresh → retry once → /login on second 401
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
/// 3. On second 401 (refresh failed): calls [AuthInterceptor.onForcedSignOut]
///    so the app can route to /login.
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
      } else {
        // Refresh failed — force sign-out and navigate to login.
        await authRepo.signOut();
        onForcedSignOut?.call();
        return handler.next(err);
      }
    }

    handler.next(err);
  }
}
