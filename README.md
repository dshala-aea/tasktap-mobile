# tasktap_mobile

TaskTap Flutter app for field technicians — offline-first rapportino creation.

Built on M5 (commit `1271cca`): full offline draft + submit loop, 204 tests green.

---

## Build / Run

All credentials are passed at build/run time via `--dart-define`. **Never commit real values.**

### Development (flutter run)

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=API_BASE_URL=https://api.yourdomain.com
```

### Release (APK / internal track)

```sh
flutter build apk --release \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=API_BASE_URL=$API_BASE_URL \
  --dart-define=SENTRY_DSN=$SENTRY_DSN
```

### dart-define reference

| Variable           | Required | Description |
|--------------------|----------|-------------|
| `SUPABASE_URL`     | Yes      | Supabase project URL (`https://<id>.supabase.co`) |
| `SUPABASE_ANON_KEY`| Yes      | Supabase anon (public) key |
| `API_BASE_URL`     | Yes      | TaskTap backend REST API base URL |
| `SENTRY_DSN`       | No       | Sentry DSN for crash reporting. When absent, crash reporting is a no-op (safe for local/CI runs). |

---

## Crash Reporting (Sentry)

Crash reporting uses [sentry_flutter](https://pub.dev/packages/sentry_flutter).

- `SENTRY_DSN` is **optional** — when absent, a no-op `CrashReporter` is used and the app runs normally.
- When the DSN is present, `SentryFlutter.init` wraps the entire app (catches Flutter framework errors, async zone errors, unhandled exceptions).
- The abstraction lives at `lib/core/crash_reporting/crash_reporter.dart`. To swap the backend (e.g. to Firebase Crashlytics), implement `CrashReporter` and call `CrashReporter.setInstance(...)` in `main()`.

Obtain your DSN from your Sentry project → Settings → Projects → Client Keys.

---

## Testing

### Unit tests (fast, no device needed)

```sh
flutter test
```

All tests in `test/` run headless. The integration test is **excluded** from `flutter test` automatically because it lives in `integration_test/`.

### Integration tests (requires a device or emulator)

```sh
flutter test integration_test/offline_submit_test.dart \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=API_BASE_URL=...
```

The integration test exercises the full **offline → submitted** happy path (create draft, fill required fields, mark ready, run submission queue against a mocked API, assert `submitted` state). No real network is needed — the API is mocked with Mocktail.

---

## App Icon + Splash Screen

### Source asset

`assets/icons/tasktap_icon.png` (1024×1024, sourced from the frontend `public/` directory).

Brand colors:
- Background: `#FFF10E` (TaskTap yellow)
- Logo: dark foreground over yellow

### Generating icons

After installing dependencies (`flutter pub get`):

```sh
# App icon (Android adaptive + iOS)
flutter pub run flutter_launcher_icons

# Splash screen (Android + iOS)
dart run flutter_native_splash:create
```

The configuration is already in `pubspec.yaml` under `flutter_launcher_icons:` and `flutter_native_splash:`. Re-run the generators whenever you change `assets/icons/tasktap_icon.png`.

> These generators write platform files to `android/` and `ios/`. You must run them on a machine with the relevant SDKs, or let CI handle it as part of the build pipeline. The source PNG is committed so CI can run the generators.

---

## CI/CD (CodeMagic)

The project uses [CodeMagic](https://codemagic.io) for automated builds, testing, and deployment.

### Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `check` | Pull requests | `flutter analyze` + `flutter test` |
| `android_release` | Push to `main` or tag `v*` | Build AAB + APK → Google Play internal track |
| `ios_release` | Push to `main` or tag `v*` | Build IPA → TestFlight |
| `ios_app_store` | Manual | Promote TestFlight build to App Store |

### CodeMagic secrets (encrypted variable groups)

Create these groups in CodeMagic UI (Team settings > Encrypted variables):

**`tasktap_dartDefines`** — environment variables passed as `--dart-define`:

| Variable | Description |
|---|---|
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase anon (public) key |
| `API_BASE_URL` | TaskTap backend REST API base URL |
| `SENTRY_DSN` | Sentry DSN for crash reporting (optional) |

**`tasktap_keystore`** — Android release signing (set up via CodeMagic UI signing tab):

| Variable | Description |
|---|---|
| `KEYSTORE_PATH` | Path to uploaded keystore (CodeMagic sets this) |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias |
| `KEY_PASSWORD` | Key password |

**`tasktap_google_play`** — Google Play deployment:

| Variable | Description |
|---|---|
| `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | Service account JSON for Google Play API |

**`tasktap_app_store_connect`** — App Store Connect (iOS):

| Variable | Description |
|---|---|
| `APP_STORE_CONNECT_API_KEY` | App Store Connect API private key (text) |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |

### Android release signing

Android release builds use a keystore uploaded to CodeMagic. The `android/app/build.gradle.kts` checks for the `KEYSTORE_PATH` env var:

- **CodeMagic CI**: keystore is available → release signing is used.
- **Local builds**: no keystore → falls back to debug signing.

To generate a release keystore locally (one-time):

```sh
keytool -genkey -v -keystore tasktap-release.jks \
  -alias tasktap -keyalg RSA -keysize 2048 -validity 10000
```

### Tagging a release

```sh
git tag v1.0.0
git push origin v1.0.0
```

This triggers both `android_release` and `ios_release` workflows.

---

## Project structure

```
lib/
  core/
    config/env.dart              # dart-define wrappers (Env.supabaseUrl, .sentryDsn …)
    crash_reporting/
      crash_reporter.dart        # CrashReporter abstraction (no-op default)
      sentry_crash_reporter.dart # Sentry implementation
    router/                      # go_router
    theme/                       # brand tokens + ThemeData
    widgets/                     # AppButton, AppCard, AppTextField, StatusBadge
  data/
    api/                         # Dio client + auth interceptor
    auth/                        # Supabase auth repository
    local/                       # Drift DB + generated code
    reports/                     # DraftReportRepository, ReportSubmitApiClient
    sync/                        # SyncService, SubmissionQueue, connectivity
  domain/
    auth/                        # Auth entities + IAuthRepository
    reports/                     # DraftValidation (mirrors server state machine)
  presentation/
    providers/                   # Riverpod providers
    screens/                     # Login, HomeShell, Oggi, Interventi, Rapportini, Profilo
  main.dart                      # Entry point — Sentry init + Supabase init + ProviderScope

test/                            # Unit + widget tests (headless)
integration_test/                # Device/emulator integration tests
assets/
  icons/
    tasktap_icon.png             # Source brand icon for flutter_launcher_icons + flutter_native_splash
```

---

## Architecture

Clean architecture: `data/` → `domain/` → `presentation/` (Riverpod providers + screens).

- **State:** Riverpod (`flutter_riverpod` + `riverpod_annotation`)
- **Local DB:** Drift (SQLite, offline-first)
- **Auth:** Supabase Flutter (JWT cached for offline use)
- **Networking:** Dio with Auth interceptor (401 → silent refresh → retry)
- **Connectivity:** `connectivity_plus` triggers `SubmissionQueue.processAll()` on reconnect
- **Submission:** `SubmissionQueue` Strategy A (process on demand) — swap to WorkManager without touching upload/submit logic

## Pilot checklist (user runs on device)

1. `flutter pub run flutter_launcher_icons` — generates icon assets
2. `dart run flutter_native_splash:create` — generates splash screen assets
3. `flutter build apk --release --dart-define=...` — build distribution APK
4. Run `integration_test/offline_submit_test.dart` on a real device to verify offline→submit flow
5. Real-device field testing: airplane-mode end-to-end, low-connectivity, large photos, token expiry mid-draft
