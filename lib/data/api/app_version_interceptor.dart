import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import '../../core/update/update_required_state.dart';

/// `RequestOptions.extra` key marking a request as anonymous: `AuthInterceptor` neither attaches the
/// bearer token nor reacts to a 401 on it. (Lives here, not in dio_client.dart, so the policy API can
/// use it without importing the provider graph.)
const noAuthExtraKey = 'noAuth';

/// Header the API reads to learn which app build is calling it.
const appVersionHeader = 'X-App-Version';

/// Header the API reads to learn which store the build came from (`ios` | `android`).
const appPlatformHeader = 'X-App-Platform';

/// Stamps every request with the app's own version (`1.0.11+42`).
///
/// The server had no way to tell which app build a request came from, so it could not know how
/// many phones still ran a version too old for a newer endpoint, and could not retire a legacy
/// one on data. This is only an observation channel: nothing here changes behaviour, and a
/// request goes out unchanged if the version cannot be read. A failure to read it must never
/// block a punch.
class AppVersionInterceptor extends Interceptor {
  /// [platform] is injectable for tests; by default it is read from the OS on first use.
  AppVersionInterceptor(this._version, {String? platform})
    : _platform = platform;

  final Future<String?> Function() _version;
  final String? _platform;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Platform first and on its own: it must go out even when the version cannot be read.
    try {
      options.headers[appPlatformHeader] =
          _platform ?? (Platform.isIOS ? 'ios' : 'android');
    } catch (_) {
      // Unknown platform: send without it (the server falls back to the default policy).
    }
    try {
      final v = await _version();
      if (v != null && v.isNotEmpty) options.headers[appVersionHeader] = v;
    } catch (_) {
      // Unreadable version: send without it.
    }
    handler.next(options);
  }
}

/// Reads the server's version-gate answer without changing it.
///
/// A success carrying `X-App-Update-Required: true` (an allow-listed queue-flush call) and a 426
/// `app_update_required` error both record the fact through the callbacks. Errors are never
/// swallowed or rewritten: the [DioException] still propagates so the queues see it and keep
/// their items (see [isUpdateRequiredError]).
class AppUpdateGateInterceptor extends Interceptor {
  AppUpdateGateInterceptor({
    required this.onUpdateRequired,
    this.onUpdateAvailable,
  });

  final void Function() onUpdateRequired;
  final void Function()? onUpdateAvailable;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    try {
      if (hasUpdateRequiredHeader(response)) onUpdateRequired();
      if (hasUpdateAvailableHeader(response)) onUpdateAvailable?.call();
    } catch (_) {
      // Observation only: never let it break a response.
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final response = err.response;
      if (isUpdateRequiredResponse(response)) {
        onUpdateRequired();
      } else if (response != null) {
        if (hasUpdateRequiredHeader(response)) onUpdateRequired();
        if (hasUpdateAvailableHeader(response)) onUpdateAvailable?.call();
      }
    } catch (_) {
      // Observation only.
    }
    handler.next(err);
  }
}
