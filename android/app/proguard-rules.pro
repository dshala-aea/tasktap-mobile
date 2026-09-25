# Flutter-specific ProGuard rules for release builds.

# Keep Flutter engine and plugin classes.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Supabase client classes.
-keep class io.github.jan-tennert.supabase.** { *; }

# Keep Dio interceptors and models.
-keep class io.github.jan.supabase.** { *; }

# Keep Sentry classes.
-keep class io.sentry.** { *; }

# Keep Drift generated code.
-keep class drift.** { *; }
-keep class app_database.** { *; }

# General Android / Kotlin rules.
-dontwarn javax.annotation.**
-dontwarn sun.misc.Unsafe
-keepattributes Signature
-keepattributes *Annotation*
-keep class kotlin.Metadata { *; }

# Flutter's engine references Google Play Core's split-install classes
# (PlayStoreDeferredComponentManager) for deferred/dynamic feature delivery, a feature this app
# does not use — the `com.google.android.play:core` dependency was never added, so R8 fails with
# "Missing class com.google.android.play.core.*" during release minification. These classes are
# only reachable through Flutter's deferred-component code path, which this app never calls into,
# so it's safe to tell R8 not to warn about them rather than pulling in the (deprecated,
# split-package-replaced) play-core artifact just to satisfy the shrinker.
# https://github.com/flutter/flutter/issues/139462
-dontwarn com.google.android.play.core.**
