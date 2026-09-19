// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// CrashReporter — thin abstraction over the crash-reporting backend.
//
// Current implementation: Sentry (via sentry_flutter).
// Future swaps (e.g. Firebase Crashlytics) only need to re-implement this
// interface — callers don't change.
//
// Initialisation is guarded by the SENTRY_DSN dart-define so that unit tests
// and local runs without a DSN work normally (the no-op implementation is used).
// ══════════════════════════════════════════════════════════════════════════════

/// Crash-reporting abstraction.
///
/// Obtain the singleton via [CrashReporter.instance] after calling
/// [CrashReporter.init] in main().
abstract interface class CrashReporter {
  // ── Singleton access ───────────────────────────────────────────────────────

  static CrashReporter _instance = const _NoOpCrashReporter();

  /// The active [CrashReporter] implementation.
  /// Defaults to a no-op until [init] is called.
  static CrashReporter get instance => _instance;

  /// Replace the active implementation.
  /// Called once from main(); also useful in tests.
  static void setInstance(CrashReporter reporter) {
    _instance = reporter;
  }

  // ── API ───────────────────────────────────────────────────────────────────

  /// Capture an exception with an optional stack trace and context.
  Future<void> captureException(Object exception, {StackTrace? stackTrace, String? hint});

  /// Capture a non-fatal message.
  Future<void> captureMessage(String message);

  /// Add breadcrumb for better crash context.
  void addBreadcrumb(String message, {String? category});
}

// ── No-op implementation (default / tests / no DSN) ──────────────────────────

/// Used when SENTRY_DSN is absent. All methods are no-ops.
final class _NoOpCrashReporter implements CrashReporter {
  const _NoOpCrashReporter();

  @override
  Future<void> captureException(Object exception, {StackTrace? stackTrace, String? hint}) async {}

  @override
  Future<void> captureMessage(String message) async {}

  @override
  void addBreadcrumb(String message, {String? category}) {}
}
