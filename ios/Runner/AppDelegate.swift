import firebase_messaging
import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UIScene apps register plugins AFTER this method, but Apple requires the
    // UNUserNotificationCenter delegate to be set before it returns. firebase_messaging
    // (>= 16.5) documents this explicit call for the UIScene lifecycle.
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNs registration diagnostics
  //
  // `getAPNSToken()` in Dart only says the token is absent, never why. The reason is delivered to
  // these two callbacks (or they are never called at all, which is itself the answer), so they are
  // recorded here and read back through the `tasktap/push_diag` channel. Both call `super` FIRST:
  // FlutterAppDelegate forwards them to the registered plugin delegates, and firebase_messaging
  // depends on that to receive the APNs token. Only the token's presence is kept, never its bytes.
  // UIKit delivers these on the main thread, as does the Flutter platform channel, so plain
  // statics need no lock.
  private static var apnsRegistered = false
  private static var apnsRegisteredAt: Date?
  private static var apnsLastError: String?
  private static var apnsErrorAt: Date?

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    AppDelegate.apnsRegistered = !deviceToken.isEmpty
    AppDelegate.apnsRegisteredAt = Date()
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    let nsError = error as NSError
    let description = "\(nsError.domain):\(nsError.code):\(nsError.localizedDescription)"
    AppDelegate.apnsLastError = String(description.prefix(200))
    AppDelegate.apnsErrorAt = Date()
  }

  /// `tasktap/push_diag` — see `lib/core/notifications/apns_diagnostics.dart`.
  private func registerPushDiagChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tasktap/push_diag", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "apnsStatus":
        let formatter = ISO8601DateFormatter()
        var status: [String: Any] = ["registered": AppDelegate.apnsRegistered]
        if let error = AppDelegate.apnsLastError { status["error"] = error }
        if let at = AppDelegate.apnsErrorAt { status["errorAt"] = formatter.string(from: at) }
        if let at = AppDelegate.apnsRegisteredAt { status["registeredAt"] = formatter.string(from: at) }
        result(status)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerDictationChannel(messenger)
    registerKioskLockChannel(messenger)
    registerPushDiagChannel(messenger)
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
