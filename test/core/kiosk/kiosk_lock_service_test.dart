// Tests for PlatformKioskLockService — the MethodChannel bridge to Android
// startLockTask()/stopLockTask() (lib/core/kiosk/kiosk_lock_service.dart).
//
// The native side is mocked via setMockMethodCallHandler, same technique as
// test/features/rapportino/steps/step_riepilogo_signature_test.dart. Platform.isAndroid can't be
// forced in a pure Dart test, so these tests exercise the channel plumbing directly (a call comes
// in, the right outcome comes out) rather than the Platform.isAndroid branch inside start()/stop()
// — that branch is exercised for real on-device, and its "no channel registered at all" fallback
// is covered by the MissingPluginException case below, which fires on every host platform.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/kiosk/kiosk_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tasktap/kiosk_lock');
  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('start() with no channel registered reads as unsupportedPlatform, not a crash', () async {
    // No handler installed at all — MissingPluginException path (a build/platform that predates
    // the channel, or a desktop test target).
    const service = PlatformKioskLockService(channel);

    final outcome = await service.start();

    expect(outcome, KioskLockOutcome.unsupportedPlatform);
  });

  test('isActive() with no channel registered reads as false, not a crash', () async {
    const service = PlatformKioskLockService(channel);

    expect(await service.isActive(), isFalse);
  });

  test('stop() with no channel registered completes without throwing', () async {
    const service = PlatformKioskLockService(channel);

    await expectLater(service.stop(), completes);
  });

  test(
    'a PlatformException from the native side never crashes start()/stop() (non-Android '
    'test host: exercises the keepScreenAwake/allowScreenSleep path both send through)',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      const service = PlatformKioskLockService(channel);

      expect(await service.start(), KioskLockOutcome.unsupportedPlatform);
      await expectLater(service.stop(), completes);
    },
  );

  test('isActive() is Android-only and reads false on every other platform, channel untouched', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    const service = PlatformKioskLockService(channel);

    expect(await service.isActive(), isFalse);
    expect(calls, 0, reason: 'isActive() short-circuits on !Platform.isAndroid before invoking the channel');
  });
}
