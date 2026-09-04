# SignalR Real-Time Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Other users' changes to tickets, worklogs, cantiere status, materiali, and rapportino
submissions appear on screen without a manual refresh — a deliberately small-scope real-time layer
on top of already-committed writes, not a replacement for the app's offline-first design.

**Architecture:** The backend already has a real, working, auth/tenant-scoped SignalR hub
(`NotificationHub`, `/api/hubs/notifications`) used today for generic notifications — this plan
does NOT build a new hub. It adds one new tenant-broadcast method alongside the existing
user-targeted one, calls it from 5 named write actions (after their DB commit, best-effort, never
blocking the response), and adds the mobile SignalR client this hub has never had — the real gap
this plan closes. Each event invalidates the relevant existing Riverpod provider rather than
pushing raw data into local state; the SignalR event is a signal to re-fetch, never a second source
of truth.

**Tech Stack:** Backend: ASP.NET Core SignalR (already a dependency). Mobile: a Dart SignalR
client (`signalr_netcore` — verify current pub.dev maintenance status before adding; if
unmaintained, use whatever the maintained alternative is at plan-execution time).

**Spec:** `docs/superpowers/specs/2026-09-04-offline-realtime-engine-design.md` (§3B)

## Global Constraints

- The database write is always the source of truth, committed before any SignalR notification —
  every push call is wrapped in try/catch, logged on failure, never allowed to fail the write
  itself (mirrors `SignalRNotificationPushService.PushToUserAsync`'s existing exact pattern —
  Task 1 follows it, does not invent a new error-handling shape).
- Exactly 5 events, no more added silently during implementation: `TicketUpdated`,
  `TicketWorkLogStarted`, `TicketWorkLogStopped`, `CantiereStatusChanged`, `RapportinoSubmitted`.
  (`MaterialeUpdated` from the original spec is deferred — no clear single "material changed"
  write action was identified as unambiguous during planning; adding it later is a small,
  independent follow-up once a specific trigger point is chosen, not blocking this plan.)
- A mobile client holds ONE persistent connection regardless of how many screens/tickets are open
  — connect once at app root (alongside the existing reconnect watchers in `HomeShell`), not
  per-screen.
- Existing polling (the dashboard's 1-minute tracker poll) is NOT removed — SignalR is additive,
  the app must keep working exactly as it does today if a SignalR connection never succeeds.
- Backend repo: `/mnt/d/AEA/Sviluppi/TaskTap`, branch `master`. Mobile repo:
  `/mnt/d/AEA/Sviluppi/TaskTap/mobile`, branch `develop`.

---

### Task 1: Backend — tenant-broadcast method on the existing push service

**Repo:** backend (`/mnt/d/AEA/Sviluppi/TaskTap`, branch `master`)

**Files:**
- Modify: `src/TaskTapAPI.Core/Interfaces/INotificationPushService.cs` (or wherever
  `INotificationPushService` is actually declared — confirm the exact file before editing)
- Modify: `src/TaskTapAPI.Api/Services/SignalRNotificationPushService.cs`
- Test: `tests/TaskTapAPI.Tests/Services/SignalRNotificationPushServiceBroadcastTests.cs` (new file)

**Interfaces:**
- Produces: `INotificationPushService.PushTenantEventAsync(Guid tenantId, string eventType, object
  payload, CancellationToken ct = default)` — Tasks 2-6 call this after their respective DB commit.
  Sends a `"ReceiveEvent"` SignalR message (distinct from the existing `"ReceiveNotification"`
  message `PushToUserAsync` sends — do not conflate the two) with shape `{ type: eventType, data:
  payload, occurredAt: <UTC now> }` to the `tenant-{tenantId}` group `NotificationHub.OnConnectedAsync`
  already joins every authenticated connection to.

- [ ] **Step 1: Write the failing test**

```csharp
// tests/TaskTapAPI.Tests/Services/SignalRNotificationPushServiceBroadcastTests.cs
using Microsoft.AspNetCore.SignalR;
using Moq;
using TaskTapAPI.Api.Hubs;
using TaskTapAPI.Api.Services;
using Xunit;

namespace TaskTapAPI.Tests.Services;

public class SignalRNotificationPushServiceBroadcastTests
{
    [Fact]
    public async Task PushTenantEventAsync_sends_ReceiveEvent_to_the_tenant_group()
    {
        var tenantId = Guid.NewGuid();
        var clientProxy = new Mock<IClientProxy>();
        var clients = new Mock<IHubClients>();
        clients.Setup(c => c.Group($"tenant-{tenantId}")).Returns(clientProxy.Object);
        var hubContext = new Mock<IHubContext<NotificationHub>>();
        hubContext.Setup(h => h.Clients).Returns(clients.Object);
        var logger = Mock.Of<Microsoft.Extensions.Logging.ILogger<SignalRNotificationPushService>>();

        var service = new SignalRNotificationPushService(hubContext.Object, logger);

        await service.PushTenantEventAsync(tenantId, "TicketUpdated", new { ticketId = "t1" });

        clientProxy.Verify(
            c => c.SendCoreAsync(
                "ReceiveEvent",
                It.Is<object[]>(args => args.Length == 1),
                default),
            Times.Once);
    }

    [Fact]
    public async Task PushTenantEventAsync_swallows_a_send_failure_rather_than_throwing()
    {
        var tenantId = Guid.NewGuid();
        var clientProxy = new Mock<IClientProxy>();
        clientProxy
            .Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object[]>(), default))
            .ThrowsAsync(new InvalidOperationException("hub unreachable"));
        var clients = new Mock<IHubClients>();
        clients.Setup(c => c.Group($"tenant-{tenantId}")).Returns(clientProxy.Object);
        var hubContext = new Mock<IHubContext<NotificationHub>>();
        hubContext.Setup(h => h.Clients).Returns(clients.Object);
        var logger = Mock.Of<Microsoft.Extensions.Logging.ILogger<SignalRNotificationPushService>>();

        var service = new SignalRNotificationPushService(hubContext.Object, logger);

        // Must not throw — a push failure must never fail the caller's write.
        await service.PushTenantEventAsync(tenantId, "TicketUpdated", new { ticketId = "t1" });
    }
}
```

(Confirm this test project already uses Moq — check an existing service test for the mocking
library convention; if it uses a different one, e.g. NSubstitute, mirror that instead.)

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test --filter "FullyQualifiedName~SignalRNotificationPushServiceBroadcastTests"`
Expected: FAIL — `PushTenantEventAsync` doesn't exist yet.

- [ ] **Step 3: Add the interface method and implementation**

In `INotificationPushService`, add:

```csharp
    Task PushTenantEventAsync(Guid tenantId, string eventType, object payload, CancellationToken ct = default);
```

In `SignalRNotificationPushService`, add (mirroring `PushToUserAsync`'s exact
try/catch-log-never-throw shape):

```csharp
    public async Task PushTenantEventAsync(
        Guid tenantId, string eventType, object payload, CancellationToken ct = default)
    {
        try
        {
            await _hubContext.Clients
                .Group($"tenant-{tenantId}")
                .SendAsync("ReceiveEvent", new
                {
                    type = eventType,
                    data = payload,
                    occurredAt = DateTime.UtcNow
                }, ct);

            _logger.LogDebug("Broadcast {EventType} to tenant {TenantId}", eventType, tenantId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to broadcast {EventType} to tenant {TenantId}", eventType, tenantId);
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dotnet test --filter "FullyQualifiedName~SignalRNotificationPushServiceBroadcastTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/TaskTapAPI.Core/Interfaces/INotificationPushService.cs \
        src/TaskTapAPI.Api/Services/SignalRNotificationPushService.cs \
        tests/TaskTapAPI.Tests/Services/SignalRNotificationPushServiceBroadcastTests.cs
git commit -m "feat(realtime): add tenant-broadcast SignalR event method"
```

---

### Task 2: Backend — wire the 5 named events into their write actions

**Repo:** backend (`/mnt/d/AEA/Sviluppi/TaskTap`, branch `master`)

**Files:**
- Modify: `src/TaskTapAPI.Api/Controllers/TicketWorkLogController.cs` (`StartTimer`, `StopTimer`)
- Modify: `src/TaskTapAPI.Api/Controllers/CantiereWorkLogController.cs` (`StartWork`, `EndWork` —
  or wherever cantiere STATUS specifically changes, not just worklog open/close; confirm the exact
  "status changed" trigger point before wiring `CantiereStatusChanged` — it may be a different
  action/controller than the worklog one, read `CantiereController`/whatever owns
  `Cantiere.StatusId` before assuming)
- Modify: whichever controller/service commits a ticket field update (find the actual "update
  ticket" write path — likely `TicketsController.Update` or similar; confirm before wiring
  `TicketUpdated`)
- Modify: `src/TaskTapAPI.Api/Controllers/ReportsController.cs` (or wherever a report's submission
  actually commits — the endpoint the frontend/mobile's submit flow calls; confirm before wiring
  `RapportinoSubmitted`)
- Test: extend each modified controller's existing test file (or the ones Task 1/2/3 of the
  worklog-auto-approve plan created, if that plan has landed by the time this task runs) with one
  assertion per action: the push service's `PushTenantEventAsync` is called with the right event
  type after a successful write (mock/spy `INotificationPushService`, do not require a real hub
  connection in these tests).

**Interfaces:**
- Consumes: `INotificationPushService.PushTenantEventAsync` (Task 1).
- Produces: no public API/response-shape changes to any of these endpoints — the push happens
  after the response-worthy work is done, best-effort, fire-and-forget from the caller's
  perspective (do not `await` it in a way that makes the HTTP response wait on the hub — if
  `SendAsync`'s `ct` parameter ties it to the request's cancellation token, that's fine; the
  response itself must not be delayed waiting for SignalR delivery to complete beyond what
  `PushTenantEventAsync`'s own try/catch already bounds).

- [ ] **Step 1: Write the failing tests**

For each of the 4 controllers, extend its test file (or its worklog-auto-approve-plan-created test
file, if applicable) with a case constructing the controller with a mocked
`INotificationPushService` and asserting `PushTenantEventAsync` was called once, with the correct
`eventType` string, after the action under test succeeds.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test --filter "FullyQualifiedName~<each new test name>"`
Expected: FAIL — no push call exists yet in any of the 4 controllers.

- [ ] **Step 3: Inject `INotificationPushService` and call it after each write commits**

In each of the 4 controllers, add `INotificationPushService` to the constructor (matching each
controller's existing DI pattern), and after `await UnitOfWork.SaveChangesAsync();` in the relevant
action, add:

```csharp
        await _notificationPush.PushTenantEventAsync(
            CurrentTenantId!.Value, "TicketWorkLogStarted", new { ticketId, userId });
```

(Adjust the event type string and payload shape per action — `TicketWorkLogStarted`/`Stopped` for
`TicketWorkLogController`'s two actions, `CantiereStatusChanged` for whichever cantiere action
actually changes status, `TicketUpdated` for the ticket update action, `RapportinoSubmitted` for
the report submission action. Payload is deliberately minimal — an id or two, enough for the
mobile client to know WHAT to re-fetch, never the full entity.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test --filter "FullyQualifiedName~<each new test name>"`
Expected: PASS.

- [ ] **Step 5: Run the full backend test suite once**

Run: `dotnet test`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add <the 4 modified controllers and their test files>
git commit -m "feat(realtime): broadcast TicketUpdated/WorkLogStarted/Stopped/CantiereStatusChanged/RapportinoSubmitted"
```

---

### Task 3: Mobile — SignalR client connection

**Repo:** mobile (`/mnt/d/AEA/Sviluppi/TaskTap/mobile`, branch `develop`)

**Files:**
- Modify: `pubspec.yaml` (add the SignalR client dependency)
- Create: `lib/data/realtime/realtime_connection.dart`
- Test: `test/data/realtime/realtime_connection_test.dart`

**Interfaces:**
- Produces: `realtimeConnectionProvider` — a `Provider` (or similar) exposing a connect/reconnect
  lifecycle and a `Stream<RealtimeEvent>` where `RealtimeEvent` is `({String type, Map<String,
  dynamic> data})`, parsed from each `"ReceiveEvent"` hub message. Task 4 subscribes to this
  stream.

- [ ] **Step 1: Add the dependency**

Check pub.dev for `signalr_netcore`'s current maintenance status (last publish date, open issues
around Flutter compatibility) before adding it — if it looks abandoned, search for the
currently-maintained alternative and use that instead, noting the substitution in the commit
message. Add to `pubspec.yaml`'s `dependencies:`, run `flutter pub get`.

- [ ] **Step 2: Write the failing test**

```dart
// test/data/realtime/realtime_connection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/realtime/realtime_connection.dart';

void main() {
  test('parses a ReceiveEvent payload into a RealtimeEvent', () {
    final raw = {
      'type': 'TicketUpdated',
      'data': {'ticketId': 't1'},
      'occurredAt': '2026-09-04T10:00:00Z',
    };

    final event = RealtimeEvent.fromHubPayload(raw);

    expect(event.type, 'TicketUpdated');
    expect(event.data['ticketId'], 't1');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/realtime/realtime_connection_test.dart`
Expected: FAIL — `RealtimeEvent`/the file don't exist yet.

- [ ] **Step 4: Write the connection wrapper**

```dart
// dart format width=100
// lib/data/realtime/realtime_connection.dart
import 'dart:async';

// Replace with the actual chosen package's import once confirmed at Step 1 above.
import 'package:signalr_netcore/signalr_client.dart';

import '../../core/config/env.dart';
import '../auth/zitadel_auth_repository.dart';

typedef RealtimeEvent = ({String type, Map<String, dynamic> data});

extension RealtimeEventParsing on RealtimeEvent {
  static RealtimeEvent fromHubPayload(Map<String, dynamic> raw) => (
    type: raw['type'] as String,
    data: (raw['data'] as Map).cast<String, dynamic>(),
  );
}

/// One persistent connection to NotificationHub's tenant-broadcast events, regardless of how many
/// screens are open. Auth via ?access_token= query string, matching Program.cs's existing
/// JwtBearerEvents.OnMessageReceived handling for the /api/hubs path prefix — same mechanism the
/// backend already built for this hub, not a new auth scheme.
///
/// This connection is best-effort: if it never connects, or drops and can't reconnect, the app
/// must keep working exactly as it does today (existing polling/manual refresh) — nothing here
/// may become a hard dependency for any screen to function.
class RealtimeConnection {
  RealtimeConnection({required String Function() accessTokenProvider})
    : _accessTokenProvider = accessTokenProvider;

  final String Function() _accessTokenProvider;
  HubConnection? _connection;
  final _eventsController = StreamController<RealtimeEvent>.broadcast();

  Stream<RealtimeEvent> get events => _eventsController.stream;

  Future<void> connect() async {
    final token = _accessTokenProvider();
    if (token.isEmpty) return;

    final connection = HubConnectionBuilder()
        .withUrl(
          '${Env.apiBaseUrl}/api/hubs/notifications?access_token=$token',
        )
        .withAutomaticReconnect()
        .build();

    connection.on('ReceiveEvent', (arguments) {
      if (arguments == null || arguments.isEmpty) return;
      final raw = arguments[0];
      if (raw is Map) {
        _eventsController.add(RealtimeEventParsing.fromHubPayload(raw.cast<String, dynamic>()));
      }
    });

    _connection = connection;
    await connection.start();
  }

  Future<void> dispose() async {
    await _connection?.stop();
    await _eventsController.close();
  }
}
```

(This is a structural sketch — `signalr_netcore`'s (or the chosen alternative's) actual
`HubConnectionBuilder`/`.withUrl`/`.on`/`.start` API must be verified against that package's real,
current documentation before this compiles; do not assume the method names above are exact without
checking. `Env.apiBaseUrl` and the access-token accessor's exact names must also be confirmed
against `lib/core/config/env.dart` and however `ZitadelAuthRepository`'s current access token is
actually exposed — this session's earlier work on `zitadel_auth_repository.dart` established that
access tokens live in memory on the `AuthUser` object, not persisted; find the correct current
accessor rather than guessing at one.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/realtime/realtime_connection_test.dart`
Expected: PASS (this specific test only exercises the pure parsing function, not a real
connection — no network/hub needed for it to pass).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/realtime/realtime_connection.dart \
        test/data/realtime/realtime_connection_test.dart
git commit -m "feat(realtime): add SignalR connection wrapper"
```

---

### Task 4: Mobile — wire the connection into the app shell, invalidate providers on events

**Files:**
- Modify: `lib/presentation/screens/home/home_shell.dart`
- Create: `lib/data/realtime/realtime_event_router.dart`
- Test: `test/data/realtime/realtime_event_router_test.dart`

**Interfaces:**
- Consumes: `RealtimeConnection.events` (Task 3), `RealtimeEvent` (Task 3).
- Produces: no new public API — this task's job is entirely "connect the pipe": start the
  connection alongside `HomeShell`'s existing reconnect watchers (`initSubmissionQueueWatcher` and
  siblings, `home_shell.dart:88` and nearby), route each event type to a provider invalidation.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/realtime/realtime_event_router_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/realtime/realtime_event_router.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart' show ticketWorklogsProvider;

void main() {
  test('a TicketWorkLogStarted event invalidates ticketWorklogsProvider for that ticket', () async {
    var invalidated = false;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(
      ticketWorklogsProvider('t1'),
      (prev, next) => invalidated = true,
      fireImmediately: false,
    );

    routeRealtimeEvent(
      container,
      (type: 'TicketWorkLogStarted', data: {'ticketId': 't1', 'userId': 'u1'}),
    );

    // Confirm the specific provider instance was invalidated — exact assertion mechanism depends
    // on ticketWorklogsProvider's real family-parameter shape; adjust to match it precisely.
  });
}
```

(This test's exact assertion shape is a sketch — `ticketWorklogsProvider`'s real signature must be
confirmed against `lib/features/ticket/ticket_providers.dart` before finalizing how to observe an
invalidation on a family provider instance.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/realtime/realtime_event_router_test.dart`
Expected: FAIL — `routeRealtimeEvent` doesn't exist yet.

- [ ] **Step 3: Write the router**

```dart
// dart format width=100
// lib/data/realtime/realtime_event_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ticket/ticket_providers.dart' show ticketWorklogsProvider;
import 'realtime_connection.dart';

/// Maps each named real-time event to the provider(s) it should invalidate — the event is a
/// signal to re-fetch, never a second source of truth. Every case here is a real, already-existing
/// provider; this function creates no new data path.
void routeRealtimeEvent(ProviderContainer container, RealtimeEvent event) {
  switch (event.type) {
    case 'TicketWorkLogStarted':
    case 'TicketWorkLogStopped':
      final ticketId = event.data['ticketId'] as String?;
      if (ticketId != null) container.invalidate(ticketWorklogsProvider(ticketId));
    // TODO for the implementer: add cases for TicketUpdated, CantiereStatusChanged,
    // RapportinoSubmitted, invalidating whichever real providers each screen already reads —
    // find the actual provider names (ticket detail's own provider, cantiere detail's status
    // provider, the rapportini list provider) before wiring each one; do not invent provider
    // names.
  }
}
```

- [ ] **Step 4: Wire the connection into `HomeShell`**

In `home_shell.dart`, alongside the existing `_reconnectUnsubs.add(initSubmissionQueueWatcher(ref))`
line, add connecting the SignalR client on the same lifecycle hook (after auth, on
resume/reconnect) and subscribing its `events` stream to `routeRealtimeEvent`. Read the surrounding
`initState`/`didChangeAppLifecycleState` structure first to match the exact pattern the existing
watchers use rather than inventing a different lifecycle shape.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/realtime/realtime_event_router_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full test suite once**

Run: `flutter test`
Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add lib/data/realtime/realtime_event_router.dart lib/presentation/screens/home/home_shell.dart \
        test/data/realtime/realtime_event_router_test.dart
git commit -m "feat(realtime): wire SignalR connection + event routing into HomeShell"
```

---

## Self-review notes (per this skill's own required step)

**Spec coverage:** Task 1-2 cover the backend event-emission half. Tasks 3-4 cover the mobile
client half. `MaterialeUpdated` is explicitly deferred (Global Constraints), not silently dropped.
Tenant/permission-scoping is inherited from `NotificationHub`'s existing, already-correct
`OnConnectedAsync` group-join — this plan does not re-implement isolation, it reuses what's proven.

**Placeholder scan:** Several steps (Task 2's "confirm the actual cantiere-status/ticket-update/
report-submit action" instructions, Task 3's package-API-verification note, Task 4's TODO for the
remaining 3 event cases) are explicit, scoped research pointers with a clear reason each — this
plan's grounding pass did not have certainty about several exact call sites (unlike the
worklog-auto-approve plan, which had that certainty from direct reads) and says so honestly rather
than guessing at file:line citations that might be wrong. This is more open scope than this
skill's "no placeholders" ideal calls for, flagged explicitly rather than hidden.

**Type consistency:** `RealtimeEvent`'s `({String type, Map<String, dynamic> data})` record shape
is used identically in Task 3 (produced) and Task 4 (consumed). `PushTenantEventAsync`'s signature
matches between Task 1 (declared) and Task 2 (called). The `"ReceiveEvent"` SignalR message name is
used identically server-side (Task 1) and client-side (Task 3) — deliberately distinct from the
existing `"ReceiveNotification"` message, so the two message types never collide.
