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
  Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? hint,
    Map<String, String>? tags,
  }) async {
    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      hint: hint != null ? Hint.withMap({'message': hint}) : null,
      withScope: (scope) => _applyTags(scope, tags),
    );
  }

  @override
  Future<void> captureMessage(String message, {Map<String, String>? tags}) async {
    await Sentry.captureMessage(message, withScope: (scope) => _applyTags(scope, tags));
  }

  @override
  void addBreadcrumb(String message, {String? category}) {
    Sentry.addBreadcrumb(Breadcrumb(message: message, category: category));
  }

  /// Inside `withScope` Sentry hands out a disposable clone, so a tag set here is scoped to this
  /// one event and cannot leak onto the next capture.
  static Future<void> _applyTags(Scope scope, Map<String, String>? tags) async {
    if (tags == null) return;
    for (final entry in tags.entries) {
      await scope.setTag(entry.key, entry.value);
    }
  }
}
