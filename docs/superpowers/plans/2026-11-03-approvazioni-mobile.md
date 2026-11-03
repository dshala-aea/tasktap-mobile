# Mobile Approval Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `presenze.absence.approve` holders one mobile screen to see the tenant's pending absence and smart-working requests, with requester names, and approve or reject them.

**Architecture:** A new capability-gated `/altro/approvazioni` route with two tabs. Each tab reads its existing list endpoint with `status=0` and no `userId`, resolves requester names from the shared `/api/users` directory, and posts to the existing approve/reject routes. The existing self-service screens are untouched; only notification routing learns to send submitted-request taps to the new screen.

**Tech Stack:** Flutter 3.44.4 / Dart 3.12, Riverpod, go_router, Dio, the existing design-system widgets and `flutter_test`/`mocktail`.

**Spec:** `docs/superpowers/specs/2026-11-03-approvazioni-mobile-design.md`

## Global Constraints

- No new dependencies and no server changes.
- Capability key is exactly `presenze.absence.approve`.
- Pending status ordinal is `0`; reject reason is required and at most 1000 characters.
- The tenant-wide read omits `userId` and sends `status=0`.
- The requester name resolves `requestedByUserId`, never `createdByUserId`.
- All user-facing copy is Italian, matching the existing screens.
- Reads and decisions are online-only; a decision is refused before the POST when offline.
- The existing `/altro/ferie` and `/altro/smart-working` screens keep their current behaviour.
- Status labels come from the existing `absenceStatusLabel`; date labels use `DateFormat(..., 'it')`.

## Review Focus

- An approve-holder without `team.user.read`: the queue still renders and decisions still work; names show `—`, never a raw GUID.
- A request decided on another device: the 400 closes the reject sheet, refreshes the queue, and the approver cannot retry a terminal row forever.
- Offline before a decision: no POST is attempted and the row stays pending.
- A Submitted notification with no `relatedEntityId`: it opens the approval queue, not the notification detail page.
- A double tap on Approva: exactly one POST.

---

## File Structure

**Modified**
- `lib/data/ferie/absence_request_api_client.dart` — pending queue + approve/reject.
- `lib/data/smart_working/smart_working_request_api_client.dart` — same.
- `lib/features/admin/squadre/admin_squadra_list_screen.dart` — use the shared directory provider.
- `lib/features/admin/squadre/admin_squadra_detail_screen.dart` — use the shared name helper.
- `lib/core/router/app_router.dart` — route constant, route, requirement.
- `lib/features/altro/altro_hub_screen.dart` — capability-gated tile.
- `lib/core/notifications/notification_service.dart` — type-aware deep links.
- `test/data/ferie/absence_request_api_client_test.dart`
- `test/data/smart_working/smart_working_request_api_client_test.dart`
- `test/core/notifications/deep_link_intent_test.dart`
- `test/core/notifications/notification_deep_link_test.dart`
- `test/core/router/app_router_route_requirement_redirect_test.dart`
- `test/features/altro/altro_hub_screen_test.dart`

**Created**
- `lib/data/users/user_directory.dart` — shared active/all user directory, `userDisplayName`, `userNameByIdProvider`.
- `lib/features/approvazioni/approvazioni_providers.dart` — the two queue providers.
- `lib/features/approvazioni/approval_request_card.dart` — the pending-request card.
- `lib/features/approvazioni/reject_reason_sheet.dart` — the mandatory-reason sheet.
- `lib/features/approvazioni/approvazioni_screen.dart` — header, tabs, lists, states, decisions.
- `test/data/users/user_directory_test.dart`
- `test/features/approvazioni/approval_request_card_test.dart`
- `test/features/approvazioni/approvazioni_screen_test.dart`
- `test/features/approvazioni/approvazioni_providers_test.dart`

---

### Task 1: Absence approval API operations

**Files:**
- Modify: `lib/data/ferie/absence_request_api_client.dart`
- Test: `test/data/ferie/absence_request_api_client_test.dart`

**Interfaces:**
- Produces:
  - `Future<List<AbsenceRequestDto>> fetchPendingForApproval()`
  - `Future<void> approve(String id)`
  - `Future<void> reject(String id, {required String reason})`
- All three live on `AbsenceRequestApiClient` and go through its existing `_guarded`.

- [ ] **Step 1: Write the failing tests**

Append to `test/data/ferie/absence_request_api_client_test.dart`:

```dart
group('AbsenceRequestApiClient — approvals', () {
  test('fetchPendingForApproval_sendsStatusZeroAndNoUserId', () async {
    final adapter = _Adapter(body: jsonEncode([_row()]));
    final client = _client(adapter);

    final rows = await client.fetchPendingForApproval();

    expect(rows.single.id, 'ar-1');
    expect(adapter.captured!.path, '/api/absence-requests');
    expect(adapter.captured!.queryParameters['status'], 0);
    expect(adapter.captured!.queryParameters.containsKey('userId'), isFalse);
  });

  test('approve_postsToTheApproveRoute', () async {
    final adapter = _Adapter(body: '{}');
    final client = _client(adapter);

    await client.approve('ar-1');

    expect(adapter.captured!.method, 'POST');
    expect(adapter.captured!.path, '/api/absence-requests/ar-1/approve');
  });

  test('reject_postsTheTrimmedReason', () async {
    final adapter = _Adapter(body: '{}');
    final client = _client(adapter);

    await client.reject('ar-1', reason: '  Copertura insufficiente  ');

    expect(adapter.captured!.method, 'POST');
    expect(adapter.captured!.path, '/api/absence-requests/ar-1/reject');
    expect(adapter.captured!.data, {'reason': 'Copertura insufficiente'});
  });

  test('a_400_detail_becomes_the_validation_error', () async {
    final adapter = _Adapter(
      status: 400,
      body: jsonEncode({'detail': 'Solo una richiesta in attesa può essere approvata o rifiutata.'}),
    );
    final client = _client(adapter);

    await expectLater(
      client.approve('ar-1'),
      throwsA(
        isA<AbsenceRequestValidationError>().having(
          (e) => e.detail,
          'detail',
          contains('in attesa'),
        ),
      ),
    );
  });
});
```

The existing `_Adapter` must accept a `status` (default 200) and return it; extend it exactly as
`test/data/smart_working/smart_working_request_api_client_test.dart` already does.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/ferie/absence_request_api_client_test.dart`
Expected: FAIL — `fetchPendingForApproval` and friends are not defined.

- [ ] **Step 3: Implement the three methods on `AbsenceRequestApiClient`**

```dart
/// GET /api/absence-requests?status=0 with no `userId`: the tenant-wide pending queue for an
/// Approve holder (the server's own resolved scope, see the file doc). Online-only.
Future<List<AbsenceRequestDto>> fetchPendingForApproval() => _guarded(() async {
  final res = await _dio.get<List<dynamic>>(
    '/api/absence-requests',
    queryParameters: const {'status': 0},
  );
  final list = res.data ?? [];
  return list.cast<Map<String, dynamic>>().map(AbsenceRequestDto.fromJson).toList();
});

/// POST /api/absence-requests/{id}/approve. The server tolerates an omitted body; send `{}`.
Future<void> approve(String id) => _guarded(() async {
  await _dio.post<dynamic>('/api/absence-requests/$id/approve', data: const <String, dynamic>{});
});

/// POST /api/absence-requests/{id}/reject. The reason is required by the server and max 1000.
Future<void> reject(String id, {required String reason}) => _guarded(() async {
  await _dio.post<dynamic>('/api/absence-requests/$id/reject', data: {'reason': reason.trim()});
});
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/ferie/absence_request_api_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/ferie/absence_request_api_client.dart test/data/ferie/absence_request_api_client_test.dart
git commit -m "feat(approvazioni): absence approval queue and decisions"
```

---

### Task 2: Smart-working approval API operations

**Files:**
- Modify: `lib/data/smart_working/smart_working_request_api_client.dart`
- Test: `test/data/smart_working/smart_working_request_api_client_test.dart`

**Interfaces:**
- Produces the same three signatures as Task 1, on `SmartWorkingRequestApiClient`.

- [ ] **Step 1: Write the failing tests**

Append the mirrored group to
`test/data/smart_working/smart_working_request_api_client_test.dart` (the `_Adapter` already takes a
status):

```dart
group('SmartWorkingRequestApiClient — approvals', () {
  test('fetchPendingForApproval_sendsStatusZeroAndNoUserId', () async {
    final adapter = _Adapter(body: jsonEncode([_row()]));
    final client = _client(adapter);

    final rows = await client.fetchPendingForApproval();

    expect(rows.single.id, 'sw-1');
    expect(adapter.captured!.path, '/api/smart-working-requests');
    expect(adapter.captured!.queryParameters['status'], 0);
    expect(adapter.captured!.queryParameters.containsKey('userId'), isFalse);
  });

  test('approve_postsToTheApproveRoute', () async {
    final adapter = _Adapter(body: '{}');
    final client = _client(adapter);

    await client.approve('sw-1');

    expect(adapter.captured!.method, 'POST');
    expect(adapter.captured!.path, '/api/smart-working-requests/sw-1/approve');
  });

  test('reject_postsTheTrimmedReason', () async {
    final adapter = _Adapter(body: '{}');
    final client = _client(adapter);

    await client.reject('sw-1', reason: '  Servizio scoperto  ');

    expect(adapter.captured!.path, '/api/smart-working-requests/sw-1/reject');
    expect(adapter.captured!.data, {'reason': 'Servizio scoperto'});
  });

  test('a_400_detail_becomes_the_validation_error', () async {
    final adapter = _Adapter(
      status: 400,
      body: jsonEncode({'detail': 'Solo una richiesta in attesa può essere approvata o rifiutata.'}),
    );
    final client = _client(adapter);

    await expectLater(
      client.reject('sw-1', reason: 'x'),
      throwsA(isA<SmartWorkingValidationError>()),
    );
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/smart_working/smart_working_request_api_client_test.dart`
Expected: FAIL — the three methods are not defined.

- [ ] **Step 3: Implement the same three methods on `SmartWorkingRequestApiClient`**

Use the paths `/api/smart-working-requests`, `/{id}/approve`, `/{id}/reject`, and the same
`status: 0`, empty body, trimmed reason and `_guarded` wrapper as Task 1.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/smart_working/smart_working_request_api_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/smart_working/smart_working_request_api_client.dart test/data/smart_working/smart_working_request_api_client_test.dart
git commit -m "feat(approvazioni): smart-working approval queue and decisions"
```

---

### Task 3: Shared user directory and display names

**Files:**
- Create: `lib/data/users/user_directory.dart`
- Modify: `lib/features/admin/squadre/admin_squadra_list_screen.dart` (replace the local provider)
- Modify: `lib/features/admin/squadre/admin_squadra_detail_screen.dart` (use the shared helper)
- Test: `test/data/users/user_directory_test.dart`

**Interfaces:**
- Produces:
  - `String userDisplayName(Map<String, dynamic> user)`
  - `final allUsersProvider = FutureProvider.family.autoDispose<List<Map<String, dynamic>>, bool>((ref, activeOnly) => …)`
  - `final userNameByIdProvider = FutureProvider.autoDispose<Map<String, String>>(…)` — returns `{}` on any failure.
- Consumes: `adminApiClientProvider` and `AdminApiClient.fetchAllUsersWithSquadraInfo(activeOnly: …)`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/users/user_directory_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/users/user_directory.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';

class _FakeAdminApi extends AdminApiClient {
  _FakeAdminApi(this.rows, {this.error}) : super(Dio());

  final List<Map<String, dynamic>> rows;
  final Object? error;

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async {
    if (error != null) throw error!;
    return rows;
  }
}

void main() {
  test('userDisplayName_prefers_displayName_then_fullName_then_parts', () {
    expect(userDisplayName({'displayName': 'Mario Rossi'}), 'Mario Rossi');
    expect(userDisplayName({'fullName': 'Mario Rossi'}), 'Mario Rossi');
    expect(userDisplayName({'firstName': 'Mario', 'lastName': 'Rossi'}), 'Mario Rossi');
    expect(userDisplayName({'firstName': '', 'lastName': ''}), 'Utente senza nome');
  });

  test('userNameByIdProvider_maps_ids_and_falls_back_to_empty_on_error', () async {
    final rows = [
      {'id': 'u1', 'fullName': 'Mario Rossi'},
      {'id': 'u2', 'firstName': 'Anna', 'lastName': 'Bianchi'},
      {'fullName': 'No id'},
    ];

    final ok = ProviderContainer(
      overrides: [adminApiClientProvider.overrideWithValue(_FakeAdminApi(rows))],
    );
    addTearDown(ok.dispose);
    expect(await ok.read(userNameByIdProvider.future), {
      'u1': 'Mario Rossi',
      'u2': 'Anna Bianchi',
    });

    final failed = ProviderContainer(
      overrides: [adminApiClientProvider.overrideWithValue(_FakeAdminApi(const [], error: Exception('403')))],
    );
    addTearDown(failed.dispose);
    expect(await failed.read(userNameByIdProvider.future), isEmpty);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/users/user_directory_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Create `lib/data/users/user_directory.dart`**

Implement `userDisplayName` with the existing order (`displayName`, `fullName`,
`firstName + lastName`, then `'Utente senza nome'`), `allUsersProvider` delegating to
`adminApiClientProvider`, and `userNameByIdProvider` catching any failure and returning `const {}`.
Add a file doc explaining that names are cosmetic and never block the approval queue.

- [ ] **Step 4: Point the squadra screens at the shared code**

In `admin_squadra_list_screen.dart`, delete the local `allUsersWithSquadraProvider` and change its
two readers to `ref.watch(allUsersProvider(true))`. In `admin_squadra_detail_screen.dart`, delete
`_memberOptionLabel` and call `userDisplayName` from the new file.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/data/users/user_directory_test.dart test/features/admin/squadre`
Expected: PASS (the squadra suites still pass).

- [ ] **Step 6: Commit**

```bash
git add lib/data/users/user_directory.dart lib/features/admin/squadre test/data/users/user_directory_test.dart
git commit -m "refactor(users): share the tenant user directory and display names"
```

---

### Task 4: Approval queue providers

**Files:**
- Create: `lib/features/approvazioni/approvazioni_providers.dart`
- Test: `test/features/approvazioni/approvazioni_providers_test.dart`

**Interfaces:**
- Produces:
  - `final absenceApprovalQueueProvider = FutureProvider.autoDispose<List<AbsenceRequestDto>>(…)`
  - `final smartWorkingApprovalQueueProvider = FutureProvider.autoDispose<List<SmartWorkingRequestDto>>(…)`
- Consumes: the two API clients from Tasks 1–2.

- [ ] **Step 1: Write the failing tests**

Create `test/features/approvazioni/approvazioni_providers_test.dart` with two tests that override
`absenceRequestApiClientProvider` / `smartWorkingRequestApiClientProvider` with `mocktail` mocks,
stub `fetchPendingForApproval`, read the provider and assert the rows are returned and the method
was called once.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/approvazioni/approvazioni_providers_test.dart`
Expected: FAIL — the providers do not exist.

- [ ] **Step 3: Create the providers**

Each provider simply watches its API client provider and returns `fetchPendingForApproval()`. Add a
file doc: online-only, no mirror, the screen owns invalidation after a decision.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/approvazioni/approvazioni_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/approvazioni/approvazioni_providers.dart test/features/approvazioni/approvazioni_providers_test.dart
git commit -m "feat(approvazioni): pending queues as providers"
```

---

### Task 5: The approval request card

**Files:**
- Create: `lib/features/approvazioni/approval_request_card.dart`
- Test: `test/features/approvazioni/approval_request_card_test.dart`

**Interfaces:**
- Produces:

```dart
class ApprovalRequestCard extends StatelessWidget {
  const ApprovalRequestCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.reason,
    required this.onApprove,
    required this.onReject,
    this.busy = false,
  });

  final String title;
  final String subtitle;
  final String? reason;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool busy;
}
```

- [ ] **Step 1: Write the failing widget tests**

Cover: title/subtitle/reason render; a null or blank reason renders nothing; tapping Approva/Rifiuta
fires the callbacks; `busy: true` disables both buttons. Pump the card in a `MaterialApp` with the
app theme.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/approvazioni/approval_request_card_test.dart`
Expected: FAIL — the widget does not exist.

- [ ] **Step 3: Implement the card**

Use the existing design-system widgets (`AppCard`, `AppButton`, `StatusPill` only if needed),
`AppSpacing`/`context.colors`, requester name as `title`, the period/reason as `subtitle`, and a
footer row with two equal buttons. Buttons carry tooltips/semantic labels that include `title`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/approvazioni/approval_request_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/approvazioni/approval_request_card.dart test/features/approvazioni/approval_request_card_test.dart
git commit -m "feat(approvazioni): pending request card"
```

---

### Task 6: The Approvazioni screen shell and lists

**Files:**
- Create: `lib/features/approvazioni/approvazioni_screen.dart`
- Test: `test/features/approvazioni/approvazioni_screen_test.dart`

**Interfaces:**
- Produces: `class ApprovazioniScreen extends ConsumerStatefulWidget { const ApprovazioniScreen({super.key, this.initialTab}); final String? initialTab; }`
- Consumes: Tasks 3–5, `isOnlineProvider`, `ErrorState`, `UnavailableState`, `EmptyState`, `ScreenHeader`.

- [ ] **Step 1: Write the failing widget tests**

With providers overridden (queue providers, `userNameByIdProvider`, `isOnlineProvider`), cover:
- The header and both chips render; the default tab is Ferie e permessi.
- An absence row shows the requester name, type label, period, and reason.
- Switching to Smart working shows its rows.
- An empty queue shows "Nessuna richiesta da approvare".
- A thrown queue shows `ErrorState` with retry.
- `isOnlineProvider == false` shows the offline `UnavailableState`.
- An unknown requester id renders `—`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/approvazioni/approvazioni_screen_test.dart`
Expected: FAIL — the screen does not exist.

- [ ] **Step 3: Implement the screen shell and both lists**

Read `initialTab` (`assenze` | `smart-working`), default to `assenze`. Render a `ScreenHeader`, two
`ChoiceChip`s, and the selected tab's provider with the standard loading/error/offline/empty
branches. Format absence periods with `DateFormat('d MMM', 'it')` and times `HH:MM`; smart working
uses the civil dates only. Build `ApprovalRequestCard`s with temporary no-op callbacks (Task 7 wires
them). Do not fetch the inactive tab.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/approvazioni/approvazioni_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/approvazioni/approvazioni_screen.dart test/features/approvazioni/approvazioni_screen_test.dart
git commit -m "feat(approvazioni): the screen and its two pending lists"
```

---

### Task 7: Approve and reject from the screen

**Files:**
- Create: `lib/features/approvazioni/reject_reason_sheet.dart`
- Modify: `lib/features/approvazioni/approvazioni_screen.dart`
- Test: `test/features/approvazioni/approvazioni_screen_test.dart`

**Interfaces:**
- Produces: `Future<String?> showRejectReasonSheet(BuildContext context, {required String title})` —
  returns the trimmed reason, or null when cancelled.
- Consumes: the API clients, `ensureOnlineOrWarn`, `showAppToast`, `confirmDeleteDialog`-style
  confirmation.

- [ ] **Step 1: Write the failing tests**

Add tests that:
- Tap Approva → a confirmation dialog appears; confirm → `approve(id)` called once and the queue
  invalidated; cancel → no call.
- Tap Rifiuta → the sheet opens; the submit is disabled for empty/whitespace; typing enables it; the
  trimmed reason is sent.
- A 400 `AbsenceRequestValidationError` closes the sheet, shows the detail and refreshes the queue.
- A non-400 failure keeps the sheet open with the reason.
- Offline: no API call and the existing offline feedback.
- A double tap on Approva sends one POST.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/approvazioni/approvazioni_screen_test.dart`
Expected: FAIL — the actions are not wired.

- [ ] **Step 3: Implement the sheet and the decision flows**

`showRejectReasonSheet` returns a modal bottom sheet with a `TextField(maxLength: 1000)`, a helper
line and a submit button disabled until `text.trim().isNotEmpty`. In the screen, keep a
`Set<String> _busyIds`; guard `ensureOnlineOrWarn` before any POST; call
`client.approve(id)` / `client.reject(id, reason: reason)`; on success invalidate the entity's
queue provider **and** its own-list provider, clear the busy id and toast. On a 400
`*ValidationError`, close the sheet, invalidate and show `e.detail`; on other errors keep the sheet
open and toast the generic message.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/approvazioni/approvazioni_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/approvazioni test/features/approvazioni/approvazioni_screen_test.dart
git commit -m "feat(approvazioni): approve and reject pending requests"
```

---

### Task 8: Route, guard and Altro tile

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/altro/altro_hub_screen.dart`
- Test: `test/core/router/app_router_route_requirement_redirect_test.dart`
- Test: `test/features/altro/altro_hub_screen_test.dart`

**Interfaces:**
- Produces:
  - `AppRoutes.altroApprovazioni = '/altro/approvazioni'`
  - `String AppRoutes.approvazioni({String? tab})`
  - A route requirement `('/altro/approvazioni', RouteRequirement.capability('presenze.absence.approve'), null)`
  - An Altro tile visible only when `cachedEntitlement.capabilities.contains('presenze.absence.approve')`.

- [ ] **Step 1: Write the failing tests**

In `app_router_route_requirement_redirect_test.dart`, add a case: navigating to
`/altro/approvazioni` with the capability denied lands on `ForbiddenScreen`; with it granted, renders
`ApprovazioniScreen`. Override the two queue providers with empty lists (and
`userNameByIdProvider` with `{}`) in that test so the screen renders without a network call. In
`altro_hub_screen_test.dart`, assert the tile is absent without the capability and present with it
(pump the hub with an `Entitlement` carrying the key).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/router/app_router_route_requirement_redirect_test.dart test/features/altro/altro_hub_screen_test.dart`
Expected: FAIL — the route/tile does not exist.

- [ ] **Step 3: Implement the route, guard and tile**

Add the constant and helper, the `GoRoute(path: 'approvazioni')` inside the `altro` subtree with
`initialTab: state.uri.queryParameters['tab']`, the requirement entry before `/altro/ferie`, the
router import, and the capability-filtered tile in `_buildGestioneTiles` using
`entitlement?.capabilities.contains('presenze.absence.approve') ?? false`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/router/app_router_route_requirement_redirect_test.dart test/features/altro/altro_hub_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/altro/altro_hub_screen.dart test/core/router test/features/altro/altro_hub_screen_test.dart
git commit -m "feat(approvazioni): capability-gated route and Altro tile"
```

---

### Task 9: Type-aware notification routing

**Files:**
- Modify: `lib/core/notifications/notification_service.dart`
- Test: `test/core/notifications/deep_link_intent_test.dart`
- Test: `test/core/notifications/notification_deep_link_test.dart`

**Interfaces:**
- Produces: `DeepLinkIntent({required entityType, required entityId, String? notificationType, String? notificationId})`
- `resolveRoute` sends `AbsenceRequest` / `SmartWorkingRequest` +
  `notificationType == 'AbsenceRequestSubmitted'` to the approval route with the right tab; every
  other combination keeps today's routes.

- [ ] **Step 1: Write the failing tests**

Update the two notification test files:
- Submitted + `AbsenceRequest` → `/altro/approvazioni?tab=assenze`.
- Submitted + `SmartWorkingRequest` → `/altro/approvazioni?tab=smart-working`.
- Submitted with an empty `entityId` still reaches the queue (and with no `entityType` defaults to
  the assenze tab).
- Decided + either entity → the existing self-service route.
- An unknown/missing type keeps today's routes.
- Existing push tests that construct `DeepLinkIntent` directly keep compiling (the new parameter is
  optional).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/notifications/deep_link_intent_test.dart test/core/notifications/notification_deep_link_test.dart`
Expected: FAIL — Submitted still resolves to the self-service lists.

- [ ] **Step 3: Implement the type-aware routing**

Add `notificationType` to `DeepLinkIntent`; pass `type` in `fromNotification`; handle the Submitted
cases before the entity-id gate and in `resolveRoute`; keep the existing fallbacks. Do not change
`kNotificationTypeRoutes` or the informational-types set.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/notifications`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/notifications/notification_service.dart test/core/notifications
git commit -m "feat(approvazioni): submitted-request notifications open the queue"
```

---

### Task 10: Final verification

- [ ] **Step 1: Run the targeted suites**

```bash
flutter test test/data/ferie test/data/smart_working test/data/users test/features/approvazioni test/core/notifications test/core/router test/features/altro
```

Expected: all PASS.

- [ ] **Step 2: Run the analyzer**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Confirm the contract snapshot is unchanged**

```bash
git status --short test/contract
```

Expected: empty — the endpoints already exist in the snapshot, so no refresh is needed. If a
required generation command was missed, run `dart run build_runner build --delete-conflicting-outputs`
and commit only generated files that legitimately changed.

- [ ] **Step 4: Commit any verification fixups**

Commit only if a test or analyzer fix was needed.
