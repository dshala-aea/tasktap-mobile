# First-login onboarding flow implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-time, post-login onboarding flow (Welcome + Location + Notifiche + Fotocamera e microfono + Blocco biometrico) that fires real OS permission prompts up front, reusing every permission service that already exists in the app.

**Architecture:** A new `lib/features/onboarding/` feature: a `PageView`-based `OnboardingScreen` gated by a new router redirect branch (mirrors the existing kiosk-mode gate exactly), backed by a per-account `SharedPreferences` flag. A single reusable `PermissionStepPage` widget renders all four permission pages from a small, service-agnostic state machine (`notDetermined` / `granted` / `deniedForever` / `unavailable`); each concrete page just supplies the copy and two callbacks (`checkStatus`, `request`) wired to that permission's existing service.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifier`, `Provider.family`), go_router, `shared_preferences`, new dependency `permission_handler` (camera/microphone only — Location/Notifiche/Biometrico keep using their existing services).

**Spec:** `docs/superpowers/specs/2026-09-17-onboarding-flow-design.md`

## Global Constraints

- Router gate mirrors the existing kiosk-mode gate pattern in `lib/core/router/app_router.dart` exactly (same "return null while loading" treatment).
- No new permission-request logic is invented — every step delegates to a service that already exists (`ILocationService`, `NotificationService`, `IDictationService`, `IBiometricService`).
- Per-account completion flag (`onboarding.completed.<userId>` in `SharedPreferences`), not per-device.
- No global "skip everything" — each of the 4 permission pages has its own "Non ora".
- `permission_handler` is added for exactly one purpose: reading/requesting camera permission, and reading (not requesting) microphone permission for the combined Fotocamera e microfono step. It is a Swift Package Manager project (no `ios/Podfile` exists) — SPM auto-detects camera/microphone support from `Info.plist`'s existing `NSCameraUsageDescription`/`NSMicrophoneUsageDescription` keys, so no further iOS project changes are needed for it.
- Every new/changed file must pass `flutter analyze` with zero new issues, and `flutter test` must stay fully green after every task.

---

### Task 1: Add the `permission_handler` dependency

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `package:permission_handler/permission_handler.dart` (`Permission`, `PermissionStatus`, `openAppSettings()`) available to later tasks.

- [ ] **Step 1: Add the dependency**

Add this line under the existing `dependencies:` section, alphabetically near the other single-purpose packages (e.g. next to `connectivity_plus`):

```yaml
  permission_handler: ^13.0.2
```

- [ ] **Step 2: Fetch it**

Run: `flutter pub get`
Expected: resolves cleanly, pulls in `permission_handler_android`, `permission_handler_apple`, `permission_handler_platform_interface` (and unused `permission_handler_html`/`permission_handler_windows` — harmless, this app doesn't target those platforms).

- [ ] **Step 3: Verify nothing else broke**

Run: `flutter analyze`
Expected: same pre-existing info-level issues as before this change, zero new ones.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add permission_handler for onboarding's camera/mic step"
```

---

### Task 2: `ILocationService.permissionStatus()`

**Files:**
- Modify: `lib/core/location/location_service.dart`
- Test: `test/core/location/location_service_test.dart`

**Interfaces:**
- Consumes: `package:geolocator/geolocator.dart`'s `Geolocator.checkPermission()`, `Geolocator.isLocationServiceEnabled()` (already imported in this file).
- Produces: `enum GpsPermissionStatus { notDetermined, granted, deniedForever, serviceDisabled }` and `Future<GpsPermissionStatus> ILocationService.permissionStatus()`, both consumed by Task 9's Location step.

- [ ] **Step 1: Write the failing test**

Add to `test/core/location/location_service_test.dart`, inside the existing `group('ILocationService contract', ...)`:

```dart
    test('permissionStatus defaults to notDetermined on the base contract', () async {
      // The base class gives every existing fake (and DisabledLocationService) an honest default
      // without each having to restate it — same trick willPromptForPermission already uses.
      const service = _FakeLocationServiceReturnsNull();
      expect(await service.permissionStatus(), GpsPermissionStatus.notDetermined);
    });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/location/location_service_test.dart`
Expected: FAIL — `permissionStatus` isn't defined on `ILocationService`.

- [ ] **Step 3: Add the enum and the method**

In `lib/core/location/location_service.dart`, add the enum above `ILocationService` (after the `GpsCoords` typedef):

```dart
/// Coarse permission status — enough for a caller to tell "already granted" apart from
/// "permanently denied" before ever showing a dialog. [willPromptForPermission] intentionally
/// can't answer this: its own doc comment explains why collapsing those two cases to `false` is
/// correct for its one existing caller. This is for a caller — onboarding — that needs to render
/// three different states instead of deciding whether to show one purpose sheet.
enum GpsPermissionStatus {
  /// Not yet asked, or asked and still allowed to ask again.
  notDetermined,
  granted,

  /// The OS will not show the dialog again; only the device's own Settings can change this now.
  deniedForever,

  /// Location services are off at the OS level entirely, independent of this app's permission.
  serviceDisabled,
}
```

Then add the method to `ILocationService` (concrete-with-a-default, same pattern as `willPromptForPermission`):

```dart
  /// See [GpsPermissionStatus]. Concrete so every fake and [DisabledLocationService] gets the
  /// honest "never asked" answer without restating it.
  Future<GpsPermissionStatus> permissionStatus() async => GpsPermissionStatus.notDetermined;
```

And override it in `LocationService` (the real implementation), right after `willPromptForPermission`:

```dart
  @override
  Future<GpsPermissionStatus> permissionStatus() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return GpsPermissionStatus.serviceDisabled;
      }
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.always ||
        LocationPermission.whileInUse => GpsPermissionStatus.granted,
        LocationPermission.deniedForever => GpsPermissionStatus.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => GpsPermissionStatus.notDetermined,
      };
    } catch (_) {
      return GpsPermissionStatus.notDetermined;
    }
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/location/location_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Add one more test covering the real mapping**

Still in the test file, add a second fake and test right after the one above:

```dart
class _FakeLocationServiceWithStatus extends ILocationService {
  const _FakeLocationServiceWithStatus(this._status);
  final GpsPermissionStatus _status;

  @override
  Future<GpsCoords?> getCurrentPosition() async => null;

  @override
  Future<GpsPermissionStatus> permissionStatus() async => _status;
}
```

```dart
    test('permissionStatus can report every state a caller needs to branch on', () async {
      for (final status in GpsPermissionStatus.values) {
        final service = _FakeLocationServiceWithStatus(status);
        expect(await service.permissionStatus(), status);
      }
    });
```

- [ ] **Step 6: Run the full location test file**

Run: `flutter test test/core/location/location_service_test.dart`
Expected: PASS, all tests.

- [ ] **Step 7: Run `flutter analyze`**

Expected: zero new issues.

- [ ] **Step 8: Commit**

```bash
git add lib/core/location/location_service.dart test/core/location/location_service_test.dart
git commit -m "feat(location): add permissionStatus() for onboarding's 3-state UI"
```

---

### Task 3: `NotificationService.authorizationStatus()`

**Files:**
- Modify: `lib/core/notifications/notification_service.dart`

**Interfaces:**
- Consumes: `package:firebase_messaging/firebase_messaging.dart`'s `AuthorizationStatus` enum (already imported in this file), the private `_messaging` field.
- Produces: `Future<AuthorizationStatus> NotificationService.authorizationStatus()`, consumed by Task 9's Notifiche step.

**Note on testing:** `NotificationService` holds `FirebaseMessaging.instance` directly (not injected), so it can only be exercised with a real `Firebase.initializeApp()` call, which nothing in this test suite does today — `hasPermission()`/`ensurePermission()` have no existing unit tests for the same reason. This task follows that existing precedent: verified by `flutter analyze` only, not a new test.

- [ ] **Step 1: Add the method**

In `lib/core/notifications/notification_service.dart`, add this method right after `hasPermission()`:

```dart
  /// Raw OS authorization status, for a caller that needs to tell "never asked" apart from "said
  /// no" — [hasPermission] deliberately collapses both to `false` for its one existing caller
  /// ("can I skip the purpose sheet"), which is correct there and not enough for onboarding's own
  /// three-state UI.
  Future<AuthorizationStatus> authorizationStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/core/notifications/notification_service.dart`
Expected: no issues.

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: same pass count as before this task (this method has no call sites yet, so nothing should change).

- [ ] **Step 4: Commit**

```bash
git add lib/core/notifications/notification_service.dart
git commit -m "feat(notifications): add authorizationStatus() for onboarding's 3-state UI"
```

---

### Task 4: Extract `PermissionPurposeCard` from the existing purpose sheet

**Files:**
- Create: `lib/core/widgets/permission_purpose_card.dart`
- Modify: `lib/core/widgets/permission_purpose_sheet.dart`
- Modify: `lib/core/widgets/widgets.dart` (barrel export, if `permission_purpose_sheet.dart`/similar widgets are exported there — check first)

**Interfaces:**
- Produces: `class PermissionPurposeCard extends StatelessWidget` (`icon`, `titolo`, `motivo`, `senzaDiEsso`), consumed by Task 8's `PermissionStepPage`.
- Consumes nothing new — pure extraction of existing visual code from `_PurposeSheet`.

- [ ] **Step 1: Check whether the barrel exports this file**

Run: `grep -n "permission_purpose_sheet" lib/core/widgets/widgets.dart`
If it prints a line, remember to add the new file there too in Step 4. If nothing prints, skip that part of Step 4.

- [ ] **Step 2: Create the extracted widget**

Create `lib/core/widgets/permission_purpose_card.dart`:

```dart
// dart format width=100
import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The icon/titolo/motivo/senzaDiEsso block `askPermissionPurpose`'s sheet renders — extracted so
/// the onboarding flow can show the exact same explanation as a full page instead of a sheet,
/// without duplicating the copy layout. Carries no buttons and no sheet chrome (grab handle,
/// bottom-sheet padding): callers supply both, since a sheet and a full onboarding page want
/// different ones.
class PermissionPurposeCard extends StatelessWidget {
  const PermissionPurposeCard({
    super.key,
    required this.icon,
    required this.titolo,
    required this.motivo,
    required this.senzaDiEsso,
  });

  final IconData icon;
  final String titolo;
  final String motivo;
  final String senzaDiEsso;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        border: Border.all(color: c.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.base,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titolo,
                    style: TextStyle(
                      fontFamily: 'Archivo Narrow',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              motivo,
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, height: 1.45, color: c.ink),
            ),
            const SizedBox(height: 10),
            Text(
              senzaDiEsso,
              style: TextStyle(fontFamily: 'Archivo', fontSize: 13, height: 1.45, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
```

(`AppRack.freeShape` in the original was `BorderRadius.all(Radius.circular(AppRack.cellRadius))` i.e. `Radius.circular(2)` — inlined the literal here since this file doesn't otherwise need the `AppRack` import; if that feels wrong on review, importing `AppRack` and using `AppRack.freeShape` directly is equally fine, just an import away.)

- [ ] **Step 3: Refactor `_PurposeSheet` to use it**

In `lib/core/widgets/permission_purpose_sheet.dart`, replace the `Row`/`Text`/`Text` block (everything between the grab-handle `Center` and the `SizedBox(height: 20)` before the buttons) with:

```dart
                PermissionPurposeCard(
                  icon: icon,
                  titolo: titolo,
                  motivo: motivo,
                  senzaDiEsso: senzaDiEsso,
                ),
```

Wait — `PermissionPurposeCard` already draws its own bordered box, but `_PurposeSheet` ALSO wraps everything (handle + content + buttons) in one bordered `DecoratedBox`. Nesting two bordered boxes would look wrong. Instead:

Change `_PurposeSheet.build` so the outer `DecoratedBox`'s border/surface styling moves onto just the card, and the sheet's own outer container becomes a plain `Padding` (no border) holding: grab handle, `PermissionPurposeCard`, spacing, buttons. Concretely, replace the whole `build` method with:

```dart
  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: c.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            PermissionPurposeCard(
              icon: icon,
              titolo: titolo,
              motivo: motivo,
              senzaDiEsso: senzaDiEsso,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: cta,
              onPressed: () => Navigator.of(context).pop(true),
              size: AppButtonSize.lg,
            ),
            const SizedBox(height: 8),
            AppButton.secondary(
              label: 'Non ora',
              onPressed: () => Navigator.of(context).pop(false),
              size: AppButtonSize.lg,
            ),
          ],
        ),
      ),
    );
  }
```

Add the import at the top of the file: `import 'permission_purpose_card.dart';`

This changes the sheet's visual result only in that the grab handle now sits above the bordered card rather than inside the same bordered box as the card — everything else (border, padding, text, buttons) renders identically. `askPermissionPurpose`'s function signature and the three existing call sites (`cantiere_timbra_screen.dart`, `step_dettagli.dart`, `impostazioni_screen.dart`) are untouched.

- [ ] **Step 4: Export the new file from the barrel, if needed**

If Step 1 found a match, add `export 'permission_purpose_card.dart';` next to the existing `permission_purpose_sheet.dart` export line in `lib/core/widgets/widgets.dart`.

- [ ] **Step 5: Run `flutter analyze`**

Run: `flutter analyze lib/core/widgets/permission_purpose_card.dart lib/core/widgets/permission_purpose_sheet.dart`
Expected: no issues.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: same pass count as before — this is a pure visual refactor of existing, already-exercised call sites (`cantiere_timbra_screen_test.dart`, `step_dettagli`-related tests, impostazioni tests), so nothing should newly fail. If any test asserts on the sheet's exact widget tree (rather than just the resulting text/behavior), fix that assertion to match the new structure.

- [ ] **Step 7: Commit**

```bash
git add lib/core/widgets/permission_purpose_card.dart lib/core/widgets/permission_purpose_sheet.dart lib/core/widgets/widgets.dart
git commit -m "refactor(widgets): extract PermissionPurposeCard for reuse by onboarding"
```

---

### Task 5: Extract the biometric-enable sequence into a shared function

**Files:**
- Create: `lib/features/altro/biometric_setup.dart`
- Modify: `lib/features/altro/impostazioni_screen.dart`
- Test: `test/features/altro/biometric_setup_test.dart`

**Interfaces:**
- Consumes: `biometricServiceProvider` (`IBiometricService.isAvailable()`, `.authenticate({required String reason})` — `lib/core/security/biometric_service.dart`), `impostazioniProvider.notifier.toggle(key: ...)` (`lib/features/altro/impostazioni_provider.dart`), `showAppToast`/`ToastTone` (`lib/core/widgets/app_toast.dart`).
- Produces: `Future<bool> enableBiometricLock(BuildContext context, WidgetRef ref)` — returns `true` only if the lock is now actually enabled. Consumed by Task 9's Blocco biometrico step and by the modified `impostazioni_screen.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/features/altro/biometric_setup_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/security/biometric_service.dart';
import 'package:tasktap_mobile/features/altro/biometric_setup.dart';
import 'package:tasktap_mobile/features/altro/impostazioni_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBiometricService implements IBiometricService {
  _FakeBiometricService({this.available = true, this.authenticates = true});
  final bool available;
  final bool authenticates;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => authenticates;
}

Widget _wrap(Widget child, {required IBiometricService biometrics}) {
  return ProviderScope(
    overrides: [biometricServiceProvider.overrideWithValue(biometrics)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('enables the lock when the device supports it and verification succeeds', (
    tester,
  ) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          },
        ),
        biometrics: _FakeBiometricService(),
      ),
    );
    await tester.pumpAndSettle();

    final result = await enableBiometricLock(capturedContext, capturedRef);

    expect(result, isTrue);
    expect(capturedRef.read(impostazioniProvider).autenticazioneBiometrica, isTrue);
  });

  testWidgets('does not enable the lock when the device has no biometrics enrolled', (
    tester,
  ) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          },
        ),
        biometrics: _FakeBiometricService(available: false),
      ),
    );
    await tester.pumpAndSettle();

    final result = await enableBiometricLock(capturedContext, capturedRef);
    await tester.pump();

    expect(result, isFalse);
    expect(capturedRef.read(impostazioniProvider).autenticazioneBiometrica, isFalse);
    expect(find.textContaining('Nessuna impronta'), findsOneWidget);
  });

  testWidgets('does not enable the lock when verification fails', (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          },
        ),
        biometrics: _FakeBiometricService(authenticates: false),
      ),
    );
    await tester.pumpAndSettle();

    final result = await enableBiometricLock(capturedContext, capturedRef);
    await tester.pump();

    expect(result, isFalse);
    expect(capturedRef.read(impostazioniProvider).autenticazioneBiometrica, isFalse);
    expect(find.textContaining('Verifica non riuscita'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/altro/biometric_setup_test.dart`
Expected: FAIL — `lib/features/altro/biometric_setup.dart` doesn't exist yet.

- [ ] **Step 3: Create the shared function**

Create `lib/features/altro/biometric_setup.dart`:

```dart
// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/biometric_service.dart';
import '../../core/widgets/app_toast.dart';
import 'impostazioni_provider.dart';

/// Attempts to turn the biometric lock on: checks the device actually has biometrics enrolled,
/// then proves the technician can pass the prompt right now, before persisting the setting.
/// Returns `true` only if the lock is now genuinely enabled.
///
/// Shared by Impostazioni's toggle and the onboarding flow so both go through the identical
/// sequence — a lock nobody can open is its own failure mode, and that was true the one time this
/// existed only inline in `impostazioni_screen.dart`.
Future<bool> enableBiometricLock(BuildContext context, WidgetRef ref) async {
  final service = ref.read(biometricServiceProvider);

  if (!await service.isAvailable()) {
    if (!context.mounted) return false;
    showAppToast(
      context,
      message:
          'Nessuna impronta o Face ID configurati su questo dispositivo. '
          'Aggiungili nelle impostazioni del telefono, poi riprova.',
      tone: ToastTone.warning,
    );
    return false;
  }

  final ok = await service.authenticate(
    reason: 'Conferma la tua identità per attivare il blocco biometrico',
  );

  if (!ok) {
    if (!context.mounted) return false;
    showAppToast(
      context,
      message: 'Verifica non riuscita. Blocco biometrico non attivato.',
      tone: ToastTone.error,
    );
    return false;
  }

  ref.read(impostazioniProvider.notifier).toggle(key: 'autenticazioneBiometrica');
  return true;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/altro/biometric_setup_test.dart`
Expected: PASS, all three tests.

- [ ] **Step 5: Wire `impostazioni_screen.dart` to use it**

In `lib/features/altro/impostazioni_screen.dart`, replace the body of `_toggleBiometrics` (everything from `final service = ref.read(biometricServiceProvider);` down to, but not including, the final closing brace) so the whole function reads:

```dart
Future<void> _toggleBiometrics(
  BuildContext context,
  WidgetRef ref,
  ImpostazioniState settings,
) async {
  final notifier = ref.read(impostazioniProvider.notifier);

  // Turning it off needs no ceremony: the user is already past the lock.
  if (settings.autenticazioneBiometrica) {
    notifier.toggle(key: 'autenticazioneBiometrica');
    return;
  }

  await enableBiometricLock(context, ref);
}
```

Add the import at the top of the file: `import 'biometric_setup.dart';`

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/features/altro/impostazioni_screen.dart lib/features/altro/biometric_setup.dart`
Expected: no issues. (`showAppToast`/`ToastTone` and `LucideIcons` imports that are now unused in `impostazioni_screen.dart`, if any, must be removed — check with the analyzer's `unused_import` warning.)

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: same pass count as before this task, plus the 3 new tests from Step 1 — no existing Impostazioni test regresses.

- [ ] **Step 8: Commit**

```bash
git add lib/features/altro/biometric_setup.dart lib/features/altro/impostazioni_screen.dart test/features/altro/biometric_setup_test.dart
git commit -m "refactor(altro): extract biometric-enable sequence for reuse by onboarding"
```

---

### Task 6: Onboarding completion persistence

**Files:**
- Create: `lib/features/onboarding/onboarding_provider.dart`
- Test: `test/features/onboarding/onboarding_provider_test.dart`

**Interfaces:**
- Consumes: `shared_preferences`'s `SharedPreferences.getInstance()`.
- Produces: `final onboardingCompletedProvider = AsyncNotifierProvider.family<OnboardingCompletedNotifier, bool, String>(OnboardingCompletedNotifier.new);` and `class OnboardingCompletedNotifier` with a `Future<void> markCompleted()` method. Consumed by Task 7 (router) and Task 9 (screen's final action).

- [ ] **Step 1: Write the failing test**

Create `test/features/onboarding/onboarding_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_provider.dart';

void main() {
  test('defaults to not completed for a user who has never finished onboarding', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container.read(onboardingCompletedProvider('user-1').future);

    expect(result, isFalse);
  });

  test('markCompleted persists per user id', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(onboardingCompletedProvider('user-1').future);
    await container.read(onboardingCompletedProvider('user-1').notifier).markCompleted();

    expect(await container.read(onboardingCompletedProvider('user-1').future), isTrue);
    // A different user on the same device has not completed it.
    expect(await container.read(onboardingCompletedProvider('user-2').future), isFalse);
  });

  test('reflects a flag already set by a previous app run', () async {
    SharedPreferences.setMockInitialValues({'onboarding.completed.user-3': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(onboardingCompletedProvider('user-3').future), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/onboarding/onboarding_provider_test.dart`
Expected: FAIL — `lib/features/onboarding/onboarding_provider.dart` doesn't exist.

- [ ] **Step 3: Create the provider**

Create `lib/features/onboarding/onboarding_provider.dart`:

```dart
// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether [userId] has completed the onboarding flow — per account, not per device, so a
/// technician signing into a shared/handed-down phone still gets it once for themselves.
///
/// Purely local device state with nothing to sync to a backend, unlike `impostazioniProvider`'s
/// settings — that's why this is its own small provider instead of folded into that one.
final onboardingCompletedProvider =
    AsyncNotifierProvider.family<OnboardingCompletedNotifier, bool, String>(
      OnboardingCompletedNotifier.new,
    );

class OnboardingCompletedNotifier extends FamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  /// Marks onboarding done for this notifier's user. The router's redirect gate re-reads this
  /// provider on the next rebuild it triggers (see `_OnboardingStateListenable` in
  /// `app_router.dart`) and stops sending this user back here.
  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(arg), true);
    state = const AsyncData(true);
  }

  static String _key(String userId) => 'onboarding.completed.$userId';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/onboarding/onboarding_provider_test.dart`
Expected: PASS, all three tests.

- [ ] **Step 5: Run `flutter analyze`**

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/onboarding/onboarding_provider.dart test/features/onboarding/onboarding_provider_test.dart
git commit -m "feat(onboarding): add per-account completion persistence"
```

---

### Task 7: Router gate

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Test: `test/presentation/providers/auth_providers_test.dart` (this is where the existing redirect-rule tests already live, per its own `// Router redirect logic` section header)

**Interfaces:**
- Consumes: `onboardingCompletedProvider` from Task 6, `authStateProvider` (existing).
- Produces: `AppRoutes.onboarding` (`'/onboarding'`) route path constant, and the router's third redirect branch — consumed by Task 9's route registration.

- [ ] **Step 1: Add the route constant**

In `lib/core/router/app_router.dart`, inside `abstract final class AppRoutes`, add near `login`:

```dart
  /// Shown once per account, right after first login, before Dashboard — see the router's
  /// `redirect` callback for the gate, and `docs/superpowers/specs/2026-09-17-onboarding-flow-design.md`
  /// for why this exists and why it's per-account rather than per-device.
  static const String onboarding = '/onboarding';
```

- [ ] **Step 2: Add the import**

Add near the other feature imports: `import '../../features/onboarding/onboarding_provider.dart';`

- [ ] **Step 3: Extend the `redirect` callback**

In the `redirect:` callback, the existing shape ends with:

```dart
      final authAsync = ref.read(authStateProvider);
      final isOnLogin = state.matchedLocation == AppRoutes.login;

      return authAsync.when(
        loading: () => null,
        error: (err, stack) => isOnLogin ? null : AppRoutes.login,
        data: (user) {
          final isAuthenticated = user != null;
          if (!isAuthenticated && !isOnLogin) return AppRoutes.login;
          if (isAuthenticated && isOnLogin) return AppRoutes.dashboard;
          return null;
        },
      );
    },
```

Replace the `data: (user) { ... }` branch so the whole callback becomes:

```dart
      final authAsync = ref.read(authStateProvider);
      final isOnLogin = state.matchedLocation == AppRoutes.login;
      final isOnOnboarding = state.matchedLocation == AppRoutes.onboarding;

      return authAsync.when(
        loading: () => null,
        error: (err, stack) => isOnLogin ? null : AppRoutes.login,
        data: (user) {
          final isAuthenticated = user != null;
          if (!isAuthenticated && !isOnLogin) return AppRoutes.login;
          if (isAuthenticated && isOnLogin) return AppRoutes.dashboard;
          if (!isAuthenticated) return null; // unauthenticated and already on /login

          // Onboarding gate — evaluated only once we know who's signed in.
          final onboardingAsync = ref.read(onboardingCompletedProvider(user.id));
          return onboardingAsync.when(
            loading: () => null,
            error: (err, stack) => null,
            data: (completed) {
              if (!completed && !isOnOnboarding) return AppRoutes.onboarding;
              if (completed && isOnOnboarding) return AppRoutes.dashboard;
              return null;
            },
          );
        },
      );
    },
```

- [ ] **Step 4: Add `_OnboardingStateListenable` and include it in `refreshListenable`**

Find `refreshListenable: Listenable.merge([_AuthStateListenable(ref), _KioskStateListenable(ref)]),` and change it to:

```dart
    refreshListenable: Listenable.merge([
      _AuthStateListenable(ref),
      _KioskStateListenable(ref),
      _OnboardingStateListenable(ref),
    ]),
```

Then add the new class right after `_KioskStateListenable`'s definition (near the bottom of the file, alongside `_AuthStateListenable`):

```dart
/// [Listenable] that notifies go_router whenever the signed-in user's onboarding-completion
/// status resolves or changes, so the redirect callback's onboarding gate (see [buildRouter])
/// re-runs once the async `SharedPreferences` read completes — it starts as loading, same as the
/// kiosk/auth gates do at cold start — and immediately when
/// `OnboardingCompletedNotifier.markCompleted` flips it.
///
/// Unlike [_AuthStateListenable]/[_KioskStateListenable], the provider being watched here is a
/// *family* keyed by user id, which isn't known until [authStateProvider] resolves — so this
/// listens to auth first, then (re)subscribes to the onboarding provider for whichever user is
/// currently signed in, tearing the old subscription down if the user changes.
class _OnboardingStateListenable extends ChangeNotifier {
  _OnboardingStateListenable(WidgetRef ref) {
    ref.listenManual(authStateProvider, (previous, next) {
      final userId = next.valueOrNull?.id;
      _subscription?.close();
      _subscription = userId == null
          ? null
          : ref.listenManual(
              onboardingCompletedProvider(userId),
              (prev, next) => notifyListeners(),
            );
      notifyListeners();
    }, fireImmediately: true);
  }

  ProviderSubscription<AsyncValue<bool>>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}
```

- [ ] **Step 5: Write the redirect-rule test**

In `test/presentation/providers/auth_providers_test.dart`, find the `// ── Router redirect logic ──` section and add a new test alongside the existing ones there (matching whatever style those use — they encode the redirect rules as plain functions/assertions without instantiating a real `GoRouter`, per that section's own comment). Add:

```dart
  group('onboarding redirect rule', () {
    // Mirrors app_router.dart's redirect callback's onboarding branch: given an authenticated
    // user and their onboarding-completion status, what should the redirect target be?
    String? onboardingRedirect({
      required bool isOnOnboarding,
      required bool completed,
    }) {
      if (!completed && !isOnOnboarding) return '/onboarding';
      if (completed && isOnOnboarding) return '/dashboard';
      return null;
    }

    test('not completed, not already there → sent to onboarding', () {
      expect(
        onboardingRedirect(isOnOnboarding: false, completed: false),
        '/onboarding',
      );
    });

    test('not completed, already on onboarding → stays put', () {
      expect(onboardingRedirect(isOnOnboarding: true, completed: false), isNull);
    });

    test('completed, on onboarding → sent to dashboard', () {
      expect(onboardingRedirect(isOnOnboarding: true, completed: true), '/dashboard');
    });

    test('completed, elsewhere → stays put', () {
      expect(onboardingRedirect(isOnOnboarding: false, completed: true), isNull);
    });
  });
```

- [ ] **Step 6: Run the new test**

Run: `flutter test test/presentation/providers/auth_providers_test.dart`
Expected: PASS, including the 4 new tests.

- [ ] **Step 7: Run `flutter analyze`**

Run: `flutter analyze lib/core/router/app_router.dart`
Expected: no issues.

- [ ] **Step 8: Run the full test suite**

Run: `flutter test`
Expected: same pass count as before plus 4 — router-dependent tests elsewhere (if any construct a real `GoRouter` with an authenticated user and no onboarding override) may now redirect to `/onboarding` unexpectedly. If any test fails this way, add `onboardingCompletedProvider(<that test's user id>).overrideWith(...)` returning `true` to that test's `ProviderScope` overrides, matching however that test already overrides `authRepositoryProvider`.

- [ ] **Step 9: Commit**

```bash
git add lib/core/router/app_router.dart test/presentation/providers/auth_providers_test.dart
git commit -m "feat(router): gate a newly authenticated user through onboarding once"
```

---

### Task 8: `PermissionStepPage` — the shared 3-state permission page

**Files:**
- Create: `lib/features/onboarding/permission_step_page.dart`
- Test: `test/features/onboarding/permission_step_page_test.dart`

**Interfaces:**
- Consumes: `PermissionPurposeCard` (Task 4), `AppButton`/`AppButtonSize` (`lib/core/widgets/app_button.dart`), `AppSpacing` (`lib/core/theme/app_spacing.dart`).
- Produces: `enum PermissionStepStatus { notDetermined, granted, deniedForever, unavailable }` and `class PermissionStepPage extends StatefulWidget` with constructor params `icon`, `titolo`, `motivo`, `senzaDiEsso`, `ctaLabel`, `checkStatus` (`Future<PermissionStepStatus> Function()`), `request` (`Future<PermissionStepStatus> Function()`), `onDone` (`VoidCallback`). Consumed by Task 9.

- [ ] **Step 1: Write the failing tests**

Create `test/features/onboarding/permission_step_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/onboarding/permission_step_page.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('not-yet-decided shows the purpose card with Consenti and Non ora', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.granted,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Posizione'), findsOneWidget);
    expect(find.text('Consenti'), findsOneWidget);
    expect(find.text('Non ora'), findsOneWidget);
  });

  testWidgets('tapping Consenti calls request and shows the granted state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.granted,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Consenti'));
    await tester.pumpAndSettle();

    expect(find.text('Consentito'), findsOneWidget);
    expect(find.text('Consenti'), findsNothing);
  });

  testWidgets('tapping Non ora calls onDone without calling request', (tester) async {
    var requested = false;
    var done = false;
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async {
            requested = true;
            return PermissionStepStatus.granted;
          },
          onDone: () => done = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Non ora'));
    await tester.pumpAndSettle();

    expect(requested, isFalse);
    expect(done, isTrue);
  });

  testWidgets('already granted on checkStatus skips straight to the granted state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.granted,
          request: () async => PermissionStepStatus.granted,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Consentito'), findsOneWidget);
    expect(find.text('Consenti'), findsNothing);
  });

  testWidgets('permanently denied on checkStatus offers Apri impostazioni, not Consenti', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.deniedForever,
          request: () async => PermissionStepStatus.deniedForever,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apri impostazioni'), findsOneWidget);
    expect(find.text('Consenti'), findsNothing);
  });

  testWidgets('request resolving to deniedForever switches the button to Apri impostazioni', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.camera_alt,
          titolo: 'Fotocamera',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.deniedForever,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Consenti'));
    await tester.pumpAndSettle();

    expect(find.text('Apri impostazioni'), findsOneWidget);
  });

  testWidgets('unavailable shows an explanatory message and no action button', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.fingerprint,
          titolo: 'Blocco biometrico',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Attiva',
          checkStatus: () async => PermissionStepStatus.unavailable,
          request: () async => PermissionStepStatus.unavailable,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attiva'), findsNothing);
    expect(find.text('Non ora'), findsOneWidget); // still a way to move on
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/onboarding/permission_step_page_test.dart`
Expected: FAIL — the file doesn't exist yet.

- [ ] **Step 3: Create the widget**

Create `lib/features/onboarding/permission_step_page.dart`:

```dart
// dart format width=100
import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/permission_purpose_card.dart';

/// Outcome of checking or requesting one permission, coarse enough to drive one shared UI for
/// every onboarding permission step regardless of which platform API backs it.
enum PermissionStepStatus {
  /// Not yet asked, or asked and still allowed to ask again.
  notDetermined,
  granted,

  /// The OS won't show its own dialog again — only Settings can change this now.
  deniedForever,

  /// This device/build can't honour the permission at all (e.g. no biometrics enrolled, Firebase
  /// unavailable) — no dialog to offer, real or otherwise.
  unavailable,
}

/// One page of the onboarding flow: explains a permission, then requests it.
///
/// Deliberately knows nothing about which permission it's for — [checkStatus] and [request] are
/// the only two places platform-specific logic enters, each supplied by the concrete step in
/// `onboarding_screen.dart`. This is what lets Location/Notifiche/Fotocamera e microfono/Blocco
/// biometrico share one implementation instead of four near-identical ones.
class PermissionStepPage extends StatefulWidget {
  const PermissionStepPage({
    super.key,
    required this.icon,
    required this.titolo,
    required this.motivo,
    required this.senzaDiEsso,
    required this.ctaLabel,
    required this.checkStatus,
    required this.request,
    required this.onDone,
  });

  final IconData icon;
  final String titolo;
  final String motivo;
  final String senzaDiEsso;

  /// Label for the primary action when the answer is still undecided — e.g. "Consenti la
  /// posizione". Not used once the state is [PermissionStepStatus.deniedForever] (the button
  /// becomes "Apri impostazioni" instead) or [PermissionStepStatus.granted]/[PermissionStepStatus.unavailable]
  /// (no primary button at all).
  final String ctaLabel;

  /// Read-only: must not itself trigger an OS dialog. Called once when the page first builds.
  final Future<PermissionStepStatus> Function() checkStatus;

  /// May trigger the real OS dialog. Called when the primary button is tapped.
  final Future<PermissionStepStatus> Function() request;

  /// Called when this step's decision is final — a skip ("Non ora"), a granted/unavailable state
  /// the technician has acknowledged, or (via the auto-advance below) shortly after granting.
  final VoidCallback onDone;

  @override
  State<PermissionStepPage> createState() => _PermissionStepPageState();
}

enum _Ui { loading, ask, granted, deniedForever, unavailable }

class _PermissionStepPageState extends State<PermissionStepPage> {
  _Ui _ui = _Ui.loading;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await widget.checkStatus();
    if (!mounted) return;
    setState(() => _ui = _uiFor(status));
    if (_ui == _Ui.granted) _scheduleAutoAdvance();
  }

  _Ui _uiFor(PermissionStepStatus status) => switch (status) {
    PermissionStepStatus.granted => _Ui.granted,
    PermissionStepStatus.deniedForever => _Ui.deniedForever,
    PermissionStepStatus.unavailable => _Ui.unavailable,
    PermissionStepStatus.notDetermined => _Ui.ask,
  };

  void _scheduleAutoAdvance() {
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _ui == _Ui.granted) widget.onDone();
    });
  }

  Future<void> _consenti() async {
    if (_busy) return;
    setState(() => _busy = true);
    final status = await widget.request();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ui = _uiFor(status);
    });
    if (_ui == _Ui.granted) _scheduleAutoAdvance();
  }

  @override
  Widget build(BuildContext context) {
    if (_ui == _Ui.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PermissionPurposeCard(
            icon: widget.icon,
            titolo: widget.titolo,
            motivo: widget.motivo,
            senzaDiEsso: widget.senzaDiEsso,
          ),
          const SizedBox(height: AppSpacing.lg),
          ..._actions(),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    switch (_ui) {
      case _Ui.loading:
        return const [];
      case _Ui.granted:
        return [
          GestureDetector(
            onTap: widget.onDone,
            child: const Text('Consentito', textAlign: TextAlign.center),
          ),
        ];
      case _Ui.unavailable:
        return [
          const Text('Non disponibile su questo dispositivo.', textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.base),
          AppButton.secondary(label: 'Non ora', onPressed: widget.onDone, size: AppButtonSize.lg),
        ];
      case _Ui.deniedForever:
        return [
          AppButton(label: 'Apri impostazioni', onPressed: widget.onDone, size: AppButtonSize.lg),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Non ora', onPressed: widget.onDone, size: AppButtonSize.lg),
        ];
      case _Ui.ask:
        return [
          AppButton(
            label: widget.ctaLabel,
            isLoading: _busy,
            onPressed: _busy ? null : _consenti,
            size: AppButtonSize.lg,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Non ora', onPressed: widget.onDone, size: AppButtonSize.lg),
        ];
    }
  }
}
```

Note: the "Apri impostazioni" button above calls `widget.onDone` directly rather than `openAppSettings()` — that's deliberate for this task, and Task 9 supplies the real settings-opening behavior. See Task 9 Step 4 for why (it needs `permission_handler`'s top-level `openAppSettings()`, which this file shouldn't import — it has no other reason to depend on that package, and keeping it out keeps this widget testable with zero platform channels).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/onboarding/permission_step_page_test.dart`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Run `flutter analyze`**

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/onboarding/permission_step_page.dart test/features/onboarding/permission_step_page_test.dart
git commit -m "feat(onboarding): add shared 3-state PermissionStepPage"
```

---

### Task 9: `OnboardingScreen` — wire the 4 real steps + Welcome

**Files:**
- Create: `lib/features/onboarding/onboarding_screen.dart`
- Test: `test/features/onboarding/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: `PermissionStepPage`/`PermissionStepStatus` (Task 8), `onboardingCompletedProvider` (Task 6), `ILocationService`/`GpsPermissionStatus`/`locationServiceProvider` (Task 2, existing), `NotificationService`/`AuthorizationStatus` (Task 3, existing), `enableBiometricLock`/`biometricServiceProvider` (Task 5, existing), `dictationServiceProvider`/`DictationCapability` (existing), `Permission`/`openAppSettings` from `permission_handler` (Task 1).
- Produces: `class OnboardingScreen extends ConsumerStatefulWidget`, consumed by Task 10's route registration.

- [ ] **Step 1: Write the failing tests**

Create `test/features/onboarding/onboarding_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_provider.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_screen.dart';

class _GrantingLocationService extends ILocationService {
  const _GrantingLocationService();

  @override
  Future<GpsCoords?> getCurrentPosition() async => (lat: 0, lng: 0, accuracy: null);

  @override
  Future<GpsPermissionStatus> permissionStatus() async => GpsPermissionStatus.granted;
}

Widget _wrap(String userId) {
  return ProviderScope(
    overrides: [
      locationServiceProvider.overrideWithValue(const _GrantingLocationService()),
    ],
    child: MaterialApp(home: OnboardingScreen(userId: userId)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the welcome page first', (tester) async {
    await tester.pumpWidget(_wrap('user-1'));
    await tester.pumpAndSettle();

    expect(find.text('Inizia'), findsOneWidget);
  });

  testWidgets('Inizia advances to the Location step', (tester) async {
    await tester.pumpWidget(_wrap('user-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();

    expect(find.text('Dove sei intervenuto'), findsOneWidget);
  });
}
```

(This is intentionally a thin smoke test, not one per permission step — `PermissionStepPage` already has full coverage in Task 8, and `NotificationService`/`DictationService`/`enableBiometricLock`'s own real behaviors are either untestable without Firebase (Task 3's documented limitation) or already covered by Task 5's tests. This test exists to prove the 5 pages are actually wired together in the right order with real copy, not to re-test the state machine.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/onboarding/onboarding_screen_test.dart`
Expected: FAIL — the file doesn't exist yet.

- [ ] **Step 3: Create the screen**

Create `lib/features/onboarding/onboarding_screen.dart`:

```dart
// dart format width=100
import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/dictation/dictation_service.dart';
import '../../core/icons/app_lucide_icons.dart';
import '../../core/location/location_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../altro/biometric_setup.dart';
import '../altro/impostazioni_provider.dart';
import 'onboarding_provider.dart';
import 'permission_step_page.dart';

/// One-time, post-login setup: explains and requests the four permissions/settings the app can
/// use, in the order a new technician is most likely to need them. See
/// `docs/superpowers/specs/2026-09-17-onboarding-flow-design.md` for why this exists and why each
/// step delegates to an existing service rather than inventing new permission logic.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  static const _pageCount = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_controller.page == null) return;
    final next = _controller.page!.round() + 1;
    if (next >= _pageCount) {
      ref.read(onboardingCompletedProvider(widget.userId).notifier).markCompleted();
      return; // The router's own redirect takes it from here.
    }
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg1,
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _WelcomePage(onNext: _next),
            PermissionStepPage(
              icon: LucideIcons.mapPin,
              titolo: 'Dove sei intervenuto',
              motivo:
                  'La posizione viene registrata quando timbri su un cantiere, come prova di dove '
                  'sei intervenuto.',
              senzaDiEsso: 'Puoi comunque timbrare e compilare rapportini: resteranno senza '
                  'coordinate.',
              ctaLabel: 'Consenti la posizione',
              checkStatus: () async =>
                  _fromGps(await ref.read(locationServiceProvider).permissionStatus()),
              request: () async {
                final coords = await ref.read(locationServiceProvider).getCurrentPosition();
                return coords != null
                    ? PermissionStepStatus.granted
                    : _fromGps(await ref.read(locationServiceProvider).permissionStatus());
              },
              onDone: _next,
            ),
            PermissionStepPage(
              icon: LucideIcons.bell,
              titolo: 'Avvisi sul lavoro',
              motivo:
                  'Ti avvisiamo quando ti viene assegnato un intervento, quando cambia un '
                  'appuntamento e quando un rapportino ha bisogno di te.',
              senzaDiEsso:
                  'Senza notifiche l\'app funziona lo stesso: trovi tutto in Dashboard e in '
                  'Calendario, ma lo scopri quando apri l\'app.',
              ctaLabel: 'Attiva le notifiche',
              checkStatus: () async {
                if (!NotificationService.isAvailable) return PermissionStepStatus.unavailable;
                return _fromAuthorization(await NotificationService.instance.authorizationStatus());
              },
              request: () async {
                if (!NotificationService.isAvailable) return PermissionStepStatus.unavailable;
                final granted = await NotificationService.instance.ensurePermission();
                return granted
                    ? PermissionStepStatus.granted
                    : _fromAuthorization(await NotificationService.instance.authorizationStatus());
              },
              onDone: _next,
            ),
            PermissionStepPage(
              icon: LucideIcons.camera,
              titolo: 'Fotocamera e microfono',
              motivo:
                  'La fotocamera serve per allegare foto dell\'intervento al rapportino; il '
                  'microfono per dettare la descrizione invece di scriverla.',
              senzaDiEsso: 'Puoi comunque compilare i rapportini a mano, senza foto.',
              ctaLabel: 'Consenti',
              checkStatus: _cameraMicStatus,
              request: _cameraMicRequest,
              onDone: _next,
            ),
            PermissionStepPage(
              icon: LucideIcons.fingerprint,
              titolo: 'Blocco biometrico',
              motivo:
                  'Richiedi impronta o Face ID all\'apertura dell\'app, a protezione dei dati di '
                  'clienti e interventi su questo dispositivo.',
              senzaDiEsso: 'Puoi attivarlo in qualsiasi momento da Impostazioni.',
              ctaLabel: 'Attiva',
              checkStatus: () async {
                final settings = ref.read(impostazioniProvider);
                if (settings.autenticazioneBiometrica) return PermissionStepStatus.granted;
                final available = await ref.read(biometricServiceProvider).isAvailable();
                return available ? PermissionStepStatus.notDetermined : PermissionStepStatus.unavailable;
              },
              request: () async {
                final enabled = await enableBiometricLock(context, ref);
                return enabled ? PermissionStepStatus.granted : PermissionStepStatus.notDetermined;
              },
              onDone: _next,
            ),
          ],
        ),
      ),
    );
  }

  Future<PermissionStepStatus> _cameraMicStatus() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    if (camera.isGranted && mic.isGranted) return PermissionStepStatus.granted;
    if (camera.isPermanentlyDenied || mic.isPermanentlyDenied) {
      return PermissionStepStatus.deniedForever;
    }
    return PermissionStepStatus.notDetermined;
  }

  Future<PermissionStepStatus> _cameraMicRequest() async {
    final cameraResult = await Permission.camera.request();
    // Mic's actual grant still goes through DictationService, not permission_handler, so the app
    // keeps exactly one place that decides "dictation actually works" (capability + permission
    // together) — see step_dettagli.dart's own capability() call for the other consumer of this.
    final micCapability = await ref.read(dictationServiceProvider).capability();
    final micStatus = await Permission.microphone.status;
    if (cameraResult.isGranted && micCapability.microphoneGranted) {
      return PermissionStepStatus.granted;
    }
    if (cameraResult.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
      return PermissionStepStatus.deniedForever;
    }
    return PermissionStepStatus.notDetermined;
  }

  PermissionStepStatus _fromGps(GpsPermissionStatus status) => switch (status) {
    GpsPermissionStatus.granted => PermissionStepStatus.granted,
    GpsPermissionStatus.deniedForever => PermissionStepStatus.deniedForever,
    GpsPermissionStatus.serviceDisabled ||
    GpsPermissionStatus.notDetermined => PermissionStepStatus.notDetermined,
  };

  PermissionStepStatus _fromAuthorization(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PermissionStepStatus.granted,
    AuthorizationStatus.denied => PermissionStepStatus.deniedForever,
    AuthorizationStatus.notDetermined => PermissionStepStatus.notDetermined,
  };
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Benvenuto in TaskTap',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Archivo Narrow',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Configuriamo insieme i permessi di cui TaskTap ha bisogno per funzionare al meglio '
            'sul campo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Archivo', fontSize: 15, color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Inizia', onPressed: onNext, size: AppButtonSize.lg),
        ],
      ),
    );
  }
}
```

For the "Apri impostazioni" action promised in Task 8's step: since `PermissionStepPage`'s `deniedForever` button currently calls `widget.onDone` directly (per Task 8's note), and this screen is the one place allowed to import `permission_handler`, give `PermissionStepPage` one more optional constructor parameter for this rather than hardcoding `_next` — go back and add to `permission_step_page.dart` (Task 8's file):

```dart
    required this.onDone,
    this.onOpenSettings,
```

```dart
  /// Opens the OS's app-settings page, when the permission is permanently denied. Defaults to
  /// [onDone] (treat "open settings" the same as "move on") for a step where opening settings
  /// isn't meaningful — none of onboarding's four steps take that default; each supplies a real
  /// settings-opening callback.
  final VoidCallback? onOpenSettings;
```

And in `_actions()`'s `_Ui.deniedForever` case, change the first button to:

```dart
          AppButton(
            label: 'Apri impostazioni',
            onPressed: widget.onOpenSettings ?? widget.onDone,
            size: AppButtonSize.lg,
          ),
```

Then back in `onboarding_screen.dart`, add `onOpenSettings: () => openAppSettings(),` to all four `PermissionStepPage` instances (right after each `onDone: _next,` line).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/onboarding/onboarding_screen_test.dart test/features/onboarding/permission_step_page_test.dart`
Expected: PASS. (Re-running Task 8's test file confirms the added `onOpenSettings` parameter didn't change any existing behavior, since it's optional and defaults to `onDone`.)

- [ ] **Step 5: Run `flutter analyze`**

Expected: no issues.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/features/onboarding/onboarding_screen.dart lib/features/onboarding/permission_step_page.dart test/features/onboarding/onboarding_screen_test.dart
git commit -m "feat(onboarding): wire Welcome + Location + Notifiche + Fotocamera e microfono + Blocco biometrico"
```

---

### Task 10: Register the route and final verification

**Files:**
- Modify: `lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: `OnboardingScreen` (Task 9), `authStateProvider` (existing — to read the current user's id for the route's `builder`).

- [ ] **Step 1: Add the import**

Add near the other feature imports in `lib/core/router/app_router.dart`: `import '../../features/onboarding/onboarding_screen.dart';`

- [ ] **Step 2: Register the route**

Add, right after the `AppRoutes.login` `GoRoute` (from Task 7's context):

```dart
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) {
          final userId = ref.read(authStateProvider).valueOrNull?.id;
          // The redirect gate never lands here without an authenticated user (see Task 7), so
          // this is unreachable in practice — the empty-string fallback just satisfies the type
          // system rather than crashing if it somehow were.
          return OnboardingScreen(userId: userId ?? '');
        },
      ),
```

- [ ] **Step 3: Run `flutter analyze` on the whole project**

Run: `flutter analyze`
Expected: zero new issues compared to before Task 1 (same pre-existing info-level ones only).

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 5: Manual smoke check (documented, not automated — no emulator in this environment)**

If a device/emulator is available: sign in with a fresh account (or clear the app's local storage / uninstall-reinstall) and confirm the flow appears once, each "Non ora" advances without an OS dialog, each "Consenti" fires the real OS dialog, and signing out and back in with the same account goes straight to Dashboard. If no device is available here, say so explicitly rather than claiming this was checked — this repo has hit that exact instruction before (see `docs/superpowers/specs/2026-09-17-onboarding-flow-design.md`'s own review process).

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat(onboarding): register /onboarding route"
```

- [ ] **Step 7: Push**

```bash
git push origin develop
```

---

## Self-Review Notes

- **Spec coverage:** Router gating (Task 7), Persistence (Task 6), Screens/5-page PageView (Task 9), per-step wiring table's 4 rows (Task 9's four `PermissionStepPage` instances), new dependency (Task 1), biometric refactor (Task 5), the two small service additions the design's own self-review added (Tasks 2–3), error handling states (`unavailable`/`deniedForever` — Task 8's state machine), testing section (a test per task). No spec section is without a task.
- **Type consistency check:** `GpsPermissionStatus`/`AuthorizationStatus`/`PermissionStatus` (three different enums from three different sources) are all funneled through `PermissionStepStatus` via the two private `_from...` mapping functions in Task 9 — `PermissionStepPage` itself (Task 8) never sees the platform-specific enums, only `PermissionStepStatus`. `onDone`/`onOpenSettings`/`checkStatus`/`request` signatures match between Task 8's definition and Task 9's call sites.
- **No placeholders:** every step above has real, complete code — the one deliberately-deferred piece (`PermissionStepPage`'s `onOpenSettings` default) is explained, not left vague, and is filled in within the same task.
