// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/update/app_version_policy_providers.dart';
import '../../../core/update/update_gate_rule.dart';
import '../../../core/update/update_required_state.dart';
import '../../../data/sync/pending_sync_count_provider.dart';
import '../../widgets/update_available_banner.dart';
import '../../widgets/update_pending_sync_banner.dart';
import 'update_required_screen.dart';

/// Applies the version gate around the router's navigator (placed in `MaterialApp.router`'s
/// `builder`, not in a router redirect: the login screen and every route stay reachable, and the
/// blocking screen only ever covers them, it never replaces them).
///
/// - update required, nothing pending: [UpdateRequiredScreen] on top (the app underneath stays
///   mounted, so a lowered minimum releases it with the navigation state intact);
/// - update required, items pending: calm "Sincronizza, poi aggiorna" banner, app usable;
/// - update recommended: dismissible banner, remembered 7 days;
/// - also refreshes the policy whenever the app returns to the foreground.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appVersionStatusProvider.notifier).refresh();
    }
  }

  void _openStore() {
    ref.read(storeLauncherProvider)(ref.read(storeUriProvider));
  }

  @override
  Widget build(BuildContext context) {
    // Watching the status provider is what starts the launch fetch.
    final status = ref.watch(appVersionStatusProvider);
    final updateRequired = ref.watch(updateRequiredProvider);
    final availableFlag = ref.watch(updateAvailableProvider);
    // Null while the count loads or is unreadable: an unknown count never blocks.
    final pending = ref.watch(pendingSyncCountProvider.select((v) => v.value?.pending));

    final mode = updateGateMode(updateRequired: updateRequired, pending: pending);

    Widget? banner;
    if (mode == UpdateGateMode.syncFirst) {
      banner = UpdatePendingSyncBanner(pending: pending ?? 0, onUpdate: _openStore);
    } else if (mode == UpdateGateMode.none &&
        !updateRequired &&
        availableFlag &&
        !status.bannerDismissed) {
      banner = UpdateAvailableBanner(
        onUpdate: _openStore,
        onDismiss: () => ref.read(appVersionStatusProvider.notifier).dismissAvailable(),
      );
    }

    // Stable structure (Stack > Visibility > Column > Expanded > MediaQuery > child): the router's
    // navigator must keep the same element position whether a banner or the blocking screen is up,
    // or its whole navigation stack would be rebuilt from scratch.
    return Stack(
      fit: StackFit.expand,
      children: [
        Visibility(
          visible: mode != UpdateGateMode.blocked,
          maintainState: true,
          child: Column(
            children: [
              banner ?? const SizedBox.shrink(),
              Expanded(
                // The banner paints the status-bar inset itself; the screens below must not add it
                // a second time.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: banner != null,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
        if (mode == UpdateGateMode.blocked)
          Positioned.fill(
            child: UpdateRequiredScreen(onUpdate: _openStore, message: status.message),
          ),
      ],
    );
  }
}
