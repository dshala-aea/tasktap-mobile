package com.advantedge.tasktap.tasktap_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the biometric prompt through
// AndroidX BiometricPrompt, which requires a FragmentActivity host. Under the default
// FlutterActivity it compiles fine and throws at runtime the first time a technician taps the
// biometric toggle — a failure no build or unit test surfaces.
class MainActivity : FlutterFragmentActivity()
