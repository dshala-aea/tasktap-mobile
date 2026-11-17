# Smart Working — Mobile (S5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A technician can file and withdraw a smart-working request from the phone, see their own requests, and gets a "Smart working" chip and a usable punch button on an approved remote day.

**Architecture:** Mirrors the existing Ferie/permessi feature one folder across: a feature-local API client over Dio, a Riverpod `FutureProvider` for the list, two screens behind the `/altro` hub, and one additive change to the timbratura screen. The approved-day flag rides the `/auth/me` response that already populates the entitlement cache, but is held in memory only — never in Drift — so a stale device reads it as *unknown* and the punch button stays visible.

**Tech Stack:** Flutter 3.44, Riverpod, Dio, Drift (untouched here), Lucide icons, `intl` with the Italian locale initialised at startup.

**Spec:** `docs/superpowers/specs/2026-10-28-smart-working-design.md` (slices S1–S6; this is S5)

## Global Constraints

- **Italian only, hard-coded literals.** This repo has no `.arb` files, no `flutter_localizations`, no generated l10n. Add strings as inline Italian literals, as `ticket_list_screen.dart:479` does.
- **No schema step.** No Drift table, no `build_runner` run, no migration, no addition to the mobile sync payload. The backend ships no smart-working entity in `/api/Sync/mobile`, so an offline mirror is not buildable in this slice.
- **Online-only list and writes.** Reads go to the server; a write while offline is refused with the existing `ensureOnlineOrWarn` notice, never queued.
- **Civil dates never shift.** `startDate`/`endDate` are `yyyy-MM-dd`; parse with `parseDateOnly` from `lib/core/time/business_time.dart:35`, format with `formatDateOnly`. Never `DateTime.parse` (it yields UTC and shifts the day in a positive-offset zone), never `.toUtc()`.
- **Reuse, do not fork:** `kAbsenceStatusLabels`/`absenceStatusLabel` (`lib/data/ferie/absence_request_api_client.dart:63`), `StatusPill` (`lib/core/widgets/status_pill.dart:17`), `AppCompartmentTile` (`lib/core/widgets/app_compartment_tile.dart:12`), `ensureOnlineOrWarn` (`lib/core/utils/offline_guard.dart:38`).
- **Route gate:** module `presenze` only, via the table at `app_router.dart:334`, matching `/altro/ferie`.
- **Contract provenance.** `test/contract/openapi.snapshot.json` has been copied from api PR #183 (`feat/smart-working @ ce730202`), which is **not merged to master**. If that PR's contract changes before it merges, re-copy and re-run the contract tests; the plan's snapshot facts are only valid against that commit.
- **Verification:** `flutter analyze` stays clean and `flutter test` passes. CI (`mobile/.github/workflows/ci.yml:55`) runs the whole suite — a directory-scoped run is not evidence.

## Review Focus

1. **An approve-holder must never see the tenant-wide queue in a screen titled "le mie richieste".** The server returns everyone's rows to a caller holding `PresenzeAbsenceApprove` when `userId` is omitted, so the client always sends its own id.
2. **An unknown flag must never hide the punch button.** This is a deliberate inversion of the "never offer a method the server will reject" doctrine: hiding the button strands the person the feature exists for. Only an explicit `false` may hide it.
3. **The chip may not survive a cold start.** The flag is memory-only; after a process restart, or a logout, the screen must read *unknown*, not the last known `true`.
4. **A civil date must render as the same calendar day** the approver saw, on a device whose zone is not the tenant's.
5. **An offline submit must be refused visibly**, never silently dropped and never queued into a queue that does not exist for this entity.

---

### Task 1: Contract copy, DTO and `SmartWorkingRequestApiClient`

**Files:**
- Modify: `test/contract/openapi.snapshot.json` (already copied — verify, do not re-copy from a local api ref)
- Modify: `test/contract/request_body_contract_test.dart`, `test/contract/openapi_contract_test.dart`
- Create: `lib/data/smart_working/smart_working_request_api_client.dart`
- Test: `test/data/smart_working/smart_working_request_api_client_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
```dart
class SmartWorkingRequestDto {
  final String id;
  final String requestedByUserId;
  final String createdByUserId;
  final DateTime startDate;        // civil date, midnight local, from "yyyy-MM-dd"
  final DateTime endDate;
  final String? reason;
  final int status;                // AbsenceRequestStatusEnum ordinals: 0..3
  final String? decidedByUserId;
  final DateTime? decidedAt;
  final String? decisionReason;
  factory SmartWorkingRequestDto.fromJson(Map<String, dynamic> json);
}

/// Thrown on a 400 whose body carries `detail` (the server's Italian, actionable prose).
class SmartWorkingValidationError implements Exception {
  const SmartWorkingValidationError(this.detail);
  final String detail;
}

class SmartWorkingRequestApiClient {
  SmartWorkingRequestApiClient(this._dio);
  Future<List<SmartWorkingRequestDto>> fetchMine({String? userId});
  Future<String> create({required DateTime startDate, required DateTime endDate, String? reason});
  Future<void> cancel(String id);
}

final smartWorkingRequestApiClientProvider = Provider<SmartWorkingRequestApiClient>(...);
// Reads the caller's own id, then lists with it explicitly:
//   final userId = await ref.watch(internalUserIdProvider.future);
//   return ref.watch(smartWorkingRequestApiClientProvider).fetchMine(userId: userId);
final mySmartWorkingRequestsProvider = FutureProvider.autoDispose<List<SmartWorkingRequestDto>>(...);
```

- [ ] **Step 1: Verify the snapshot** — `grep -c "smart-working-requests" test/contract/openapi.snapshot.json` must print `5`. Record in the report which schema components the copy added (`CreateSmartWorkingRequestBody`, `DecideSmartWorkingRequestBody`, and whether a response schema exists — it does not: the list 200 and GET-by-id 200 declare `content?: never`, because the controller returns the raw entity).

- [ ] **Step 2: Write the failing tests** — `test/data/smart_working/smart_working_request_api_client_test.dart`, using the same fake-Dio-adapter style as `test/data/ferie/absence_request_api_client_test.dart`:
  - `fromJson_ParsesEveryEntityField` — a full entity body plus a null-reason one
  - `fromJson_UnknownStatus_ClampsToALabel` — `status: 99` renders, does not throw
  - `fetchMine_AlwaysSendsTheCallersOwnUserId` — asserts the request query carries `userId` (the approve-holder rule; see Review Focus 1)
  - `create_SendsIsoCivilDatesAndOmitsAnEmptyReason`
  - `create_SendsTheReasonWhenPresent`
  - `create_400WithDetail_BecomesValidationError` — the detail string is preserved verbatim
  - `cancel_PostsToTheCancelRoute`
  - and in `request_body_contract_test.dart`, a `smart working` group asserting the create body's keys match the snapshot's `CreateSmartWorkingRequestBody`; in `openapi_contract_test.dart`, assert the three schema names exist.

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/data/smart_working/smart_working_request_api_client_test.dart test/contract/request_body_contract_test.dart`
Expected: FAIL — the client and DTO do not exist.

- [ ] **Step 4: Implement** — `lib/data/smart_working/smart_working_request_api_client.dart`, opening with a `// ═══` header comment naming the four endpoints and the "marker, never hours" rule, like `CantiereWorklogApiClient`. `fetchMine` sends `userId` only when the caller supplies one; `mySmartWorkingRequestsProvider` supplies it from the existing `internalUserIdProvider` (persisted by `EntitlementService.refresh` from `/api/Auth/me`), so the screen is always self-scoped. Reuse `formatDateOnly`/`parseDateOnly` and `kAbsenceStatusLabels`; add no second status enum and no duplicate date codec.

- [ ] **Step 5: Run** the named tests and then the four contract files by full path.
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add test/contract lib/data/smart_working test/data/smart_working
git commit -m "feat(smart-working): contract sync, dto and request api client"
```

---

### Task 2: `smartWorkingToday` on `/auth/me`, held in memory only

**Files:**
- Modify: `lib/data/entitlements/entitlement_service.dart`, `lib/data/entitlements/entitlement_repository.dart`, `lib/data/entitlements/entitlement_providers.dart`
- Test: `test/data/entitlements/smart_working_flag_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `bool? smartWorkingTodayFor(String? userId)` on `EntitlementRepository` (null = unknown, and null for any caller who is not the owner the flag was set for), `void setSmartWorkingToday(bool? value, {required String ownerId})`, and
```dart
/// null = unknown (never refreshed, or the process restarted). Callers must fail OPEN on null.
final smartWorkingTodayProvider = Provider<bool?>((ref) => ...);
```

- [ ] **Step 1: Write the failing tests**
  - `refresh_True_SetsTheFlagTrue`
  - `refresh_False_SetsTheFlagFalse`
  - `refresh_WhenTheFieldIsAbsent_LeavesTheFlagUnknown` — an old server or a trimmed body
  - `coldStart_FromTheDriftCache_ReportsUnknown` — write an `Entitlements` row, construct a fresh repository, assert `smartWorkingToday == null`
  - `logout_ClearsTheFlagToUnknown`

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — `entitlement_service.dart` parses `body['smartWorkingToday']` as `bool?` beside `clockInMethod` (`:78`) and passes it to the repository. The repository keeps it in a private field, **not** a Drift column: `Entitlements` (`app_database.dart:354-390`) is unchanged, no migration is added, and the write path never persists it. `entitlement_providers.dart` gains `smartWorkingTodayProvider` beside `effectiveClockInMethodProvider` (`:57-60`).

- [ ] **Step 4: Run** → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/data/entitlements test/data/entitlements
git commit -m "feat(smart-working): carry the approved-day flag from /auth/me, in memory only"
```

---

### Task 3: Chip and fail-open on the timbratura screen

**Files:**
- Modify: `lib/features/timbra/timbra_screen.dart`
- Test: `test/features/timbra/smart_working_chip_test.dart`

**Interfaces:**
- Consumes: `smartWorkingTodayProvider` (Task 2), `effectiveClockInMethodProvider` (existing).
- Produces: nothing other than the rendered behaviour.

- [ ] **Step 1: Write the failing widget tests** — harness copied from `test/features/timbra/timbra_screen_test.dart:429-488` (which already overrides `effectiveClockInMethodProvider` with `'QrOnly'`/`'Both'` and fakes the clock):
  - `qrOnly_withUnknownFlag_stillShowsThePunchButton` ← the spec's core inversion
  - `qrOnly_withFlagFalse_hidesThePunchButton`
  - `qrOnly_withFlagTrue_showsThePunchButtonAndTheChip`
  - `bothMethod_withFlagTrue_showsTheChip`
  - `bothMethod_withUnknownFlag_showsNoChip`

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — in `content` (`timbra_screen.dart:183-227`), insert the chip immediately after the guard `AnimatedSize` and before the `if (clockInMethod == 'QrOnly')` branch, so it sits above the punch button in both the fixed and scrolling layouts:
```dart
if (smartWorking == true) ...[
  const _SmartWorkingChip(),
  const SizedBox(height: AppSpacing.md),
],
```
and change the branch condition itself so only an explicit `false` hides the button:
```dart
final hidePunch = clockInMethod == 'QrOnly' && smartWorking == false;
```
`_SmartWorkingChip` is a small private widget in the same file: a rounded pill reading `Smart working`, using the same visual language as `_QrRequiredNotice` (`:507-528`) but neutral-positive rather than warning, with `Semantics(label: 'Giornata di smart working approvata')`.

- [ ] **Step 4: Run** → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/features/timbra test/features/timbra
git commit -m "feat(smart-working): chip and fail-open punch on an approved remote day"
```

---

### Task 4: Altro entry, routes and the request list

**Files:**
- Modify: `lib/features/altro/altro_hub_screen.dart`, `lib/core/router/app_router.dart`
- Create: `lib/features/smart_working/smart_working_list_screen.dart`
- Test: `test/features/smart_working/smart_working_list_screen_test.dart`, `test/features/altro/altro_hub_screen_test.dart` (extend if present)

**Interfaces:**
- Consumes: `mySmartWorkingRequestsProvider`, `SmartWorkingRequestDto` (Task 1).
- Produces:
```dart
// app_router.dart, beside altroFerie (:219)
/// Self-service smart working against `/api/smart-working-requests` — a marker, never hours.
static const String altroSmartWorking = '/altro/smart-working';
```
Route subtree mirroring `ferie` (`app_router.dart:721-731`): `smart-working` → list, child `nuovo` → form with `parentNavigatorKey: rootNavigatorKey`. Route table entry `('/altro/smart-working', const RouteRequirement.module('presenze'), null)` beside `/altro/ferie` (`:334`).

- [ ] **Step 1: Write the failing tests**
  - `tile_opensTheSmartWorkingScreen` (Altro hub)
  - `listsRequestsNewestFirst`
  - `emptyState_asksForANewRequest`
  - `pendingRow_offersCancel_afterConfirmation`
  - `approvedRow_isStillCancellable` — status 1 is a cancellable state
  - `cancelledRow_offersNoAction`
  - `row_rendersTheCivilDatesAndTheStatusPill`

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — the Altro tile immediately after the Ferie block (`altro_hub_screen.dart:168-173`), same tuple shape, `icon: LucideIcons.laptop` (if the pinned lucide version lacks it, `LucideIcons.home`), `label: 'Smart working'`, `module: 'presenze'`. The list screen mirrors `ferie_permessi_list_screen.dart`: `AppBar('Smart working')`, FAB `'Nuova richiesta'` pushing `altroSmartWorking` + `/nuovo`, rows showing `'${formatDateOnly(startDate)} – ${formatDateOnly(endDate)}'`, a `StatusPill(stato: absenceStatusLabel(item.status))`, an optional reason line, and a cancel action only for status `0` or `1`, behind a confirm dialog, invalidating `mySmartWorkingRequestsProvider` on success.

- [ ] **Step 4: Run** → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/features/smart_working lib/features/altro lib/core/router test/features
git commit -m "feat(smart-working): altro entry, routes and my-requests list"
```

---

### Task 5: Request form

**Files:**
- Create: `lib/features/smart_working/smart_working_form_screen.dart`
- Test: `test/features/smart_working/smart_working_form_screen_test.dart`

**Interfaces:**
- Consumes: `SmartWorkingRequestApiClient.create` (Task 1), `ensureOnlineOrWarn` (existing), `SmartWorkingValidationError`.
- Produces: nothing other than the screen.

- [ ] **Step 1: Write the failing widget tests** — harness copied from `test/features/ferie/ferie_permessi_form_screen_test.dart:41-55` (ProviderScope overrides + `initializeDateFormatting('it', null)`), with a local `_FakeSmartWorkingRequestApiClient` that records calls:
  - `creates_withTheDefaultTodayDates`
  - `endBeforeStart_showsTheItalianError_andNeverCallsTheApi`
  - `rangeOver366Days_isRefusedBeforeTheRoundTrip`
  - `backdatedStart_isRefusedBeforeTheRoundTrip`
  - `offline_submit_isRefusedWithTheOfflineNotice_andNeverCallsTheApi`
  - `serverDetail_isShownVerbatim` — a `SmartWorkingValidationError` reaches the snackbar text unchanged
  - `success_popsTheScreen_andRefreshesTheList`

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — a two-field form (start date, end date) plus an optional note, reusing the date-picker idiom of `ferie_permessi_form_screen.dart:17-200` but without the type dropdown or partial-time fields. Client-side validation mirrors the server's three range rules with the server's own Italian wording so the two cannot drift in the user's eyes. The submit path is `ensureOnlineOrWarn` → `create` → invalidate `mySmartWorkingRequestsProvider` → toast `'Richiesta di smart working inviata'` → `pop`.

- [ ] **Step 4: Run** → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/features/smart_working/smart_working_form_screen.dart test/features/smart_working
git commit -m "feat(smart-working): request form with range validation"
```

---

### Task 6: Notification deep link

**Files:**
- Modify: `lib/core/notifications/notification_service.dart`
- Test: `test/core/notifications/notification_deep_link_test.dart` (extend)

**Interfaces:**
- Consumes: `AppRoutes.altroSmartWorking` (Task 4).
- Produces: `resolveRoute` handles `'SmartWorkingRequest'`.

- [ ] **Step 1: Write the failing test**
  - `smartWorkingRequestNotification_routesToTheSmartWorkingList` — a notification with `relatedEntityType: 'SmartWorkingRequest'` resolves to `AppRoutes.altroSmartWorking`; and the pair still works when `relatedEntityId` is an id no screen can resolve, because the route is the list.

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — one case in `resolveRoute` (`notification_service.dart:384-397`), beside `'AbsenceRequest'` (`:393`):
```dart
case 'SmartWorkingRequest':
  return AppRoutes.altroSmartWorking;
```
The notification *types* are the existing `AbsenceRequestSubmitted`/`AbsenceRequestDecided`, so `notifiche_screen.dart:251-252`'s icon mapping needs no change. Leave the unknown-type fallback (`null`, then `kNotificationTypeRoutes`) untouched.

- [ ] **Step 4: Run** → PASS, then the full suite.

- [ ] **Step 5: Commit**
```bash
git add lib/core/notifications test/core
git commit -m "feat(smart-working): route the smart-working notification to its list"
```

---

## Self-review notes

- **Offline mirror is deliberately absent.** The absence feature gained a Drift mirror on `origin/main`, but the backend ships no smart-working entity in `/api/Sync/mobile`, so nothing could populate one. The list therefore needs a signal; that is stated in Global Constraints rather than discovered at review.
- **The list is self-scoped by argument, not by server policy.** `fetchMine({String? userId})` exists specifically so Task 1's provider can pass the persisted `internal_user_id`; without it an approve-holder gets the tenant queue.
- **Two client-side surfaces for one rule.** The form validates ranges locally and the server validates again; the local messages copy the server's Italian wording, which is the only way both agree without shipping a shared resource.
- **S6 (calendar overlay) is not here.** It is a web slice and is optional by the spec.
