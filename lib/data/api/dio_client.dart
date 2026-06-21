import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  final authRepo = SupabaseAuthRepository(Supabase.instance.client);
  dio.interceptors.add(AuthInterceptor(dio: dio, authRepo: authRepo));

  return dio;
});

// ── Auth interceptor ───────────────────────────────────────────────────────

/// Dio interceptor that:
/// 1. Attaches the current JWT as `Authorization: Bearer <token>`.
/// 2. On 401: silently refreshes the token once, retries the request.
/// 3. On second 401 (refresh failed): calls [AuthInterceptor.onForcedSignOut]
///    so the app can route to /login.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.authRepo,
  });

  final Dio dio;
  final IAuthRepository authRepo;

  /// Observable — set this callback to react to forced sign-out.
  void Function()? onForcedSignOut;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final user = authRepo.currentUser;
    if (user != null) {
      options.headers['Authorization'] = 'Bearer ${user.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    // Only handle 401 Unauthorized — and only once (not on retry).
    if (response?.statusCode == 401 &&
        err.requestOptions.extra['_retried'] != true) {
      // Attempt silent refresh.
      final refreshResult = await authRepo.refreshSession();

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
