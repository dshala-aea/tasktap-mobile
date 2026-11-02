// NotificationService.fetchToken: the FCM token fetch, bounded and recorded.
//
// The case that matters is the Apple one. On iOS `getToken()` resolves only once APNs has
// registered the device, and on a misconfigured build (App ID without the Push capability, no
// APNs key on the Firebase project, a `development` aps-environment under a distribution profile)
// it does not throw — it HANGS. That hang used to be awaited by `initialize()`, which main.dart
// bounds at five seconds, so the whole bootstrap timed out, the listeners were never wired, and
// every surface reported push as unsupported on a handset that supports it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';

void main() {
  setUp(() {
    NotificationService.lastError = null;
  });
  tearDown(() {
    NotificationService.lastError = null;
  });

  testWidgets('returns the token the platform issues', (tester) async {
    String? recorded;
    final token = await NotificationService.fetchToken(
      () async => 'fcm-token-abc',
      recordError: (message) => recorded = message,
    );

    expect(token, 'fcm-token-abc');
    expect(recorded, isNull);
  });

  testWidgets('a platform that issues no token yet is null, not an error', (tester) async {
    String? recorded;
    final token = await NotificationService.fetchToken(
      () async => null,
      recordError: (message) => recorded = message,
    );

    expect(token, isNull);
    expect(recorded, isNull);
  });

  testWidgets('records and swallows a throwing getToken (apns-token-not-set)', (tester) async {
    String? recorded;
    final token = await NotificationService.fetchToken(
      () async => throw Exception('[firebase_messaging/apns-token-not-set]'),
      recordError: (message) => recorded = message,
    );

    expect(token, isNull);
    expect(recorded, startsWith('Token: '));
    expect(recorded, contains('apns-token-not-set'));
  });

  testWidgets('bounds a hanging getToken and names the timeout', (tester) async {
    String? recorded;
    String? token;
    var done = false;

    unawaited(
      NotificationService.fetchToken(
        () => Completer<String?>().future,
        timeout: const Duration(milliseconds: 50),
        recordError: (message) => recorded = message,
      ).then((value) {
        token = value;
        done = true;
      }),
    );

    // Still waiting just before the budget: a timeout that fired early would hide the slow-APNs
    // case as a plain failure.
    await tester.pump(const Duration(milliseconds: 40));
    expect(done, isFalse);

    await tester.pump(const Duration(milliseconds: 20));
    expect(done, isTrue);
    expect(token, isNull);
    expect(recorded, startsWith('Token: '));
    expect(recorded, contains('APNs'));
  });
}
