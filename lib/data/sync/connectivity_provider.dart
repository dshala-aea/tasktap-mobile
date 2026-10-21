// dart format width=100
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ConnectivityProvider
//
// Exposes the current online/offline status via Riverpod.
// Detects the offline→online transition and fires a callback so the
// SubmissionQueue can be triggered automatically.
// ══════════════════════════════════════════════════════════════════════════════

/// True when the device has at least one active non-none connectivity type.
bool _isOnline(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}

/// A StreamNotifier that emits [true] when online, [false] when offline.
class ConnectivityNotifier extends AsyncNotifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  Future<bool> build() async {
    ref.onDispose(() => _sub?.cancel());

    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    final initialOnline = _isOnline(initial);

    _sub = connectivity.onConnectivityChanged.listen(_onResult);

    return initialOnline;
  }

  void _onResult(List<ConnectivityResult> results) {
    final wasOnline = state.valueOrNull ?? false;
    final nowOnline = _isOnline(results);
    state = AsyncValue.data(nowOnline);

    // offline → online transition: trigger submission queue
    if (!wasOnline && nowOnline) {
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
