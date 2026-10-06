import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crash_reporting/crash_reporter.dart';

/// Reports a cold-start failure that was survived (timeout, unreadable keychain, ...): always a
/// `debugPrint`, plus the active [CrashReporter] (no-op without a Sentry DSN). Never throws —
/// it runs inside the very error paths that keep the app from hanging on its first screen.
void reportStartupFailure(String what, Object error, StackTrace stackTrace) {
  debugPrint('$what: $error');
  try {
    unawaited(
      CrashReporter.instance
          .captureException(error, stackTrace: stackTrace, hint: what)
          .catchError((Object _) {}),
    );
  } catch (_) {
    // Reporting is best-effort.
  }
}
