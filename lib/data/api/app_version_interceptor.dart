import 'package:dio/dio.dart';

/// Header the API reads to learn which app build is calling it.
const appVersionHeader = 'X-App-Version';

/// Stamps every request with the app's own version (`1.0.11+42`).
///
/// The server had no way to tell which app build a request came from, so it could not know how
/// many phones still ran a version too old for a newer endpoint, and could not retire a legacy
/// one on data. This is only an observation channel: nothing here changes behaviour, and a
/// request goes out unchanged if the version cannot be read. A failure to read it must never
/// block a punch.
class AppVersionInterceptor extends Interceptor {
  AppVersionInterceptor(this._version);

  final Future<String?> Function() _version;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final v = await _version();
      if (v != null && v.isNotEmpty) options.headers[appVersionHeader] = v;
    } catch (_) {
      // Unreadable version: send without it.
    }
    handler.next(options);
  }
}
