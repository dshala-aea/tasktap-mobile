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
/// NEVER commit real values here. The OIDC/API defaults are intentionally
/// empty so a build without the dart-define flags fails fast at runtime.
/// SENTRY_DSN is optional: when absent, crash reporting is a no-op.
abstract final class Env {
  /// Zitadel OIDC issuer — e.g. https://tasktap-auth.advantedgeautomation.com
  static const String oidcIssuer = String.fromEnvironment('OIDC_ISSUER', defaultValue: '');

  /// OIDC client id of the mobile (Native) app.
  static const String oidcClientId = String.fromEnvironment('OIDC_CLIENT_ID', defaultValue: '');

  /// OIDC redirect URI (custom scheme). Must match the app's registered scheme
  /// and the Zitadel Native app's redirect URI — e.g. it.tasktap.app://callback
  static const String oidcRedirectUri = String.fromEnvironment(
    'OIDC_REDIRECT_URI',
    defaultValue: 'it.tasktap.app://callback',
  );

  /// TaskTap backend REST API base URL — e.g. https://api.tasktap.io
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Sentry DSN for crash reporting.
  ///
  /// When empty (the default), Sentry is NOT initialised and [CrashReporter]
  /// falls back to a no-op implementation.  This means unit tests and local
  /// development runs without a DSN work correctly.
  ///
  /// Obtain the DSN from your Sentry project settings and pass it at build time:
  ///   `--dart-define=SENTRY_DSN=https://<KEY>@o<ORG>.ingest.sentry.io/<PROJECT>`
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  /// Returns true when all required env vars are present.
  static bool get isConfigured =>
      oidcIssuer.isNotEmpty && oidcClientId.isNotEmpty && apiBaseUrl.isNotEmpty;
}
