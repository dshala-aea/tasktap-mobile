// initializePush (lib/main.dart): the pre-runApp Firebase/notification bootstrap must be bounded,
// otherwise a hang means the first frame is never drawn.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/main.dart';

void main() {
  setUp(() => NotificationService.isAvailable = false);
  tearDown(() => NotificationService.isAvailable = false);

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
}
