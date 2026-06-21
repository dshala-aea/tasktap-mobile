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
final connectivityProvider =
    AsyncNotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);

/// Convenience synchronous bool (true = online). May be null before first check.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull ?? false;
});
