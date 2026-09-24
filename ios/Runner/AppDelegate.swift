import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerDictationChannel(messenger)
    registerKioskLockChannel(messenger)
  }

  /// Whether this handset can recognise Italian speech without sending audio to Apple.
  ///
  /// Asked directly rather than through the speech_to_text plugin, which does not surface it.
  /// ADR-0017 makes on-device recognition the foundation — dictation has to work in a basement,
  /// and no site audio may leave the device — so this is a precondition, not a preference, and
  /// dictation is refused when it is false.
  private func registerDictationChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tasktap/dictation", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isOnDeviceRecognitionAvailable":
        // Asked for Italian specifically: supportsOnDeviceRecognition is a property of the
        // recogniser for a given locale, and a device can hold the on-device model for one
        // language and not another. Rapportini are written in Italian, so the general answer is
        // not the useful one.
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT")) else {
          result(false)
          return
        }
        result(recognizer.supportsOnDeviceRecognition)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Kiosk mode's iOS half (see `lib/core/kiosk/kiosk_lock_service.dart`).
  ///
  /// There is no public API that lets an app enable true single-app lockdown on iOS — Guided
  /// Access exists and does exactly that, but Apple deliberately requires a PERSON to turn it on
  /// (triple-click the side/home button), specifically so no app can silently trap the user in
  /// itself. That is a intentional platform limitation, not a gap in this implementation: the
  /// Dart side (`PlatformKioskLockService.start()`) already reports `unsupportedPlatform` on iOS
  /// and shows the technician an explicit "enable Guided Access yourself" notice rather than
  /// claiming the tablet is locked when it is not.
  ///
  /// What IS available without a person's help: keeping the screen from sleeping while the kiosk
  /// display is up, since a blank/locked screen defeats the point of a wall-mounted totem just as
  /// completely as an unlocked one would.
  private func registerKioskLockChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tasktap/kiosk_lock", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "keepScreenAwake":
        UIApplication.shared.isIdleTimerDisabled = true
        result(nil)
      case "allowScreenSleep":
        UIApplication.shared.isIdleTimerDisabled = false
        result(nil)
      default:
        // startLockTask/stopLockTask/isLockTaskActive are Android-only concepts (see the
        // kiosk_lock_service.dart doc comment above) — the Dart side never sends them on iOS.
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
