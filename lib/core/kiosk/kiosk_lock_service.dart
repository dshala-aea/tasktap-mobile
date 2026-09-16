import 'dart:io';

import 'package:flutter/services.dart';

/// What happened when kiosk mode tried to pin the device to the app.
enum KioskLockOutcome {
  /// The OS actually locked the screen to this app (Android `startLockTask` / screen pinning —
  /// the technician cannot leave without the exit PIN flow AND the system "unpin" gesture).
  locked,

  /// The platform has no programmatic equivalent (iOS: Guided Access is real single-app lockdown,
  /// but Apple only lets a *person* turn it on, via a triple-click of the side/home button — no
  /// API lets an app enable it for itself). Kiosk mode still runs — credential, QR display, exit
  /// PIN all work — but nothing stops a technician from pressing the iOS home indicator/App
  /// Switcher unless they (or an MDM profile) also enable Guided Access by hand. The activation
  /// and display screens show this explicitly so nobody assumes the tablet is actually locked.
  unsupportedPlatform,

  /// The platform channel exists and claims Android, but the OS call itself failed (e.g. the
  /// activity isn't in the foreground, or the device disallows lock task for this app).
  failed,
}

/// Locks the device to this app (Android Lock Task Mode / screen pinning) for kiosk mode, and
/// releases it again on deactivation.
///
/// True silent, un-exitable lock task (no system "unpin" affordance at all) requires the app to
/// be the device/profile owner via MDM provisioning — out of scope here, and not something a
/// downloaded app can grant itself. What this DOES give a kiosk tablet, with zero extra
/// provisioning: `Activity.startLockTask()` screen pinning, which hides Recents/Home and pins the
/// current app, leaving only the OS's own long-press-Back-and-Overview "unpin" gesture as an
/// escape hatch — combined with this app's own hidden-gesture-plus-PIN exit (see
/// `KioskDisplayScreen`), that is a real deterrent for a technician-facing wall tablet.
abstract interface class IKioskLockService {
  /// Pins the app to the foreground. Safe to call more than once.
  Future<KioskLockOutcome> start();

  /// Releases the pin, if any. Safe to call even when not currently locked.
  Future<void> stop();

  /// Best-effort: whether the OS currently considers this app locked/pinned.
  Future<bool> isActive();
}

/// Real implementation, backed by a `MethodChannel` to native code — same shape as
/// `OnDeviceRecognitionProbe` (`core/dictation/dictation_service.dart`): a thin ask-the-platform
/// probe/actuator, `MissingPluginException` (host side not registered — desktop, tests, a build
/// that predates the channel) always reads as "not supported" rather than throwing.
class PlatformKioskLockService implements IKioskLockService {
  const PlatformKioskLockService([
    this._channel = const MethodChannel('tasktap/kiosk_lock'),
  ]);

  final MethodChannel _channel;

  @override
  Future<KioskLockOutcome> start() async {
    if (!Platform.isAndroid) {
      // iOS (and any other platform): ask the channel to at least keep the screen awake, but the
      // real answer is "unsupported" — see this class's own doc comment.
      try {
        await _channel.invokeMethod<void>('keepScreenAwake');
      } on PlatformException {
        // Best-effort only; kiosk mode still proceeds without it.
      } on MissingPluginException {
        // Same.
      }
      return KioskLockOutcome.unsupportedPlatform;
    }

    try {
      final locked =
          await _channel.invokeMethod<bool>('startLockTask') ?? false;
      return locked ? KioskLockOutcome.locked : KioskLockOutcome.failed;
    } on PlatformException {
      return KioskLockOutcome.failed;
    } on MissingPluginException {
      return KioskLockOutcome.unsupportedPlatform;
    }
  }

  @override
  Future<void> stop() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('stopLockTask');
      } else {
        await _channel.invokeMethod<void>('allowScreenSleep');
      }
    } on PlatformException {
      // Nothing to pin/unpin on this device — deactivation still proceeds.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  Future<bool> isActive() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isLockTaskActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
