import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/sync/sync_service.dart';

/// The main app shell with bottom navigation.
///
/// Hosts four tabs: Oggi / Interventi / Rapportini / Profilo.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: _AppBottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      // Return to the initial location when re-tapping the active tab.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today),
          label: 'Oggi',
          tooltip: 'Oggi',
        ),
        NavigationDestination(
          icon: Icon(Icons.build_outlined),
          selectedIcon: Icon(Icons.build),
          label: 'Interventi',
          tooltip: 'Interventi',
        ),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: 'Rapportini',
          tooltip: 'Rapportini',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profilo',
          tooltip: 'Profilo',
        ),
      ],
    );
  }
}
