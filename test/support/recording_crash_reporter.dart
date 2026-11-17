// dart format width=100
// A [CrashReporter] that records what was sent, for tests that pin what a production build would
// actually report. Install with `CrashReporter.setInstance(...)`; the default no-op reporter is
// restored by handing back the instance you saved first.

import 'package:tasktap_mobile/core/crash_reporting/crash_reporter.dart';

/// One captured exception, as the tests want to look at it.
typedef CapturedException = ({
  Object error,
  String? hint,
  Map<String, String>? tags,
  StackTrace? stackTrace,
});

/// One captured message.
typedef CapturedMessage = ({String message, Map<String, String>? tags});

/// Records every call instead of sending it anywhere.
final class RecordingCrashReporter implements CrashReporter {
  final List<CapturedException> exceptions = [];
  final List<CapturedMessage> messages = [];
  final List<String> breadcrumbs = [];

  @override
  Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? hint,
    Map<String, String>? tags,
  }) async {
    exceptions.add((error: exception, hint: hint, tags: tags, stackTrace: stackTrace));
  }

  @override
  Future<void> captureMessage(String message, {Map<String, String>? tags}) async {
    messages.add((message: message, tags: tags));
  }

  @override
  void addBreadcrumb(String message, {String? category}) => breadcrumbs.add(message);
}

/// A reporter whose backend is broken — every call throws.
///
/// The real one can too (Sentry uninitialised, transport down), and none of the reporting call
/// sites may turn a crash-report failure into a push failure.
final class ThrowingCrashReporter implements CrashReporter {
  @override
  Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? hint,
    Map<String, String>? tags,
  }) async => throw StateError('reporting backend down');

  @override
  Future<void> captureMessage(String message, {Map<String, String>? tags}) async =>
      throw StateError('reporting backend down');

  @override
  void addBreadcrumb(String message, {String? category}) =>
      throw StateError('reporting backend down');
}

/// Install [reporter] for the duration of one test, returning a callback that restores the
/// reporter that was active before.
void Function() useReporter(CrashReporter reporter) {
  final previous = CrashReporter.instance;
  CrashReporter.setInstance(reporter);
  return () => CrashReporter.setInstance(previous);
}
