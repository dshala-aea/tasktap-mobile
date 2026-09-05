import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/auth/auth_reconnect_watcher.dart';
import '../../../data/entitlements/entitlement_providers.dart';
import '../../../data/realtime/realtime_event_router.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/tickets/ticket_attachment_upload_queue_watcher.dart';
import '../../../data/tickets/ticket_creation_queue_watcher.dart';
import '../../../data/timbratura/cantiere_timbra_sync_watcher.dart';
import '../../../data/timbratura/cantiere_work_log_reconcile_watcher.dart';
import '../../../data/timbratura/cantiere_work_log_reconciler.dart';
import '../../../data/sync/submission_queue_watcher.dart';
import '../../../data/timbratura/timbra_sync_watcher.dart';
import '../../../data/timbratura/work_log_reconcile_watcher.dart';
import '../../../data/timbratura/work_log_reconciler.dart';

/// The main app shell with the 5-tab floating-pill bottom navigation.
///
/// Hosts: Dashboard / Ticket / Timbra / Calendario / Altro.
/// Uses [StatefulNavigationShell] to preserve each branch's state.
///
/// Sync triggers:
/// - On first mount (post-login): calls [SyncNotifier.performSync].
/// - On app foreground resume: calls [SyncNotifier.performSync].
/// - On reconnect, and every 60s while foregrounded: same call, added alongside the worklog
///   reconcilers below so a rapportino status change (e.g. an office rejection —
///   SyncService's `submittedReports` upsert) surfaces without waiting for the next resume.
///
/// Worklog reconciliation triggers (see work_log_reconciler.dart for why this exists — in short,
/// the same account clocking out on the web must not leave mobile showing "on shift" forever).
/// [CantiereWorkLogReconciler] gets the identical treatment for the cantiere (worksite) session:
/// - On first mount and on reconnect: see [initWorkLogReconcileWatcher] /
///   [initCantiereWorkLogReconcileWatcher].
/// - On app foreground resume: both reconcile immediately.
/// - Every 60s while foregrounded: matches the dashboard's activeTrackersProvider poll cadence.
///   Cancelled while backgrounded — this is a foreground fallback, not a background service.
///
/// Cantiere timbra also gets the personal-timbra offline push treatment: [initTimbraSyncWatcher] /
/// [initCantiereTimbraSyncWatcher] push locally-queued punches as soon as connectivity allows.
///
/// Realtime: [initRealtimeEventWatcher] opens the one persistent SignalR connection for this
/// shell's lifetime and routes each pushed event to the existing provider(s)/sync it should
/// trigger — see realtime_event_router.dart. Best-effort: a device that never connects, or loses
/// the connection, keeps working exactly as it does today via the triggers above.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  Timer? _reconcilePoll;

  // Cancel functions for every connectivityProvider.onReconnect() registration made below. A
  // forced sign-out (AuthInterceptor → authRepo.signOut()) sends the router to /login and back,
  // disposing and recreating this whole widget — connectivityProvider itself is never disposed
  // across that cycle. Without unregistering here, each remount left the previous mount's
  // closures (closing over an already-disposed `ref`) in the listener list forever, and the next
  // reconnect threw "Cannot use ref after the widget was disposed" on those stale entries.
  final List<VoidCallback> _reconnectUnsubs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Trigger initial sync post-login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).performSync();
      _reconnectUnsubs.add(initTimbraSyncWatcher(ref));
      // Offline-first cantiere (worksite) timbratura — same push-on-reconnect pattern as
      // personal attendance. See cantiere_timbra_sync_service.dart.
      _reconnectUnsubs.add(initCantiereTimbraSyncWatcher(ref));
      // Offline-created tickets are queued locally (see
      // features/ticket/new_ticket_form_screen.dart); this flushes the
      // ones that are safe to auto-retry as soon as connectivity returns.
      _reconnectUnsubs.add(initTicketCreationQueueWatcher(ref));
      // Same push-on-reconnect treatment for a photo/file picked from ticket detail's Allegati
      // tab while offline (features/ticket/ticket_detail_screen.dart).
      _reconnectUnsubs.add(initTicketAttachmentUploadQueueWatcher(ref));
      // A rapportino submitted with no signal is queued (SubmissionQueue) and correctly kept as
      // retryable rather than lost — but nothing ever retried it automatically until this watcher
      // was wired up. Every other offline-write queue in this app (tickets, attachments, timbra,
      // cantiere timbra) gets this same reconnect-triggered flush; this was the one missing.
      _reconnectUnsubs.add(initSubmissionQueueWatcher(ref));
      // Retries the OIDC token refresh as soon as connectivity returns —
      // matters most right after a cold start on no signal, where auth
      // falls back to a cached, signed-in-but-offline identity (see
      // ZitadelAuthRepository._restore).
      _reconnectUnsubs.add(initAuthReconnectWatcher(ref));
      // Which modules this tenant actually bought. The whole entitlement layer — repository,
      // service, Drift table, tests — existed and was never started from anywhere, so the cache was
      // permanently empty and the Altro hub offered every office module to every technician
      // regardless. The server refused them on arrival, which is the wrong place to find out.
      _reconnectUnsubs.add(initEntitlementRefreshWatcher(ref));
      // Corrects local "on shift" state when the same account clocked out elsewhere (web).
      // See work_log_reconciler.dart.
      _reconnectUnsubs.add(initWorkLogReconcileWatcher(ref));
      // Same correction, for the cantiere (worksite) session. See
      // cantiere_work_log_reconciler.dart.
      _reconnectUnsubs.add(initCantiereWorkLogReconcileWatcher(ref));
      // One persistent SignalR connection for the lifetime of this shell, routing each pushed
      // event (ticket worklog started/stopped, ticket updated, cantiere status changed,
      // rapportino submitted) to the existing provider(s) it should refresh — never a new data
      // path. See realtime_event_router.dart's own doc comment for why this is best-effort and
      // never blocks anything else here.
      _reconnectUnsubs.add(initRealtimeEventWatcher(ref));
      // General sync already carries a submitted rapportino's server-side lifecycle back to the
      // device (SyncService's `submittedReports` upsert) — including an office rejection — but
      // until now it only ever ran on first mount and app-foreground resume (below). A
      // technician staring at a rapportino they just fixed offline, who then regains signal
      // without backgrounding the app, would not see a rejection until they happened to resume
      // it. Reconnect + the same 60s foreground poll the two worklog reconcilers already use
      // close that gap, matching their cadence exactly rather than inventing a third pattern.
      _reconnectUnsubs.add(
        ref.read(connectivityProvider.notifier).onReconnect(() {
          ref.read(syncProvider.notifier).performSync();
        }),
      );
      _startReconcilePoll();
    });
  }

  @override
  void dispose() {
    for (final unsub in _reconnectUnsubs) {
      unsub();
    }
    _reconcilePoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Starts (or restarts) the 60s foreground reconciliation poll.
  void _startReconcilePoll() {
    _reconcilePoll?.cancel();
    _reconcilePoll = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.read(workLogReconcilerProvider).reconcile();
      ref.read(cantiereWorkLogReconcilerProvider).reconcile();
      ref.read(syncProvider.notifier).performSync();
    });
  }

  /// Called on every app lifecycle transition.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncProvider.notifier).performSync();
      ref.read(workLogReconcilerProvider).reconcile();
      ref.read(cantiereWorkLogReconcilerProvider).reconcile();
      _startReconcilePoll();
    } else {
      // Backgrounded (paused/inactive/hidden): stop the foreground fallback poll. This is
      // deliberately not a background service — reconciliation resumes on the next foreground.
      _reconcilePoll?.cancel();
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      // Return to the initial location when re-tapping the active tab.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rack is a passthrough now (see its own doc comment) — kept only so this one call site
    // needs no change from when it painted the van-racking rail behind every tab.
    final content = Rack(
      bottom: AppRack.navBarHeight,
      child: widget.navigationShell,
    );
    final nav = AppBottomNav(
      currentIndex: widget.navigationShell.currentIndex,
      onTap: _onDestinationSelected,
    );

    // ≥AppBottomNav.wideBreakpoint (tablet/expanded window): AppBottomNav itself switches to a
    // vertical rail shape at this same width (see its own doc comment on `_buildRail`), and a
    // vertical rail placed in `Scaffold.bottomNavigationBar` would still render at the bottom of
    // the screen regardless — that slot only ever puts a widget along the bottom edge. Laying it
    // out beside the content in a `Row` instead is the minimal restructuring that actually lets it
    // sit at the side.
    if (MediaQuery.sizeOf(context).width >= AppBottomNav.wideBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            nav,
            Expanded(
              child: Stack(
                children: [
                  content,
                  const Align(
                    alignment: Alignment.topCenter,
                    child: OfflineSyncBanner(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          content,
          const Align(
            alignment: Alignment.topCenter,
            child: OfflineSyncBanner(),
          ),
        ],
      ),
      // Extend body behind the floating pill so the hero/content scrolls under it.
      extendBody: true,
      bottomNavigationBar: nav,
    );
  }
}
