import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/auth/auth_reconnect_watcher.dart';
import '../../../data/entitlements/entitlement_providers.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/tickets/ticket_creation_queue_watcher.dart';
import '../../../data/timbratura/timbra_sync_watcher.dart';

/// The main app shell with the 5-tab floating-pill bottom navigation.
///
/// Hosts: Dashboard / Ticket / Timbra / Calendario / Altro.
/// Uses [StatefulNavigationShell] to preserve each branch's state.
///
/// Sync triggers:
/// - On first mount (post-login): calls [SyncNotifier.performSync].
/// - On app foreground resume: calls [SyncNotifier.performSync].
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Trigger initial sync post-login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).performSync();
      initTimbraSyncWatcher(ref);
      // Offline-created tickets are queued locally (see
      // features/ticket/new_ticket_form_screen.dart); this flushes the
      // ones that are safe to auto-retry as soon as connectivity returns.
      initTicketCreationQueueWatcher(ref);
      // Retries the OIDC token refresh as soon as connectivity returns —
      // matters most right after a cold start on no signal, where auth
      // falls back to a cached, signed-in-but-offline identity (see
      // ZitadelAuthRepository._restore).
      initAuthReconnectWatcher(ref);
      // Which modules this tenant actually bought. The whole entitlement layer — repository,
      // service, Drift table, tests — existed and was never started from anywhere, so the cache was
      // permanently empty and the Altro hub offered every office module to every technician
      // regardless. The server refused them on arrival, which is the wrong place to find out.
      initEntitlementRefreshWatcher(ref);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called when the app is brought back to foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncProvider.notifier).performSync();
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
    return Scaffold(
      // The rail is drawn once here rather than per screen. It was reaching only four of the
      // forty-two screens, so the world read as "ledged cards" everywhere else — and the rail is
      // the mark that makes a column of cells a rack. It costs no layout: it paints inside the
      // 19dp gutter every screen already indents by (see AppRack.railColumn).
      //
      // SuspendedBanner used to live here; it now lives in MaterialApp's `builder` (main.dart) so
      // it covers pushed routes too, not just the 5 tab branches.
      body: Rack(bottom: AppRack.navBarHeight, child: widget.navigationShell),
      // Extend body behind the floating pill so the hero/content scrolls under it.
      extendBody: true,
      bottomNavigationBar: AppBottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onDestinationSelected,
      ),
    );
  }
}
