plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.advantedge.tasktap.tasktap_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.advantedge.tasktap.tasktap_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The custom scheme the identity provider redirects back to after sign-in.
        //
        // flutter_appauth registers its RedirectUriReceiverActivity against this placeholder; with
        // it unset the build has no intent-filter for the callback, so Android hands the redirect
        // to nothing. The browser sits on the last page and the app waits for a result that can
        // never arrive — sign-in does not fail, it hangs, which is why the OIDC work read as
        // "code-complete" while no phone had ever completed a login.
        //
        // Must equal the scheme of Env.oidcRedirectUri (it.tasktap.app://callback) and the
        // redirect URI registered on the Zitadel Native application. All three or none.
        manifestPlaceholders["appAuthRedirectScheme"] = "it.tasktap.app"
    }

    signingConfigs {
        getByName("debug") {
            // Default debug keystore — used for local development builds.
        }
        create("release") {
            // When building on CodeMagic, the CI provides the keystore via
            // KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD env vars.
            // When running locally, falls back to debug signing.
            val ksFile = System.getenv("KEYSTORE_PATH")
            if (ksFile != null && file(ksFile).exists()) {
                storeFile = file(ksFile)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("KEYSTORE_PATH") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
