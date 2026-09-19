// dart format width=100
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporter.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SentryCrashReporter
//
// Implements [CrashReporter] using the sentry_flutter SDK.
// Only instantiated when SENTRY_DSN is non-empty (see main.dart).
// ══════════════════════════════════════════════════════════════════════════════

/// Sentry-backed implementation of [CrashReporter].
final class SentryCrashReporter implements CrashReporter {
  const SentryCrashReporter();

  @override
  Future<void> captureException(Object exception, {StackTrace? stackTrace, String? hint}) async {
    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      hint: hint != null ? Hint.withMap({'message': hint}) : null,
    );
  }

  @override
  Future<void> captureMessage(String message) async {
    await Sentry.captureMessage(message);
  }

  @override
  void addBreadcrumb(String message, {String? category}) {
    Sentry.addBreadcrumb(Breadcrumb(message: message, category: category));
  }
}
