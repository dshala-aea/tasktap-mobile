// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// WorkLogLiveRefresh
//
// Keeps a screen that shows the running clock honest about what other devices did. Wraps the
// dashboard and the timbra screen.
//
// The primary channel is the SignalR `WorkLogChanged` push (see realtime_event_router.dart). This
// is the safety net for when that channel is down or has not been re-established yet:
//  - refresh as soon as the screen appears (every time — including a tab being shown again),
//  - refresh the moment the app returns to the foreground,
//  - poll every 15s, ONLY while this screen is visible AND the app is foregrounded AND the
//    "Sincronizza dati in background" preference (backgroundSyncPreferenceProvider) is on — the
//    same switch that already governs the 60s HomeShell poll.
//
// Not covered here: a BACKGROUNDED app. That needs an FCM data-only push from the backend on
// WorkLogChanged (backend follow-up); until then it converges on the next resume.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_service.dart' show backgroundSyncPreferenceProvider;
import '../../data/timbratura/work_log_refresh_coordinator.dart';

class WorkLogLiveRefresh extends ConsumerStatefulWidget {
  const WorkLogLiveRefresh({super.key, required this.child});

  final Widget child;

  static const pollInterval = Duration(seconds: 15);

  @override
  ConsumerState<WorkLogLiveRefresh> createState() => _WorkLogLiveRefreshState();
}

class _WorkLogLiveRefreshState extends ConsumerState<WorkLogLiveRefresh>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _foreground = true;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A tab of the shell stays mounted while hidden; TickerMode is switched off for it. Treat
    // "became visible" as "appeared" so returning to the dashboard refreshes too.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _refresh();
      _syncPoll();
    } else {
      _stopPoll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      if (_visible) _refresh();
      _syncPoll();
    } else {
      _stopPoll();
    }
  }

  /// Deferred to a microtask: this can be reached from didChangeDependencies, i.e. mid-build, and a
  /// provider (activeTrackersProvider) must not be invalidated while the tree is building.
  void _refresh() => Future.microtask(() {
    if (mounted) unawaited(ref.read(workLogRefreshCoordinatorProvider).refreshNow());
  });

  void _syncPoll() {
    _stopPoll();
    if (!_visible || !_foreground) return;
    if (!ref.read(backgroundSyncPreferenceProvider)) return;
    _poll = Timer.periodic(WorkLogLiveRefresh.pollInterval, (_) => _refresh());
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPoll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
