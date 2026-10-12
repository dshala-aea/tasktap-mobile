// initializePush (lib/main.dart): the pre-runApp Firebase/notification bootstrap must be bounded,
// otherwise a hang means the first frame is never drawn.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/main.dart';

void main() {
  setUp(() {
    NotificationService.isAvailable = false;
    NotificationService.lastError = null;
  });
  tearDown(() {
    NotificationService.isAvailable = false;
    NotificationService.lastError = null;
  });

  testWidgets('both steps succeed -> push available', (tester) async {
    await initializePush(initFirebase: () async {}, initNotifications: () async {});
    expect(NotificationService.isAvailable, isTrue);
  });

  testWidgets('Firebase init never completes -> returns after 5s, push disabled', (tester) async {
    var done = false;
    unawaited(
      initializePush(
        initFirebase: () => Completer<void>().future,
        initNotifications: () async {},
      ).then((_) => done = true),
    );

    await tester.pump(const Duration(seconds: 4));
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(done, isTrue);
    expect(NotificationService.isAvailable, isFalse);
  });

  testWidgets('notification init never completes -> returns after 5s, push disabled', (
    tester,
  ) async {
    var done = false;
    unawaited(
      initializePush(
        initFirebase: () async {},
        initNotifications: () => Completer<void>().future,
      ).then((_) => done = true),
    );

    await tester.pump(const Duration(seconds: 6));
    expect(done, isTrue);
    expect(NotificationService.isAvailable, isFalse);
  });

  testWidgets('a throwing step -> push disabled, no exception escapes', (tester) async {
    await initializePush(
      initFirebase: () async => throw StateError('no plist'),
      initNotifications: () async {},
    );
    expect(NotificationService.isAvailable, isFalse);
  });

  // ── The recorded cause ─────────────────────────────────────────────────────
  //
  // `isAvailable == false` is the same value whether Firebase could not start, the notification
  // layer threw or a step timed out, and on a TestFlight build the only other trace of which one
  // happened was a `debugPrint` nobody can read. These pin that the failure is named, because
  // Impostazioni now shows it to the technician and a wrong or missing name sends them the
  // wrong way.

  testWidgets('a Firebase failure is recorded and names its step', (tester) async {
    await initializePush(
      initFirebase: () async => throw StateError('no plist'),
      initNotifications: () async {},
    );

    expect(NotificationService.lastError, contains('Firebase'));
    expect(NotificationService.lastError, contains('no plist'));
  });

  testWidgets('a notification-init failure is named separately from a Firebase one', (tester) async {
    await initializePush(
      initFirebase: () async {},
      initNotifications: () async => throw StateError('apns-token-not-set'),
    );

    expect(NotificationService.lastError, contains('Notifiche'));
    expect(NotificationService.lastError, contains('apns-token-not-set'));
    expect(NotificationService.lastError, isNot(contains('Firebase')));
  });

  testWidgets('a timeout is recorded too, not just a throw', (tester) async {
    // `unawaited` + `tester.pump`, like the two timeout tests above: `testWidgets` runs in a
    // FakeAsync zone, so a real `.timeout()` never fires while this test simply awaits it.
    var done = false;
    unawaited(
      initializePush(
        initFirebase: () async {},
        initNotifications: () => Completer<void>().future,
        timeout: const Duration(milliseconds: 50),
      ).then((_) => done = true),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(done, isTrue);
    expect(NotificationService.isAvailable, isFalse);
    expect(NotificationService.lastError, contains('Notifiche'));
  });

  testWidgets('a successful bootstrap records no error', (tester) async {
    await initializePush(initFirebase: () async {}, initNotifications: () async {});

    expect(NotificationService.isAvailable, isTrue);
    expect(NotificationService.lastError, isNull);
  });
}
