// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// RealtimeEventRouter
//
// Maps each named realtime event (Task 1/2's backend, Task 3's RealtimeConnection) to the
// existing provider(s) it should refresh. The event is a signal to re-fetch, never a second
// source of truth — see realtime_connection.dart's own doc comment for the "best-effort" side of
// this contract, and note that CantiereStatusChanged's raw `status` ordinal is never read here:
// a dropped/late/duplicate SignalR message must never leave the UI showing a value the server
// didn't actually confirm through the normal, already-trusted read path.
//
// Two different re-fetch mechanisms are wired below, matched to how each target provider
// actually gets its data:
//  - `ticketWorklogsProvider` is a `FutureProvider` that calls the ticket-workflow API directly
//    on every read (see its own doc comment: "no local mirror of ticket worklogs"). Invalidating
//    it alone is a real re-fetch.
//  - `ticketByIdProvider`, `cantiereByIdProvider`, `adminCantiereDetailProvider` and
//    `rapportiniListProvider` are `StreamProvider`s that reactively watch a *local Drift table*.
//    Invalidating one of these alone would just re-run the same query against data that hasn't
//    changed yet — a harmless no-op (briefly re-queries, gets the same row back) rather than an
//    actual re-fetch. The real re-fetch mechanism for all of these is the existing general sync
//    (`SyncService.sync()` via `syncProvider` — the same one HomeShell already triggers on
//    mount/resume/reconnect/every 60s, and the same one `ticketCreationQueueProvider.onSubmitted`
//    already reuses for exactly this reason — see ticket_creation_queue_watcher.dart). So each of
//    these cases both invalidates the specific provider instance (immediate, if a screen happens
//    to already be looking at it — cheap even though the data itself hasn't moved yet) *and*
//    triggers `syncProvider.notifier.performSync()`, which is what actually pulls the changed row
//    into Drift; the already-reactive StreamProvider then updates on its own once that write
//    lands. This reuses the existing sync path — it does not add a new one.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/cantieri/admin_cantiere_detail_screen.dart'
    show adminCantiereDetailProvider;
import '../../features/admin/reports/admin_report_list_screen.dart' show adminReportsProvider;
import '../../features/cantiere/cantiere_providers.dart' show cantiereByIdProvider;
import '../../features/rapportino/rapportino_list_providers.dart' show rapportiniListProvider;
import '../../features/ticket/ticket_providers.dart' show ticketWorklogsProvider;
import '../../presentation/providers/schedule_providers.dart' show ticketByIdProvider;
import '../sync/connectivity_provider.dart';
import '../sync/sync_service.dart' show syncProvider;
import 'realtime_connection.dart';

/// Routes one parsed realtime [event] to whichever existing provider(s) it should refresh — see
/// this file's header comment for why some cases also trigger a general sync rather than
/// invalidating alone.
///
/// Exactly the 5 events this plan promises are handled. `MaterialeUpdated` is deliberately not a
/// case here (explicitly out of scope). An unrecognized `event.type` is silently ignored rather
/// than throwing — a future server-side event type must be safe to receive on an older,
/// not-yet-updated app build.
void routeRealtimeEvent(ProviderContainer container, RealtimeEvent event) {
  switch (event.type) {
    case 'TicketWorkLogStarted':
    case 'TicketWorkLogStopped':
      final ticketId = event.data['ticketId'] as String?;
      if (ticketId != null) container.invalidate(ticketWorklogsProvider(ticketId));
      break;

    case 'TicketUpdated':
      final ticketId = event.data['ticketId'] as String?;
      if (ticketId != null) container.invalidate(ticketByIdProvider(ticketId));
      container.read(syncProvider.notifier).performSync();
      break;

    case 'CantiereStatusChanged':
      final cantiereId = event.data['cantiereId'] as String?;
      if (cantiereId != null) {
        container.invalidate(cantiereByIdProvider(cantiereId));
        container.invalidate(adminCantiereDetailProvider(cantiereId));
      }
      container.read(syncProvider.notifier).performSync();
      break;

    case 'RapportinoSubmitted':
      // Whole-family invalidation for the admin list: the technician side has no id param
      // (rapportiniListProvider is a plain provider), but the admin list is keyed by StatoFilter
      // and the office screen currently open may be on any filter — invalidating the family
      // covers whichever one(s) are actually instantiated.
      container.invalidate(rapportiniListProvider);
      container.invalidate(adminReportsProvider);
      container.read(syncProvider.notifier).performSync();
      break;
  }
}

/// Call once on app start (HomeShell.initState via addPostFrameCallback, alongside every other
/// reconnect-triggered watcher — see home_shell.dart). Starts the best-effort realtime connection
/// and routes every event it delivers via [routeRealtimeEvent].
///
/// Also forces a fresh connection attempt on every offline→online transition
/// (`connectivityProvider.onReconnect`), on top of `RealtimeConnection`'s own
/// `withAutomaticReconnect()`. This is deliberately not redundant: the SignalR client's automatic
/// reconnect gives up after a fixed number of attempts (the package's default retry policy), and
/// once it does, `RealtimeConnection._connection` is left in place — `connect()`'s "already
/// connected/connecting" guard means it would never try again on its own. A device offline longer
/// than that retry window would otherwise lose the realtime channel for the rest of the app
/// session; the explicit `reconnect()` on the app's own already-reliable connectivity signal
/// closes that gap, the same way every other reconnect-triggered watcher in this app does for its
/// own feature.
///
/// Returns the cancel function to invoke from the caller's `dispose()` — see
/// timbra_sync_watcher.dart's doc comment for why this matters.
///
/// The cancel function also stops the underlying SignalR connection (via [RealtimeConnection.stop],
/// not [RealtimeConnection.dispose]) rather than just unsubscribing locally. `realtimeConnectionProvider`
/// is root-scoped and outlives a `HomeShell` remount — a forced sign-out tears down and recreates the
/// whole `HomeShell` (see home_shell.dart's own comment on `_reconnectUnsubs`), and without an explicit
/// stop here the next mount's `connect()` call would see the SAME instance still holding a live
/// connection authenticated under the PREVIOUS session's token and joined to the PREVIOUS tenant's
/// group — the new sign-in would get zero realtime events for its own tenant. `stop()` (rather than
/// `dispose()`) leaves the instance's `events` stream open so the next mount's `connect()` still works.
VoidCallback initRealtimeEventWatcher(WidgetRef ref) {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final connection = ref.read(realtimeConnectionProvider);

  // Best-effort by design (see RealtimeConnection.connect's own doc comment) — never throws,
  // no-op if there's no access token yet.
  connection.connect();

  final eventsSub = connection.events.listen((event) => routeRealtimeEvent(container, event));

  final reconnectCancel = ref.read(connectivityProvider.notifier).onReconnect(() {
    connection.reconnect();
  });

  return () {
    eventsSub.cancel();
    reconnectCancel();
    connection.stop();
  };
}
