import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
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

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Trigger initial sync post-login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).performSync();
      initTimbraSyncWatcher(ref);
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
      body: widget.navigationShell,
      // Extend body behind the floating pill so the hero/content scrolls under it.
      extendBody: true,
      bottomNavigationBar: AppBottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onDestinationSelected,
      ),
    );
  }
}
