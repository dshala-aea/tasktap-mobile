# Login and onboarding UX — design

Status: proposed. Mobile only; no API or backend change.

## 1. Intent

Two first-contact screens work against the technician rather than for them:

- **Login** shows email and password side by side with a secondary "Accedi con passkey" that
  cannot do anything until an email is typed. Both backends already need the email first
  (`MobileAuth/login` takes `loginName` + `password`; the passkey session needs a user to
  point ZITADEL's challenge at), so the single form is two flows pretending to be one.
- **Onboarding** is a mandatory five-page wizard (welcome, location, notifications,
  camera/mic, biometrics) with scrolling disabled — every permission needs its own page and
  its own skip path before the technician reaches the app.

The change: a two-step login that makes the method an explicit choice, and onboarding
reduced to a welcome that asks only for notifications, with every other permission requested
in context, the first time the capability is actually used.

## 2. What exists today

- `LoginScreen`: `AutofillGroup` with email + password fields, "Password dimenticata?",
  error banner, primary "Accedi", secondary "Accedi con passkey" (gated by
  `passkeySupportedProvider` and, after the last fix, by a non-empty email).
- `OnboardingScreen`: five `PageView` pages with `NeverScrollableScrollPhysics`; each
  permission page calls the OS through `PermissionStepPage`; completion is stored per user in
  `SharedPreferences` (`onboarding.completed.<userId>`) and the router redirects to
  `/onboarding` until it is set.
- Permission requests already happen at use: `LocationService.getCurrentPosition()` asks when
  denied; `image_picker` and speech-to-text raise the OS prompts on first use; the push
  permission is also available from Impostazioni → Notifiche push.
- Biometric unlock is opt-in in Impostazioni; it is not part of first-run setup.

## 3. Approaches

**A — two-step login; contextual prompts with a short welcome (chosen).** Email first, then
a "password or passkey" screen; onboarding becomes one welcome page that asks for
notifications (the one permission worth asking early) and otherwise gets out of the way.

**B — keep the single form, add a "use passkey" affordance once the email is filled.**
Smaller change, but the method ambiguity the report is about remains, and the passkey button
still looks secondary.

**C — keep the wizard but make it skippable.** Cheapest, but the five pages still ask for
permissions out of context, which is what makes it feel like a gauntlet.

## 4. Behaviour

### Login

1. **Step 1 — email.** One field (`AutofillHints.username`), "Continua", and the TaskTap
   logo. Empty or malformed email keeps the action disabled.
2. **Step 2 — method.** Shows the email with a way back to change it, then:
   - password field (`AutofillHints.password`) with "Accedi";
   - "Usa una passkey" as a secondary action, always available because the email is known;
   - "Password dimenticata?" (browser flow, unchanged);
   - the same error banner and loading state as today.
3. Unexpected failures keep the existing "Accedi con il browser" escape.
4. Autofill: the two fields stay in one `AutofillGroup` across the steps so password managers
   still offer to fill and save the pair; `TextInput.finishAutofillContext()` fires on a
   successful password sign-in only.
5. Wrong password stays on step 2, same form, retry in place.

### Onboarding

1. One welcome page: brand, one line on what the app does, **Attiva le notifiche** (system
   prompt via `NotificationService.ensurePermission()`) with **Non ora**, and **Inizia**.
2. "Inizia" marks onboarding complete for the user (same provider and router gate). The
   notifications ask is not required: "Non ora" proceeds and the permission remains available
   in Impostazioni → Notifiche push.
3. Location, camera/microphone: no page; the OS prompts at first use, as today.
4. Biometric lock: not requested at first run; opt-in from Impostazioni, as today.
5. `PermissionStepPage` and the page list are deleted if nothing else uses them.

## 5. What is left to the builder

- Exact copy and layout of the two login steps and the welcome page, following the existing
  design system (`AppButton`, `AppTextField`, `ScreenHeader`/logo styles).
- Whether the email is remembered for the next sign-in on the same device (a convenience,
  not a requirement; if added, it must not store anything in plain `SharedPreferences` beyond
  the last email — no token).
- The animation between login steps, if any (a simple `AnimatedSwitcher` is enough).

## 6. Testing

- Login: step 1 refuses to continue with an empty email; step 2 appears with the email shown;
  password success and failure behave as today; passkey action is enabled on step 2 and calls
  `signInWithPasskey` with the step-1 email; back returns to step 1 with the email preserved;
  the browser fallback still appears for unexpected failures.
- Onboarding: one page, "Non ora" proceeds without marking the permission denied, "Inizia"
  marks completion once, and the router leaves `/onboarding` afterwards; no page triggers a
  location/camera/microphone prompt.
- Existing suites that reference the removed wizard pages are updated, not deleted silently.

## 7. Non-goals

- Usernameless / discoverable-credential login (ZITADEL's Session API needs a named user).
- Changing the password BFF or the passkey flow.
- Tenant-level consent or legal documents.
- Moving notification preferences out of Impostazioni.
