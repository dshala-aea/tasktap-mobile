# Two-step login and contextual onboarding — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the sign-in method an explicit choice after the email, and replace the mandatory five-page permission wizard with a single welcome page that asks only for notifications.

**Architecture:** Both changes are client-only. `LoginScreen` gains a local step state (email → method) inside one `AutofillGroup`; `OnboardingScreen` collapses to one page and the per-permission pages disappear, leaving location/camera/microphone to the prompts they already raise at first use.

**Tech Stack:** Flutter, Riverpod, go_router, SharedPreferences, `permission_handler`/`geolocator` (unchanged), `NotificationService`.

**Spec:** `docs/superpowers/specs/2026-11-01-login-and-onboarding-ux-design.md`

## Global Constraints

- No API, BFF, or passkey-flow changes; the password BFF and `signInWithPasskey` keep their signatures.
- Both login steps live inside one `AutofillGroup`; `TextInput.finishAutofillContext()` fires only on a successful password sign-in.
- Wrong password stays on the method step; unexpected failures keep the "Accedi con il browser" escape.
- The onboarding router gate (`onboardingCompletedProvider`, per user) and the `/onboarding` route are unchanged.
- Only the notification permission is requested at the welcome; location, camera and microphone are not asked there.
- Copy is Italian, following the existing tone; exact strings are fixed by the tasks below.

## Review Focus

1. **Password managers** still offer to fill and save the email+password pair when the two fields are on different steps.
2. **Back from the method step** preserves the email and clears any error from a failed attempt.
3. **Passkey on step 2** uses the email from step 1 — never an empty login name.
4. **A failed password attempt** does not bounce the user back to step 1.
5. **Onboarding "Inizia"** completes once and the router leaves `/onboarding`; the notification ask never blocks or traps.
6. **No permission prompt** fires merely by opening the welcome page.

---

### Task 1: Two-step login

**Files:**
- Modify: `lib/presentation/screens/login/login_screen.dart`
- Test: `test/presentation/screens/login_screen_test.dart`

**Interfaces:**
- Consumes: `LoginNotifier.signInWithPassword(String loginName, String password)` and `signInWithPasskey(String loginName)`, unchanged.
- Produces: a local `_LoginStep { email, method }`; no public API.

- [ ] **Step 1: Write the failing tests**

Rewrite the existing passkey/error groups around the two steps:

```dart
testWidgets('the email step refuses to continue while the field is empty');
testWidgets('continuing shows the method step with the email and the password field');
testWidgets('back from the method step keeps the email and clears the error');
testWidgets('a wrong password stays on the method step');
testWidgets('the passkey action on the method step calls signInWithPasskey with the email');
testWidgets('the browser fallback is still offered for an unexpected failure');
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/presentation/screens/login_screen_test.dart`
Expected: failures — the method step and the "Continua" action do not exist yet.

- [ ] **Step 3: Implement the two steps**

- `_LoginStep` enum + `_step` state; `AutofillGroup` wraps the whole body.
- Step 1: logo, "Accedi", short line, email field (`AutofillHints.username`), error banner, `AppButton('Continua')` disabled while the trimmed email is empty. `_onContinue` sets the step and clears the error.
- Step 2: the email shown read-only with a "Cambia" action returning to step 1 (email preserved, error cleared); password field (`AutofillHints.password`); error banner; `AppButton('Accedi')` (loading state as today); `OutlinedButton('Usa una passkey')`; `TextButton('Password dimenticata?')`; the browser fallback for non-`InvalidCredentials` failures.
- `_onLogin` uses the step-1 email; the passkey action likewise. `TextInput.finishAutofillContext()` only after a successful password sign-in.

- [ ] **Step 4: Run to green**

Run: same command, then `flutter test test/presentation/`.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/login/login_screen.dart test/presentation/screens/login_screen_test.dart
git commit -m "feat(login): ask for the email first, then the sign-in method"
```

---

### Task 2: Remember the last email

**Files:**
- Modify: `lib/presentation/screens/login/login_screen.dart`
- Test: `test/presentation/screens/login_screen_test.dart`

**Interfaces:**
- Produces: a `SharedPreferences` key `login.last_email` (plain preference, never a token).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('a saved email prefills the first step');
testWidgets('a successful password sign-in remembers the email');
testWidgets('a failed attempt does not overwrite the saved email');
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/presentation/screens/login_screen_test.dart`

- [ ] **Step 3: Implement**

Read the key in `initState` and prefill `_usernameCtrl` (stay on step 1); write it only when a password or passkey sign-in returns `failure == null`. Keep the read tolerant of a missing/corrupt value.

- [ ] **Step 4: Run to green** — same command.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/login/login_screen.dart test/presentation/screens/login_screen_test.dart
git commit -m "feat(login): remember the last email on this device"
```

---

### Task 3: One-page onboarding

**Files:**
- Modify: `lib/features/onboarding/onboarding_screen.dart`
- Delete: `lib/features/onboarding/permission_step_page.dart`
- Delete: `test/features/onboarding/permission_step_page_test.dart`
- Test: `test/features/onboarding/onboarding_screen_test.dart` (rewrite)

**Interfaces:**
- Consumes: `onboardingCompletedProvider(userId).notifier.markCompleted()`; `NotificationService.isAvailable` / `ensurePermission()` / `authorizationStatus()`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('the welcome asks only for notifications and offers Inizia');
testWidgets('opening the welcome raises no location, camera or microphone prompt');
testWidgets('Inizia marks onboarding complete for the user');
testWidgets('the notification action asks the OS and reflects the granted state');
testWidgets('a denied notification ask still lets Inizia complete');
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/features/onboarding/`
Expected: the single-page expectations fail against the five-page wizard.

- [ ] **Step 3: Implement**

Replace the `PageView` with one scrollable page: logo/title, one-line description, a notification row whose action calls `NotificationService.ensurePermission()` (hidden/disabled with "Non disponibile su questo dispositivo." when `isAvailable` is false, mirroring today's copy), and the primary `AppButton('Inizia')` that marks onboarding complete. No location/camera/biometric calls. Delete `permission_step_page.dart` and its test — nothing else imports it.

- [ ] **Step 4: Run to green**

Run: `flutter test test/features/onboarding/ test/core/router/`

- [ ] **Step 5: Commit**

```bash
git add lib/features/onboarding/ test/features/onboarding/
git commit -m "feat(onboarding): one welcome page; ask permissions when they are needed"
```

---

### Task 4: Regression sweep

**Files:** none.

- [ ] **Step 1: Run the full suite**

Run: `flutter test`
Expected: the same 10 pre-existing failures on `main` (startup timing, step-ore readout, report-editor providers) and nothing new.

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/presentation/screens/login lib/features/onboarding`
Expected: clean.

- [ ] **Step 3: Commit any test-only adjustments** that the removal forced, with a message naming the removed wizard.
