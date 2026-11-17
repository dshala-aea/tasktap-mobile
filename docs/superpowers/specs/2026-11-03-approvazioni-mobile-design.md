# Mobile approval queue for absences and smart working

**Date:** 2026-11-03
**Status:** design, awaiting approval
**Feature area:** presenze — approvals

## Intent

A user who holds `presenze.absence.approve` (`PermissionCatalogue.PresenzeAbsenceApprove`) must be
able to open the mobile app, see every **pending** ferie/permesso and smart-working request in the
tenant, see **who** filed each one, and approve or reject it. They keep their own self-service
screens for their own requests.

Today the mobile app has only the self-service screens (`/altro/ferie`, `/altro/smart-working`).
Their clients always send the caller's own id on purpose, so an approver sees only their own rows.
The API client comments say the approval queue "does not exist yet" and "lives only on web".

Notifications already exist: a new request notifies every approver (`AbsenceRequestSubmitted`), but
the tap currently resolves to the approver's **own** list, where the new request is not shown. This
feature closes that loop.

## Goals

- One capability-gated "Approvazioni" screen on mobile with two tabs: **Ferie e permessi** and
  **Smart working**.
- Each tab lists the tenant's **pending** requests (`status = 0`) with the requester's display name,
  the request details, and the request's own reason when present.
- Approve and reject from the row. Reject requires a reason (server rule), 1000 characters max.
- Approvers keep their existing self-service screens unchanged.
- Notifications for a submitted request open the approval queue on the right tab; decision
  notifications keep opening the requester's own list.
- Honest online-only behaviour: explicit loading, empty, offline, error, and per-row in-flight
  states. Decisions never queue offline.

## Non-goals

- Decided-request history. `/api/approval-history` stays web-only for now.
- A per-request detail screen; the row carries everything needed to decide.
- Approval badges or unread counts on the tile/tab.
- Multi-step approval chains, delegation, or self-approval rules.
- Filing requests on someone else's behalf.
- Any server change. The endpoints, permissions and payloads already exist.

## Anti-goals

- Showing the tenant-wide queue to a user who cannot approve.
- Letting a rejection leave the phone without a reason.
- Rendering a failed queue read as "nothing to approve".
- Queueing a decision offline and telling the approver it was sent.
- Falling back to raw user ids in the requester column.

## Constraints (verified)

- `GET /api/absence-requests` and `GET /api/smart-working-requests` with **no** `userId` return the
  whole tenant only for an Approve holder; everyone else gets their own rows. The queue must omit
  `userId` and add `status=0`.
- Both list responses are the raw entities. They carry `requestedByUserId` and `createdByUserId`,
  never a name. The approval row names the **subject of the request**, so it resolves
  `requestedByUserId`; a request filed by an office user on an employee's behalf must show the
  employee, not the person who tapped "invia". Names come from `GET /api/users`, which requires
  `team.user.read`. Office and Admin hold it by default
  (`DefaultPermissionMatrix`: Office gets `AllReads() + AllWrites() + Approvals()`); a tenant that
  revokes it must still be able to approve, so the queue degrades to "—" rather than failing.
- `POST /api/absence-requests/{id}/approve` and `/reject`; the smart-working routes mirror them.
  Reject requires `{reason}` (server 400 `reject_reason_required`), max 1000 characters. A request
  already decided elsewhere answers 400 with the server's Italian `detail` (`not_pending`).
- Status is a bare ordinal: 0 Pending, 1 Approved, 2 Rejected, 3 Cancelled. Labels already exist
  (`absenceStatusLabel`).
- Absence rows carry type, start/end dates, optional start/end times, and a reason. Smart-working
  rows carry a civil-date window and a reason; they never carry hours.
- The route guard supports `RouteRequirement.capability('presenze.absence.approve')`.
- The user directory already exists as `allUsersWithSquadraProvider` in
  `features/admin/squadre/admin_squadra_list_screen.dart`; it calls
  `AdminApiClient.fetchAllUsersWithSquadraInfo`. The display-name derivation lives as a private
  `_memberOptionLabel` in `admin_squadra_detail_screen.dart`.
- Notification routing (`DeepLinkIntent`) switches only on `entityType` today. The notification
  `type` is already available at both call sites (`intentFromPushData`, the in-app list tap) but is
  dropped before `resolveRoute`.
- The endpoints are already in `test/contract/openapi.snapshot.json`; no contract refresh is needed.

## Approaches considered

**A — Approval sections inside the existing screens.** Add a "Da approvare" section above the
self-service list on `/altro/ferie` and `/altro/smart-working`, gated by capability. Mirrors the web
page, no new routes, and the existing notification deep links already land there. Rejected: mixes
the approver's own worklist with the tenant queue, gives no single place for both queues, and makes
the self-service screens carry two different responsibilities.

**B — One "Approvazioni" screen with two tabs (chosen).** A new capability-gated route
`/altro/approvazioni`, a tile in the Altro hub visible only to approvers, and type-aware notification
routing. The two self-service screens stay untouched. This is the only option that gives approvers
one discoverable worklist for both entities and makes submitted-request notifications land on the
work, matching the existing admin-screen pattern.

**C — Two separate approval sub-screens.** `/altro/ferie/approvazioni` and
`/altro/smart-working/approvazioni`, opened from each self-service screen. Rejected: duplicates the
list frame, loading/error/empty states and decision plumbing for no benefit over B.

## The design

### Screen and navigation

- New route `AppRoutes.altroApprovazioni = '/altro/approvazioni'` inside the existing `altro`
  subtree.
- Route requirement: `RouteRequirement.capability('presenze.absence.approve')`, added to
  `_routeRequirements` before the broader `/altro/ferie` entry. A non-approver deep-linking to it is
  redirected to `/forbidden`, like the other admin routes.
- Altro hub: a new "Approvazioni" tile next to Ferie and Smart working. It is rendered only when
  `cachedEntitlementProvider` holds `presenze.absence.approve` (fail-closed: no cache means hidden).
  Icon: `LucideIcons.clipboardCheck` (or the closest existing check-list glyph).
- The screen is `ApprovazioniScreen`, a `ConsumerStatefulWidget` that owns the selected tab:
  - Header: `ScreenHeader(title: 'Approvazioni', subtitle: '<n> in attesa')` when the selected tab
    has loaded rows.
  - A two-option selector (two `ChoiceChip`s styled like the existing list filters) carrying
    "Ferie e permessi" and "Smart working".
  - The initial tab comes from the `tab` query parameter (`assenze` | `smart-working`), so a push can
    open the right queue; switching tabs is local state and does not rewrite the URL.
  - Only the selected tab's queue provider is watched. Switching tabs loads the other one on demand;
    both providers are `autoDispose` and re-fetch on the next open.
- The app's own self-service screens are unchanged. An approver reaches them from the existing
  Ferie/Permessi and Smart working tiles, exactly as today.

### Rows

Each pending request is a card (not a dense table). Layout:

- Header line: requester display name (bold) + type label for absences; `—` when the name cannot be
  resolved.
- Body:
  - Absence: `12 mar – 14 mar`, plus `dalle HH:MM alle HH:MM` when the request carries times; the
    request's `reason`, if any.
  - Smart working: `12 mar – 14 mar`; the request's `reason`, if any.
- Footer: two equal buttons, **Approva** (primary) and **Rifiuta** (outline/danger), disabled while a
  decision for that row is in flight. A spinner replaces the acted row's actions.
- Pending-only, so no status pill is needed; the screen itself is the status.

Approve opens a confirmation dialog naming the requester and period ("Approvare la richiesta di
Mario Rossi dal 12 al 14 marzo?"). Confirm sends the decision; cancel does nothing. This is a
deliberate safety choice on a touch device — a decision has no undo route.

Reject opens a modal bottom sheet with a labelled multiline field (`maxLength: 1000`, autofocus),
helper text "Il motivo è obbligatorio", and a **Rifiuta** action disabled until the trimmed text is
non-empty. Submit sends the trimmed reason. On success the sheet closes and the queue refreshes; on
`not_pending` the sheet closes, the queue refreshes, and the server's message is shown; on other
failures the sheet stays open with the error toast so the reason is not lost.

### Data layer

Add to `AbsenceRequestApiClient` and `SmartWorkingRequestApiClient`:

- `fetchPendingForApproval()` — `GET` with `status: 0` and **no** `userId`, parsed into the existing
  DTOs. Online-only.
- `approve(String id)` — `POST .../{id}/approve` with an empty JSON object.
- `reject(String id, {required String reason})` — `POST .../{id}/reject` with `{'reason': reason}`.

All three go through the existing `_guarded` helper, so a 400 with a `detail` becomes the existing
`AbsenceRequestValidationError` / `SmartWorkingValidationError`, whose `toString()` is already the
server's actionable Italian sentence. The screens map a 403 to "Non hai i permessi per approvare le
richieste." and anything else to a generic retry message.

**Any 400 on a decision is terminal.** The client has already blocked the only fixable 400 (an empty
or over-long reason), the row came from the queue, and the body shape carries no stable code the
mobile client can branch on. So a 400 from approve or reject closes the reject sheet (keeping the
typed text only for a non-400 failure), refreshes the queue, and shows the server's `detail` — which
is exactly the "già decisa" sentence for `not_pending`. A retry on that row could only repeat the
same refusal.

Providers (new `lib/features/approvazioni/approvazioni_providers.dart`):

- `absenceApprovalQueueProvider` — `FutureProvider.autoDispose<List<AbsenceRequestDto>>` calling
  `fetchPendingForApproval()`.
- `smartWorkingApprovalQueueProvider` — the same for smart working.
- Decisions are performed by the screen (`ref.read(client).approve/reject`) and then:
  - invalidate that entity's queue provider **and** its own-list provider
    (`myAbsenceRequestsProvider` / `mySmartWorkingRequestsProvider`), so an approver who decided
    their own request sees the self screen update too;
  - show a success toast.
- No offline mirror. A failed read throws; the screen shows the error/offline state. A decision is
  refused before the request with the existing `ensureOnlineOrWarn` helper.

### Requester names

Move the user directory out of the squadra screen into a shared
`lib/data/users/user_directory.dart`:

- `allUsersProvider` becomes a family keyed by `activeOnly`
  (`FutureProvider.family.autoDispose<List<Map<String, dynamic>>, bool>`), wrapping
  `AdminApiClient.fetchAllUsersWithSquadraInfo(activeOnly: …)`.
- `userDisplayName(Map<String, dynamic> user)` becomes public there. It keeps the existing order:
  `displayName`, then `fullName`, then `firstName + lastName`, then "Utente senza nome". The squadra
  detail screen's private `_memberOptionLabel` is deleted in favour of this helper.
- `userNameByIdProvider` (`FutureProvider.autoDispose<Map<String, String>>`) builds an id → name map
  from `allUsersProvider(false)` — inactive users are included so a pending request filed by someone
  who has since left still shows a name. It catches any failure and resolves to an empty map; a
  missing name must never take the approval queue down. The queue screen reads it with
  `.valueOrNull ?? const {}` and renders `—` for unknown ids, never the raw GUID.
- The squadra list keeps its current behaviour by reading `allUsersProvider(true)`.

### Notifications

`DeepLinkIntent` gains a `notificationType` field (nullable), populated by `fromNotification` from
its existing `type` argument and exposed to `resolveRoute`:

| Notification type | Entity type | Destination |
|---|---|---|
| `AbsenceRequestSubmitted` | `AbsenceRequest` | `/altro/approvazioni?tab=assenze` |
| `AbsenceRequestSubmitted` | `SmartWorkingRequest` | `/altro/approvazioni?tab=smart-working` |
| `AbsenceRequestDecided` | `AbsenceRequest` | `/altro/ferie` (unchanged) |
| `AbsenceRequestDecided` | `SmartWorkingRequest` | `/altro/smart-working` (unchanged) |
| unknown / missing | either | current self-service route (unchanged) |

The server sends `AbsenceRequestSubmitted` to approvers for both entities (smart working reuses the
absence notification enum), and `AbsenceRequestDecided` to the requester. The entity id is still not
part of the route; the queue is the destination. Both the push path (`intentFromPushData`) and the
in-app list tap already have the notification type and must pass it through.

The current `fromNotification` only takes the entity branch when **both** `entityType` and
`entityId` are present. That gate is wrong for this destination: the approval queue needs no id.
The Submitted check therefore runs on `type` + `entityType` before the id requirement, so an
id-less Submitted notification still opens the queue. If `entityType` is missing but the type is
`AbsenceRequestSubmitted`, it opens the screen on its default (Ferie e permessi) tab; that is the
best available answer and the screen still shows whatever is pending.

### States and copy

- Loading: centered spinner.
- Empty: "Nessuna richiesta da approvare" with the tab's icon.
- Offline: `UnavailableState` with `wifiOff`, "Sei offline", and a retry that invalidates the
  provider. Decisions show the existing offline toast from `ensureOnlineOrWarn`.
- Read error: `ErrorState` with retry. Never rendered as the empty state.
- Success: "Richiesta approvata." / "Richiesta rifiutata."
- Permission (403): "Non hai i permessi per approvare le richieste."
- Other failure: "Impossibile aggiornare la richiesta. Riprova."

## Tests

- `test/data/ferie/absence_request_api_client_test.dart` — pending read sends `status=0` and no
  `userId`; approve POSTs to `/{id}/approve`; reject POSTs the trimmed reason; 400 `detail` maps to
  the validation error; 403 is surfaced.
- `test/data/smart_working/smart_working_request_api_client_test.dart` — the same three operations.
- `test/features/approvazioni/approvazioni_screen_test.dart` — rows show requester names (and `—`
  when the directory is empty), type/period/reason; approve confirmation then success; reject sheet
  refuses whitespace and sends the trimmed reason; empty, error and offline states; double-tap
  guard; a request decided elsewhere refreshes the queue.
- `test/core/notifications/deep_link_intent_test.dart` and
  `test/core/notifications/notification_deep_link_test.dart` — Submitted routes to the approval
  screen and the right tab, including with a missing `relatedEntityId`; Decided keeps the
  self-service routes; unknown types keep today's behaviour.
- `test/core/router/app_router_route_requirement_redirect_test.dart` — `/altro/approvazioni` is
  refused without the capability and allowed with it.
- `test/features/altro/altro_hub_screen_test.dart` — the tile is absent without
  `presenze.absence.approve` and present with it.
- Existing `flutter analyze` and the targeted suites must stay green.

## What is left to the builder

- Exact spacing, chip styling and card composition using the existing design-system widgets.
- Whether to show the requester name as a leading avatar tile or plain text (no avatar is required).
- The precise network-failure toast wording around the existing error strings.
- Whether the header count is shown per selected tab (recommended: yes, from the loaded list).
- How the user directory handles a partial page failure (recommended: the whole map resolves empty;
  names degrade, the queue still works).

## Decisions made in this design (check these)

- A separate screen (B), not sections inside the self-service screens.
- Pending only; no decided history in this pass.
- Approve asks for confirmation; reject requires a reason sheet.
- Names degrade to `—`; they never block approval.
- The approver's own pending requests appear in the tenant queue like anyone else's (the server does
  not exclude them); their self-service screens remain the place to manage their own.
- Requester names resolve `requestedByUserId`, never `createdByUserId`; an on-behalf request names
  the employee it is for.
- Any 400 on a decision is terminal (refresh, close the reject sheet, show the server's detail);
  only non-400 failures keep the sheet open with the typed reason.
- A Submitted notification opens the queue even without a `relatedEntityId`; a missing entity type
  defaults to the Ferie e permessi tab.
- No server change.
