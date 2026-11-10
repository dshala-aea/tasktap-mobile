// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// Push reporting — the diagnostics half of the FCM/APNs pipeline.
//
// Every failure in this pipeline used to reach a `debugPrint` and nothing else, and a
// `debugPrint` on a TestFlight or App Store build is invisible: there is no console to read it
// on a technician's handset. That is how "iOS never receives a notification" survived several
// releases while every step of it was already instrumented on paper.
//
// Two kinds of event are sent:
//
//   * failures — a [PushFailure], tagged by [PushStage] so they group per stage and per platform
//     in Sentry (`push.stage:fcm-token`, `push.platform:iOS`);
//   * milestones — permission granted/denied, device registered, registration skipped and why.
//     Milestones matter because the absence of errors is not evidence of success here: a device
//     that never registered emits no error at all, and "no events from this handset" and
//     "registered but nothing delivered" are different incidents with different owners.
//
// Nothing here ever throws. Every call site is inside a path that must keep running.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crash_reporting/crash_reporter.dart';

/// Where in the push pipeline something happened.
///
/// The `slug` is sent as the `push.stage` tag, so it is part of the Sentry query surface — keep
/// it stable.
enum PushStage {
  firebaseInit('firebase-init'),
  messagingInit('messaging-init'),
  permission('permission'),
  tokenFetch('fcm-token'),
  deviceRegistration('device-registration'),
  deviceUnregistration('device-unregistration'),
  initialMessage('initial-message'),
  foregroundPresentation('foreground-presentation'),
  foregroundMessage('foreground-message');

  const PushStage(this.slug);

  final String slug;
}

/// The exception the reporting layer hands to the crash reporter for a push fault.
///
/// A dedicated type rather than the raw dio/plugin error: the original is kept verbatim in
/// [cause] and in [toString], but grouping keys on this type plus the stage, which is what makes
/// "is this the same iOS fault as last release" answerable.
class PushFailure implements Exception {
  PushFailure(this.stage, this.cause);

  final PushStage stage;
  final Object cause;

  @override
  String toString() => 'push/${stage.slug}: $cause';
}

/// Failures already reported in this run, so a fault that recurs on every login or reconnect does
/// not become a flood of identical events. Keyed by the caller's `onceKey`.
final Set<String> _reportedOnce = <String>{};

/// Forget the de-duplication state. Tests only.
@visibleForTesting
void resetPushReporting() => _reportedOnce.clear();

/// Report a push fault.
///
/// [tags] are added to `push.stage` and `push.platform`; when [onceKey] is given, only the first
/// occurrence in this app run is sent (the `debugPrint` always happens).
void reportPushFailure(
  PushStage stage,
  Object error, {
  StackTrace? stackTrace,
  Map<String, String>? tags,
  String? onceKey,
}) {
  debugPrint('push/${stage.slug} failed: $error');
  if (onceKey != null && !_reportedOnce.add('failure/$onceKey')) return;

  try {
    unawaited(
      CrashReporter.instance
          .captureException(
            PushFailure(stage, error),
            stackTrace: stackTrace,
            hint: 'push/${stage.slug}',
            tags: _tags(stage, tags),
          )
          .catchError((Object _) {}),
    );
  } catch (_) {
    // Reporting is best-effort: this runs inside the failure path it is describing.
  }
}

/// Report a push milestone that is not an exception.
///
/// Use it where "nothing happened" would otherwise be indistinguishable from "it worked": a
/// permission outcome, a registration that succeeded, a registration that was skipped because
/// there was no token to send. [onceKey] de-duplicates per app run exactly as above.
void reportPushEvent(
  PushStage stage,
  String message, {
  Map<String, String>? tags,
  String? onceKey,
}) {
  debugPrint('push/${stage.slug}: $message');
  if (onceKey != null && !_reportedOnce.add('event/$onceKey')) return;

  try {
    unawaited(
      CrashReporter.instance
          .captureMessage('push/${stage.slug}: $message', tags: _tags(stage, tags))
          .catchError((Object _) {}),
    );
  } catch (_) {
    // Reporting is best-effort.
  }
}

/// Add a trail entry for the events above: what the pipeline did, in order, attached to whatever
/// is captured later in the same session.
void pushBreadcrumb(String message, {PushStage? stage}) {
  debugPrint('push: $message');
  try {
    CrashReporter.instance.addBreadcrumb(
      stage == null ? message : 'push/${stage.slug}: $message',
      category: 'push',
    );
  } catch (_) {
    // Reporting is best-effort.
  }
}

/// A token as it may safely appear in a log line or a tag: never the credential itself.
///
/// The FCM token is a delivery capability — anyone holding it can push to the handset. The last
/// six characters are enough to tie an event to the row the backend has for the same device
/// without putting a usable token in a third-party service.
String maskToken(String? token) {
  if (token == null) return 'none';
  if (token.length <= 8) return 'len-${token.length}';
  return '…${token.substring(token.length - 6)} (len-${token.length})';
}

/// `push.stage`, `push.platform`, plus whatever the caller adds.
///
/// [defaultTargetPlatform] rather than `dart:io`'s `Platform`: this file is imported by code that
/// is also exercised in tests, and it keeps the tag vocabulary (`iOS`, `android`) identical to the
/// platform names the rest of the app already uses.
Map<String, String> _tags(PushStage stage, Map<String, String>? extra) => {
  'push.stage': stage.slug,
  'push.platform': defaultTargetPlatform.name,
  ...?extra,
};
