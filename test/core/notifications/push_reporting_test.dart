// dart format width=100

// Push reporting: what a production handset tells us when a notification never arrives.
//
// The pipeline itself was instrumented for several releases and still shipped a fault nobody could
// see, because every failure ended in a `debugPrint` — which, on a TestFlight or App Store build,
// reaches no one. These pin the three properties that make the replacement useful:
//
//   * a failure is one event, tagged by stage and platform, so it groups and is findable;
//   * a recurring failure is one event per app run, not one per retry;
//   * reporting never makes a push failure worse (a broken backend cannot throw out of it), and a
//     token is never placed in an event.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/crash_reporting/crash_reporter.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/core/notifications/push_reporting.dart';

import '../../support/recording_crash_reporter.dart';

void main() {
  late RecordingCrashReporter reporter;
  late void Function() restore;

  setUp(() {
    reporter = RecordingCrashReporter();
    restore = useReporter(reporter);
    resetPushReporting();
  });

  tearDown(() {
    restore();
    resetPushReporting();
  });

  test('a failure is a PushFailure tagged by stage and platform', () {
    reportPushFailure(
      PushStage.deviceRegistration,
      StateError('POST /api/devices → HTTP 400'),
      tags: {'push.http_status': '400'},
    );

    final event = reporter.exceptions.single;
    expect(event.error, isA<PushFailure>());
    expect(event.error.toString(), startsWith('push/device-registration: '));
    expect(event.error.toString(), contains('HTTP 400'));
    expect(event.hint, 'push/device-registration');
    expect(event.tags, {
      'push.stage': 'device-registration',
      'push.platform': defaultTargetPlatform.name,
      'push.http_status': '400',
    });
    // An exception is what groups in the crash reporter; a message would not.
    expect(reporter.messages, isEmpty);
  });

  test('onceKey keeps a fault that recurs on every login to one event', () {
    reportPushFailure(PushStage.tokenFetch, 'no APNs token', onceKey: 'token-fetch-failed');
    reportPushFailure(PushStage.tokenFetch, 'no APNs token', onceKey: 'token-fetch-failed');
    expect(reporter.exceptions, hasLength(1));

    // A different key is a different fact, and is reported.
    reportPushFailure(PushStage.tokenFetch, 'timed out', onceKey: 'token-timeout');
    expect(reporter.exceptions, hasLength(2));

    // Without a key nothing is swallowed: the caller asked for every occurrence.
    reportPushFailure(PushStage.initialMessage, 'boom');
    reportPushFailure(PushStage.initialMessage, 'boom');
    expect(reporter.exceptions, hasLength(4));
  });

  test('a milestone is a message carrying the stage, never an exception', () {
    reportPushEvent(
      PushStage.deviceRegistration,
      'skipped: no FCM token yet',
      tags: {'push.authorization': 'authorized'},
      onceKey: 'skip:no FCM token yet',
    );
    reportPushEvent(
      PushStage.deviceRegistration,
      'skipped: no FCM token yet',
      onceKey: 'skip:no FCM token yet',
    );

    final event = reporter.messages.single;
    expect(event.message, 'push/device-registration: skipped: no FCM token yet');
    expect(event.tags?['push.stage'], 'device-registration');
    expect(event.tags?['push.authorization'], 'authorized');
    expect(reporter.exceptions, isEmpty);
  });

  test('breadcrumbs record the trail without becoming events', () {
    pushBreadcrumb('listeners wired');
    pushBreadcrumb('token issued', stage: PushStage.tokenFetch);

    expect(reporter.breadcrumbs, ['listeners wired', 'push/fcm-token: token issued']);
    expect(reporter.exceptions, isEmpty);
    expect(reporter.messages, isEmpty);
  });

  test('a broken reporting backend cannot throw out of a push failure', () {
    // Set directly rather than through addTearDown: the assertion is that nothing escapes, and a
    // teardown that ran in a different order than expected would hide a throw in this test.
    CrashReporter.setInstance(ThrowingCrashReporter());
    try {
      expect(
        () => reportPushFailure(PushStage.deviceRegistration, StateError('boom')),
        returnsNormally,
      );
      expect(
        () => reportPushEvent(PushStage.permission, 'denied'),
        returnsNormally,
      );
      expect(() => pushBreadcrumb('anything'), returnsNormally);
    } finally {
      CrashReporter.setInstance(reporter);
    }
  });

  test('a token is never reported in full', () {
    const token = 'cXk3Q2fJ8mN0pR5tV7yZ1aB4dE6gH9jL2nO8qS3uW5xY';

    final masked = maskToken(token);
    expect(masked, isNot(contains(token)));
    expect(masked, contains(token.substring(token.length - 6)));
    expect(masked, contains('len-${token.length}'));

    // Too short to tail-mask without revealing most of it.
    expect(maskToken('abc12345'), 'len-8');
    expect(maskToken(null), 'none');
  });

  // ── The three silent returns ────────────────────────────────────────────────
  //
  // `registerDeviceToken` used to return without a word when it had no token, which is the whole
  // reason an iPhone that granted permission after login never reached the backend. The reasons
  // are now one ordered list; the first one that applies is what the event says.
  group('registrationSkipReason', () {
    test('no FCM token wins: nothing else is actionable until a token exists', () {
      expect(
        NotificationService.registrationSkipReason(token: null, accessToken: '', apiBaseUrl: ''),
        'no FCM token yet',
      );
    });

    test('no access token', () {
      expect(
        NotificationService.registrationSkipReason(
          token: 'fcm',
          accessToken: '',
          apiBaseUrl: 'https://api.tasktap.io',
        ),
        'no access token',
      );
    });

    test('API_BASE_URL missing is a build fault and says so', () {
      expect(
        NotificationService.registrationSkipReason(
          token: 'fcm',
          accessToken: 'jwt',
          apiBaseUrl: '',
        ),
        'API_BASE_URL was not set at build time',
      );
    });

    test('nothing missing means the registration may proceed', () {
      expect(
        NotificationService.registrationSkipReason(
          token: 'fcm',
          accessToken: 'jwt',
          apiBaseUrl: 'https://api.tasktap.io',
        ),
        isNull,
      );
    });
  });
}
