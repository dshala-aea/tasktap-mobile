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
