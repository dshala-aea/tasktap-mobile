import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// What iOS said about APNs registration, as read from the native `AppDelegate`.
///
/// `getAPNSToken()` only says the token is absent; it cannot say WHY. The reason lives in
/// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`, which nothing in Dart can
/// see, so the AppDelegate records it and this class reads it back. Diagnostic only: it never
/// carries the token (only whether one arrived), and it never throws.
class ApnsDiagnostics {
  ApnsDiagnostics({
    Future<Object?> Function()? invokeStatus,
    bool? isIOS,
    this.timeout = const Duration(seconds: 1),
  }) : _invokeStatus = invokeStatus ?? _defaultInvoke,
       _isIOS = isIOS ?? Platform.isIOS;

  static const MethodChannel channel = MethodChannel('tasktap/push_diag');

  static Future<Object?> _defaultInvoke() =>
      channel.invokeMethod<Object?>('apnsStatus');

  final Future<Object?> Function() _invokeStatus;
  final bool _isIOS;
  final Duration timeout;

  /// The two Sentry tags. `push.apns_error` is the native error string, `none` when APNs reported
  /// no failure, `n/a` off iOS, `unknown` when the status could not be read.
  /// `push.apns_registered` is `true` / `false` / `unknown` (`n/a` off iOS).
  Future<Map<String, String>> tags() async {
    if (!_isIOS) {
      return const {'push.apns_error': 'n/a', 'push.apns_registered': 'n/a'};
    }
    try {
      final raw = await _invokeStatus().timeout(timeout);
      if (raw is! Map) return _unknown;
      final registered = raw['registered'];
      final error = raw['error'];
      return {
        'push.apns_error': error is String && error.isNotEmpty
            ? _cap(error)
            : 'none',
        'push.apns_registered': registered is bool ? '$registered' : 'unknown',
      };
    } catch (_) {
      return _unknown;
    }
  }

  static const Map<String, String> _unknown = {
    'push.apns_error': 'unknown',
    'push.apns_registered': 'unknown',
  };

  static String _cap(String s) => s.length > 200 ? s.substring(0, 200) : s;
}
