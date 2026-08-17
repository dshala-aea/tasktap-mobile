package com.advantedge.tasktap.tasktap_mobile

import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the biometric prompt through
// AndroidX BiometricPrompt, which requires a FragmentActivity host. Under the default
// FlutterActivity it compiles fine and throws at runtime the first time a technician taps the
// biometric toggle — a failure no build or unit test surfaces.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Whether this handset can recognise speech without sending audio to a server.
        //
        // The speech_to_text plugin asks for on-device recognition and, when it is unavailable,
        // constructs an ordinary network SpeechRecognizer and carries on — see its
        // createRecognizer(). Nothing in its Dart API reports that, so an app that trusted the
        // plugin would believe it was recognising locally while streaming site audio to Google.
        //
        // ADR-0017 makes on-device the foundation rather than a preference, so this is asked
        // directly and dictation is refused when the answer is no.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasktap/dictation")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isOnDeviceRecognitionAvailable" -> {
                        // isOnDeviceRecognitionAvailable arrived in API 31. Below that there is no
                        // way to ask, and no on-device recogniser to find, so the answer is no
                        // rather than unknown.
                        val available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                        result.success(available)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
