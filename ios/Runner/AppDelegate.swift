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
    registerDictationChannel(engineBridge.binaryMessenger)
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
}
