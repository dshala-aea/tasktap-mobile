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
