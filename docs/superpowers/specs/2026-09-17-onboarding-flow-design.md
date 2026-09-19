# First-login onboarding flow — design

Status: **Draft, for review.**

## Context

The app has no onboarding today. Every permission it needs (location, push notifications,
camera/microphone, biometric lock) is requested contextually, the first time a feature that needs
it is used — via the existing `askPermissionPurpose` sheet (`lib/core/widgets/
permission_purpose_sheet.dart`), whose own doc comment records that this contextual approach
replaced an earlier "ask blind at startup" pattern that was explicitly identified as a
transparency failure and a reliable way to get permissions permanently denied.

This spec adds a one-time, post-login onboarding flow that fires the real OS permission prompts up
front (reusing the existing contextual-ask philosophy's visual language, not replacing it), so a
new technician sets up the device once instead of hitting four separate unexplained prompts spread
across their first week of real use. The existing contextual asks in `cantiere_timbra_screen.dart`,
`step_dettagli.dart`, and `impostazioni_screen.dart` are unaffected — they remain the fallback path
for anyone who skips a step here, or for a permission revoked later.

## Scope

**In scope:**
- `OnboardingScreen` — a 5-page linear flow: Welcome, Location, Notifiche, Fotocamera e microfono,
  Blocco biometrico.
- A router gate (mirroring the existing kiosk-mode gate in `app_router.dart`) that sends a newly
  authenticated user here once, before Dashboard, and never again for that account.
- Per-step real OS permission requests, each delegating to the service that already owns that
  permission elsewhere in the app (no new permission-request logic is invented).
- Correct handling of three states per step: not yet asked, already granted (skip to "done"), and
  permanently denied (offer "Apri impostazioni" instead of a dead prompt).
- One small refactor: extracting `impostazioni_screen.dart`'s biometric-enable sequence into a
  shared function so the onboarding step and the Impostazioni toggle call the same code.
- Two small additions for state detection: `ILocationService.permissionStatus()` and
  `NotificationService.authorizationStatus()`, both needed to tell "already granted" apart from
  "denied" (see Decisions — the existing boolean-returning checks deliberately collapse that
  distinction, correctly, for their one current caller each).
- One new dependency: `permission_handler`, used only by the Fotocamera e microfono step's camera
  half (see Decisions).

**Explicitly out of scope:**
- Any app-tour / feature-walkthrough content. This is a permissions setup flow, not a marketing
  carousel — "maybe some other needed things" from the original request is scoped down to the
  biometric-lock offer, since that's the only other one-time device setup step that exists in the
  app today (Impostazioni already has a "Tema scuro" toggle and offline-sync toggle, neither of
  which is a permission or a one-time setup decision — both stay exactly where they are).
- Changing what happens after a permission is denied or skipped: existing screens' contextual
  fallback behavior (e.g. "compila il rapportino senza coordinate") is untouched.
- Re-triggering onboarding after it's been completed once for an account, even if the technician
  later revokes a permission from OS settings. Re-granting after that goes through the existing
  contextual asks or Impostazioni, same as it does today for every existing user.
- A global "skip everything" button (see Decisions — per-step skip only).

## Decisions

### Router gating

New `AppRoutes.onboarding = '/onboarding'`, added as a plain (non-nested) route. `app_router.dart`'s
`redirect` callback gets a third branch, evaluated after the kiosk gate and alongside the auth
gate:

- While `onboardingCompletedProvider` is loading: return `null` (stay put) — same treatment
  `kioskState.loading` and the auth `AsyncLoading` case already get.
- Authenticated, not completed, not already on `/onboarding`: redirect to `/onboarding`.
- On `/onboarding` while unauthenticated, or already completed: redirect away (to `/login` or
  `/dashboard` respectively — same resolution the existing auth branch already computes).

`onboardingCompletedProvider` is added to the router's `refreshListenable` merge so completing the
flow immediately triggers the redirect away, with no manual navigation call needed from the
screen itself (the last page's action is just "write the flag", not "navigate").

### Persistence

New file `lib/features/onboarding/onboarding_provider.dart`. A `SharedPreferences`-backed
`AsyncNotifier<bool>`, keyed `onboarding.completed.<userId>` — per-account, not per-device, per the
explicit requirement (a shared/handed-down device re-runs onboarding for a new technician signing
in). Deliberately not folded into `impostazioniProvider`: that provider syncs its settings with a
backend endpoint, and onboarding completion is purely local device state with nothing to sync.

### Screens

`lib/features/onboarding/onboarding_screen.dart` — a `PageView` with `physics:
NeverScrollableScrollPhysics()` (button-driven only, so a swipe can't skip the transparency step
the flow exists to provide) over 5 pages:

1. **Welcome** — app name/mark, one line on what's about to happen ("Configuriamo insieme i
   permessi di cui TaskTap ha bisogno"). Single "Inizia" action.
2. **Location** — icon/titolo/motivo/senzaDiEsso card, same shape `askPermissionPurpose` already
   renders (inlined here rather than shown as a sheet, since this is a full page, not an
   interruption of some other flow). **Consenti** / **Non ora**.
3. **Notifiche** — same card shape, wired to `NotificationService.instance.ensurePermission()`.
4. **Fotocamera e microfono** — one card explaining both together (matches how the original request
   grouped them), **Consenti** requests both permissions.
5. **Blocco biometrico** — same card shape; **Attiva** only shown if the device actually has
   biometrics enrolled (mirrors the existing Impostazioni guard); otherwise the page states that
   plainly instead of offering a button that can't work.

Each permission page (2–5) renders one of three states, checked on page build:
- **Not yet decided** — the explanation card with Consenti/Non ora.
- **Already granted** (from a prior contextual ask, or a previous partial run of this same flow —
  see below) — a plain confirmation state, no button, auto-advances after a short beat or on tap
  anywhere.
- **Permanently denied** (OS won't re-prompt — the common case on iOS after one refusal) — the same
  card, but the action becomes "Apri impostazioni" (`app_settings`-style intent/URL, whichever the
  target service already uses if it has one, otherwise `AppSettings.openAppSettings()` from
  `permission_handler`) instead of re-firing a dialog that can't appear.

Last page's "Vai alla Dashboard" (or "Fine" on page 5, whichever reads better in context) writes
`onboardingCompletedProvider`'s flag; the router's own redirect then takes over navigation — the
screen does not call `context.go(...)` itself.

**No global skip.** Each of pages 2–5 has its own "Non ora", satisfying "must be seen once,
individually skippable" without a shortcut that defeats the transparency purpose of the flow.

### Per-step permission wiring (all delegate to existing code)

| Step | Delegates to | Notes |
|---|---|---|
| Location | `ref.read(locationServiceProvider).getCurrentPosition()` to fire the prompt; a **new** `ILocationService.permissionStatus()` to render the right state beforehand | `getCurrentPosition()` is the same call `step_dettagli.dart`'s `_captureGps` makes — reused as-is for the actual prompt, coordinate discarded. But `willPromptForPermission()` (the only status check the interface exposes today) deliberately collapses "granted" and "deniedForever" to the same `false` — its own doc comment says so, and that's correct for its one existing caller, which only needs "should I show the purpose sheet." Onboarding needs to tell those two apart to render "already done" vs. "open settings," so this adds one small method returning an enum (`granted`/`denied`/`deniedForever`/`disabled`), concrete-with-a-default like `willPromptForPermission` so test fakes need no changes. `willPromptForPermission()` itself is untouched. |
| Notifiche | `NotificationService.instance.ensurePermission()` to fire the prompt; a **new** `NotificationService.authorizationStatus()` to render the right state beforehand | `ensurePermission()` is unchanged. `hasPermission()` (the only status check exposed today) collapses `notDetermined`/`denied` to the same `false` — fine for its one current caller ("can I skip asking"), not enough for onboarding to tell "never asked" from "said no." Adds one small method returning the raw `AuthorizationStatus`. Also guarded on `NotificationService.isAvailable` exactly like every other call site — if Firebase failed to init, this page states that plainly instead of a dead button. Note: `AuthorizationStatus` has no distinct "permanently denied" value on Android (unlike iOS's real never-again-on-deny), so `denied` is treated as "offer settings" on both platforms — the safe default, since re-requesting an already-denied permission generally shows nothing anyway. |
| Fotocamera e microfono | Status check for both via `permission_handler`'s `Permission.camera.status`/`Permission.microphone.status` (the only one of the three that already distinguishes granted/denied/permanentlyDenied natively — no new method needed here, unlike Location/Notifiche above); the actual grant via `Permission.camera.request()` for camera, `DictationService.initialize()` for microphone | Mic's *request* deliberately still goes through `DictationService`, not `permission_handler`, even though its *status* is read via `permission_handler` — so the app has exactly one place that decides "dictation actually works" (capability + OS permission together), matching `step_dettagli.dart`'s existing `capability()` call. See "New dependency" below for why camera needs a new package at all. |
| Blocco biometrico | The extracted shared function (see "Biometric refactor" below) | Identical behavior to today's Impostazioni toggle: capability check → biometric verify prompt → persist to `impostazioniProvider`. |

### New dependency: `permission_handler`

`image_picker` has no way to request camera permission without actually opening the camera UI, and
`mobile_scanner` would require standing up a scanner controller just to trigger the same dialog —
neither is acceptable for a priming step that shouldn't launch a live camera view. `permission_handler`
is added specifically for this one step's camera half; the existing photo-attach flow in the
Allegati tab keeps using `image_picker` exactly as it does today, untouched. Microphone stays on
`DictationService` rather than moving to `permission_handler` too, so there remains exactly one
code path that decides "is microphone granted" for the feature that actually uses it.

### Biometric refactor

`impostazioni_screen.dart`'s `_toggleBiometrics` (capability check via `biometricServiceProvider`,
`Nessuna impronta o Face ID configurati` guard, verify prompt, persist via
`impostazioniProvider.notifier.toggle`) moves to a shared location — most likely a static method on
`BiometricLock` or a new small `biometric_setup.dart` next to it, whichever reads more naturally
once written — with `impostazioni_screen.dart` and the new onboarding step both calling it. No
behavior change to the existing Impostazioni screen; this is purely deduplication of logic that two
places now need identically.

## Error handling / edge cases

- **Existing users on this device** (already granted or denied some of these permissions before
  onboarding existed): every step reads actual current OS status before rendering its
  not-yet-decided state, so nobody who already granted location last month sees a redundant prompt
  — they see the already-granted confirmation and move on.
- **Firebase unavailable** (`NotificationService.isAvailable == false`): the Notifiche step states
  that push isn't available on this build/device rather than presenting a button wired to nothing.
- **Biometrics not enrolled on device**: the Blocco biometrico step says so and offers no button,
  matching the existing Impostazioni guard's own message.
- **App backgrounded/killed mid-flow**: nothing to reconcile — each step's state is read fresh from
  the OS on next build, and the completed flag is only written on the final page, so an interrupted
  run simply resumes wherever the OS's own permission state says it should.

## Testing

- Widget tests per permission step: not-yet-decided → Consenti → granted; not-yet-decided → Non ora
  → advances without prompting; already-granted → auto-advance state; permanently-denied → settings
  link shown, no prompt fired.
- A router test asserting the onboarding gate: authenticated + not completed → redirected to
  `/onboarding`; authenticated + completed → never redirected there; unauthenticated on
  `/onboarding` → redirected to `/login`. Mirrors whatever pattern the existing kiosk-gate test (if
  one exists) already uses.
- Existing Impostazioni biometric-toggle tests continue passing unchanged after the extraction
  (behavior parity is the whole point of that refactor).
