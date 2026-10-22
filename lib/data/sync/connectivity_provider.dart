// dart format width=100
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ConnectivityProvider
//
// Exposes "the backend is reachable" via Riverpod — NOT "an interface is up". The interface is
// only the trigger; the answer comes from [ReachabilityProbe], because a captive portal, a Wi-Fi
// whose upstream is down and a hotel network nobody paid for all look like a working connection to
// `connectivity_plus`, and every freshness and offline-fallback decision in the app hangs off this
// one bool.
//
// Detects the offline→online transition and fires a callback so the SubmissionQueue can be
// triggered automatically.
// ══════════════════════════════════════════════════════════════════════════════

import 'reachability.dart' show reachabilityProbeProvider;

/// True when the device has at least one active non-none connectivity type.
bool _isOnline(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}

/// Emits [true] when the backend answers, [false] when it does not.
///
/// The radio is the trigger, not the verdict: every interface change re-asks the probe, and while
/// the interface is up but the backend does not answer, the probe is retried on a timer so the app
/// comes back online on its own once the portal clears or the upstream recovers — nobody should
/// have to toggle Wi-Fi to make the app notice.
class ConnectivityNotifier extends AsyncNotifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _retry;
  bool _interfaceUp = false;
  bool _disposed = false;

  /// The last verdict handed to listeners — see [_publish] for why this is not read from `state`.
  bool _lastPublished = false;

  /// Bumped for every evaluation so a slow probe that lands after a newer one cannot publish a
  /// stale verdict.
  int _generation = 0;

  static const retryInterval = Duration(seconds: 20);

  @override
  Future<bool> build() async {
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _retry?.cancel();
    });

    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    _sub = connectivity.onConnectivityChanged.listen(_onResult);

    _interfaceUp = _isOnline(initial);
    if (!_interfaceUp) return false;
    return _evaluate();
  }

  void _onResult(List<ConnectivityResult> results) {
    final up = _isOnline(results);
    if (up == _interfaceUp) return;
    _interfaceUp = up;
    unawaited(_evaluate());
  }

  /// Asks the probe and publishes the combined answer. Never throws.
  Future<bool> _evaluate() async {
    final gen = ++_generation;
    if (!_interfaceUp) {
      // No interface: no need to ask anyone. Publish immediately, it is the one case where the
      // radio's answer is the whole answer.
      _retry?.cancel();
      _retry = null;
      _publish(false);
      return false;
    }

    final reachable = await ref.read(reachabilityProbeProvider).isReachable();
    if (_disposed || gen != _generation) return reachable;

    _publish(reachable);
    if (reachable) {
      _retry?.cancel();
      _retry = null;
    } else if (_retry == null) {
      _retry = Timer.periodic(retryInterval, (_) => unawaited(_evaluate()));
    }
    return reachable;
  }

  void _publish(bool online) {
    if (_disposed) return;
    // Tracked here rather than read back through `state`: the first verdict is published from
    // inside `build` (after the probe's await), where the element's value is still the initial
    // AsyncLoading and must not be treated as a previous "offline" answer.
    final wasOnline = _lastPublished;
    _lastPublished = online;
    state = AsyncValue.data(online);

    // offline → online transition: trigger submission queue
    if (!wasOnline && online) {
      _onReconnect();
    }
  }

  void _onReconnect() {
    // Notify reconnect listeners.
    for (final listener in _reconnectListeners) {
      listener();
    }
  }

  final List<VoidCallback> _reconnectListeners = [];

  /// Register a callback that fires on every offline→online transition.
  /// Returns a function to cancel the subscription.
  VoidCallback onReconnect(VoidCallback callback) {
    _reconnectListeners.add(callback);
    return () => _reconnectListeners.remove(callback);
  }
}

typedef VoidCallback = void Function();

/// Global connectivity state provider.
final connectivityProvider = AsyncNotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);

/// Convenience synchronous bool (true = online). May be null before first check.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull ?? false;
});

/// True only on an unmetered Wi-Fi link. Asked at the moment it matters (a prefetch sweep), not
/// watched — nothing in the UI branches on it.
///
/// Decision D-4 (2026-10-21 offline audit): downloading a report's photos is fine on Wi-Fi and
/// expensive on mobile data, so the [AttachmentPrefetcher] stays off it. Ethernet is accepted: no
/// phone has one, and a docked tablet on a cable is not metered either.
Future<bool> onUnmeteredWifi() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
  } catch (_) {
    // No platform answer (tests, an unsupported runner): treat as "do not spend the user's data".
    return false;
  }
}
