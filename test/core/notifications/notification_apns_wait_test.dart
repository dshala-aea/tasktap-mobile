// The iOS first-run race: permission is granted, iOS starts registering with APNs, and the APNs
// device token arrives a second or few later. `getToken()` asked in that gap throws
// `[firebase_messaging/apns-token-not-set]` even though nothing is wrong. The fetch must wait for
// the APNs token (bounded) and retry once before it calls the token missing, and only a token that
// is STILL missing after the window is a reportable fault.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/crash_reporting/crash_reporter.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/core/notifications/push_reporting.dart';

import '../../support/recording_crash_reporter.dart';

Exception _apnsNotSet() => Exception(
  '[firebase_messaging/apns-token-not-set] APNS token has not been set yet. '
  'Please ensure the APNS token is available by calling `getAPNSToken()`.',
);

/// A delay that returns at once, counting the time it was asked to wait.
({Future<void> Function(Duration) delay, Duration Function() waited}) _fakeDelay() {
  var total = Duration.zero;
  return (
    delay: (d) async => total += d,
    waited: () => total,
  );
}

void main() {
  late RecordingCrashReporter reporter;
  late CrashReporter previous;

  setUp(() {
    previous = CrashReporter.instance;
    reporter = RecordingCrashReporter();
    CrashReporter.setInstance(reporter);
    resetPushReporting();
    NotificationService.lastError = null;
  });
  tearDown(() {
    CrashReporter.setInstance(previous);
    resetPushReporting();
    NotificationService.lastError = null;
  });

  group('waitForApnsToken', () {
    test('returns the token once it appears after N polls', () async {
      var reads = 0;
      final clock = _fakeDelay();
      final token = await NotificationService.waitForApnsToken(
        () async => ++reads >= 4 ? 'apns-abc' : null,
        timeout: const Duration(seconds: 10),
        interval: const Duration(milliseconds: 500),
        delay: clock.delay,
      );

      expect(token, 'apns-abc');
      expect(reads, 4);
      expect(clock.waited(), const Duration(milliseconds: 1500));
    });

    test('returns null after the timeout without sleeping real time', () async {
      var reads = 0;
      final clock = _fakeDelay();
      final token = await NotificationService.waitForApnsToken(
        () async {
          reads++;
          return null;
        },
        timeout: const Duration(seconds: 10),
        interval: const Duration(milliseconds: 500),
        delay: clock.delay,
      );

      expect(token, isNull);
      expect(clock.waited(), const Duration(seconds: 10));
      expect(reads, 21); // one immediate read + one per interval
    });

    test('a read that throws counts as "not yet", not as a failure', () async {
      var reads = 0;
      final token = await NotificationService.waitForApnsToken(
        () async {
          if (++reads < 3) throw StateError('channel hiccup');
          return 'apns-abc';
        },
        timeout: const Duration(seconds: 10),
        interval: const Duration(milliseconds: 500),
        delay: _fakeDelay().delay,
      );
      expect(token, 'apns-abc');
    });
  });

  group('fetchToken on iOS', () {
    test('apns-token-not-set, then the APNs token appears: retry succeeds, no error', () async {
      var getTokenCalls = 0;
      var apnsReads = 0;
      String? recorded;
      var pending = 0;
      Duration? resolvedAfter;

      final token = await NotificationService.fetchToken(
        () async {
          getTokenCalls++;
          if (getTokenCalls == 1) throw _apnsNotSet();
          return 'fcm-token-abc';
        },
        isIOS: true,
        readApnsToken: () async => ++apnsReads >= 3 ? 'apns-abc' : null,
        apnsWait: const Duration(seconds: 10),
        apnsPollInterval: const Duration(milliseconds: 500),
        delay: _fakeDelay().delay,
        onApnsPending: () => pending++,
        onApnsResolved: (waited) => resolvedAfter = waited,
        recordError: (m) => recorded = m,
      );

      expect(token, 'fcm-token-abc');
      expect(getTokenCalls, 2);
      expect(recorded, isNull);
      expect(pending, 1);
      expect(resolvedAfter, const Duration(seconds: 1));
    });

    test('a null first answer is waited on as well', () async {
      var getTokenCalls = 0;
      final token = await NotificationService.fetchToken(
        () async => ++getTokenCalls == 1 ? null : 'fcm-token-abc',
        isIOS: true,
        readApnsToken: () async => 'apns-abc',
        delay: _fakeDelay().delay,
      );
      expect(token, 'fcm-token-abc');
      expect(getTokenCalls, 2);
    });

    test('the token never appears: null, the cause recorded, getToken asked once', () async {
      var getTokenCalls = 0;
      String? recorded;
      final clock = _fakeDelay();

      final token = await NotificationService.fetchToken(
        () async {
          getTokenCalls++;
          throw _apnsNotSet();
        },
        isIOS: true,
        readApnsToken: () async => null,
        apnsWait: const Duration(seconds: 10),
        apnsPollInterval: const Duration(milliseconds: 500),
        delay: clock.delay,
        recordError: (m) => recorded = m,
      );

      expect(token, isNull);
      expect(getTokenCalls, 1);
      expect(recorded, contains('apns-token-not-set'));
      expect(clock.waited(), const Duration(seconds: 10));
    });

    test('a non-APNs error is not waited on and not retried', () async {
      var getTokenCalls = 0;
      var apnsReads = 0;
      String? recorded;

      final token = await NotificationService.fetchToken(
        () async {
          getTokenCalls++;
          throw Exception('[firebase_messaging/unknown] boom');
        },
        isIOS: true,
        readApnsToken: () async {
          apnsReads++;
          return null;
        },
        delay: _fakeDelay().delay,
        recordError: (m) => recorded = m,
      );

      expect(token, isNull);
      expect(getTokenCalls, 1);
      expect(apnsReads, 0);
      expect(recorded, contains('unknown'));
    });

    test('the retry runs once: a second failure is recorded, not looped', () async {
      var getTokenCalls = 0;
      String? recorded;
      final token = await NotificationService.fetchToken(
        () async {
          getTokenCalls++;
          throw _apnsNotSet();
        },
        isIOS: true,
        readApnsToken: () async => 'apns-abc',
        delay: _fakeDelay().delay,
        recordError: (m) => recorded = m,
      );
      expect(token, isNull);
      expect(getTokenCalls, 2);
      expect(recorded, contains('apns-token-not-set'));
    });
  });

  group('fetchToken off iOS', () {
    test('does not wait, does not retry', () async {
      var getTokenCalls = 0;
      var apnsReads = 0;
      final clock = _fakeDelay();
      final token = await NotificationService.fetchToken(
        () async {
          getTokenCalls++;
          throw _apnsNotSet();
        },
        isIOS: false,
        readApnsToken: () async {
          apnsReads++;
          return 'apns-abc';
        },
        delay: clock.delay,
      );
      expect(token, isNull);
      expect(getTokenCalls, 1);
      expect(apnsReads, 0);
      expect(clock.waited(), Duration.zero);
    });
  });

  group('fetchAndReportToken', () {
    test('a late APNs token is no failure: nothing reported, lastError null', () async {
      var calls = 0;
      final token = await NotificationService.fetchAndReportToken(
        () async {
          if (++calls == 1) throw _apnsNotSet();
          return 'fcm-token-abc';
        },
        isIOS: true,
        readApnsToken: () async => 'apns-abc',
        delay: _fakeDelay().delay,
      );

      expect(token, 'fcm-token-abc');
      expect(NotificationService.lastError, isNull);
      expect(reporter.exceptions, isEmpty);
      expect(reporter.breadcrumbs.join('\n'), contains('apns token pending, waiting'));
      expect(reporter.breadcrumbs.join('\n'), contains('token issued after waiting'));
    });

    test('still missing after the window: one failure, tagged apns absent', () async {
      final token = await NotificationService.fetchAndReportToken(
        () async => throw _apnsNotSet(),
        isIOS: true,
        readApnsToken: () async => null,
        delay: _fakeDelay().delay,
      );

      expect(token, isNull);
      expect(NotificationService.lastError, contains('apns-token-not-set'));
      final event = reporter.exceptions.single;
      expect(event.hint, 'push/fcm-token');
      expect(event.tags!['push.apns_token'], 'absent');
    });
  });
}
