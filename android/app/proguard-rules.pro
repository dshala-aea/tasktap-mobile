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

# Flutter's engine references Google Play Core's split-install classes for deferred/dynamic
# feature delivery, a feature this app does not use. The real fix is the
# com.google.android.play:feature-delivery dependency in build.gradle.kts (see the comment there
# for why -dontwarn alone can't satisfy R8 here). Kept as a defensive fallback.
# https://github.com/flutter/flutter/issues/139462
-dontwarn com.google.android.play.core.**
