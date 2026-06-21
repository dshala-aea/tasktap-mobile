/// App configuration loaded from --dart-define at build time.
///
/// Usage (development):
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=your-anon-key \
///   --dart-define=API_BASE_URL=https://api.yourdomain.com
/// ```
///
/// Usage (CI / production build with crash reporting):
/// ```
/// flutter build apk \
///   --dart-define=SUPABASE_URL=$SUPABASE_URL \
///   --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
///   --dart-define=API_BASE_URL=$API_BASE_URL \
///   --dart-define=SENTRY_DSN=$SENTRY_DSN
/// ```
///
/// NEVER commit real values here. The defaults are intentionally empty
/// so that a build without the dart-define flags fails fast at runtime
/// (Supabase.initialize will throw if the URL is blank).
/// SENTRY_DSN is optional: when absent, crash reporting is a no-op.
abstract final class Env {
  /// Supabase project URL — e.g. https://abcdefgh.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Supabase anon (public) key.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// TaskTap backend REST API base URL — e.g. https://api.tasktap.io
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Sentry DSN for crash reporting.
  ///
  /// When empty (the default), Sentry is NOT initialised and [CrashReporter]
  /// falls back to a no-op implementation.  This means unit tests and local
  /// development runs without a DSN work correctly.
  ///
  /// Obtain the DSN from your Sentry project settings and pass it at build time:
  ///   `--dart-define=SENTRY_DSN=https://<KEY>@o<ORG>.ingest.sentry.io/<PROJECT>`
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// Returns true when all required env vars are present.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      apiBaseUrl.isNotEmpty;
}
