// ══════════════════════════════════════════════════════════════════════════════
// Badge providers — "Il mio badge"
//
// The controller owns the rotating-token lifecycle: fetch on open, refresh every 25s while the
// screen is alive, stop while the app is in the background, and re-fetch (showing loading, never
// the old code) on resume. The token is the QR payload — it is held in memory in the view state
// only: never logged, persisted or put in a URL.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/badge/badge_api_client.dart';
import '../../data/badge/badge_models.dart';

// ── View state ────────────────────────────────────────────────────────────────

sealed class BadgeViewState {
  const BadgeViewState();
}

/// First fetch, or a re-fetch after the app came back to the foreground. No QR is shown.
class BadgeLoading extends BadgeViewState {
  const BadgeLoading();
}

/// A usable badge. [fetchedAt] is when [card]'s token was issued by the server.
class BadgeReady extends BadgeViewState {
  const BadgeReady(this.card, this.fetchedAt);
  final BadgeCard card;
  final DateTime fetchedAt;
}

/// 409 badge_revoked. Terminal until the user leaves: no retry loop, no QR.
class BadgeRevoked extends BadgeViewState {
  const BadgeRevoked();
}

/// 409 user_inactive. Terminal until the user leaves: no retry loop, no QR.
class BadgeInactive extends BadgeViewState {
  const BadgeInactive();
}

/// No signal (connection/timeout, or the gateway said 502/503/504). The badge needs the server.
class BadgeOffline extends BadgeViewState {
  const BadgeOffline();
}

/// Anything else that went wrong (other HTTP status, malformed body). Shown like [BadgeOffline].
class BadgeError extends BadgeViewState {
  const BadgeError(this.message);
  final String message;
}

// ── Seams ─────────────────────────────────────────────────────────────────────

/// How often the token is rotated while the screen is visible. Well inside the server's token
/// lifetime; overridden in tests.
final badgeRefreshIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 25));

/// How long before the token's server-side expiry a shown QR is pulled from the screen if no
/// fresh one has arrived (a refresh may be stuck on a slow network). Overridden in tests.
final badgeExpiryMarginProvider = Provider<Duration>((ref) => const Duration(seconds: 5));

/// Keeps the screen awake while the badge is on display. A seam because the plugin has no
/// platform in widget tests; every call swallows platform errors so a missing channel can never
/// take the screen down.
class BadgeWakelock {
  const BadgeWakelock();

  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // No platform channel (tests, unsupported platform): the badge still works, it may dim.
    }
  }

  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}

final badgeWakelockProvider = Provider<BadgeWakelock>((ref) => const BadgeWakelock());

// ── Controller ────────────────────────────────────────────────────────────────

class BadgeController extends AutoDisposeNotifier<BadgeViewState> {
  Timer? _timer;
  Timer? _expiryTimer;
  _LifecycleObserver? _observer;
  bool _disposed = false;
  bool _paused = false;

  /// Bumped on every pause/resume/manual refresh so a response that was in flight across one of
  /// them is dropped instead of re-showing a QR the controller already hid.
  int _generation = 0;

  @override
  BadgeViewState build() {
    _disposed = false;
    _observer = _LifecycleObserver(_onLifecycle);
    WidgetsBinding.instance.addObserver(_observer!);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _timer?.cancel();
      _timer = null;
      _expiryTimer?.cancel();
      _expiryTimer = null;
      final o = _observer;
      if (o != null) WidgetsBinding.instance.removeObserver(o);
    });
    // Fetch on open — after build() returns, since a Notifier cannot write state inside build.
    scheduleMicrotask(() {
      if (!_disposed) refresh(showLoading: false);
    });
    return const BadgeLoading();
  }

  /// Fetches a fresh token. [showLoading] hides the current QR while the request is in flight
  /// (manual retry, resume); the silent timer path keeps the still-valid code on screen.
  Future<void> refresh({bool showLoading = true}) async {
    if (_disposed) return;
    final gen = ++_generation;
    _timer?.cancel();
    _timer = null;
    // A silent refresh deliberately leaves the expiry timer running: if the response is slow the
    // old QR must still be pulled before its token dies.
    if (showLoading) _setState(const BadgeLoading());

    BadgeViewState next;
    try {
      final card = await ref.read(badgeApiClientProvider).getMyBadge();
      next = BadgeReady(card, DateTime.now());
    } on BadgeApiException catch (e) {
      if (e.isRevoked) {
        next = const BadgeRevoked();
      } else if (e.isInactive) {
        next = const BadgeInactive();
      } else if (e.isOffline || _isGatewayStatus(e.statusCode)) {
        next = const BadgeOffline();
      } else {
        next = BadgeError(e.message);
      }
    } catch (e) {
      // Malformed body (TypeError), empty body, anything unforeseen: never escape, never a QR.
      next = const BadgeError('Risposta non valida dal server');
    }

    if (_disposed || gen != _generation) return;
    _setState(next);
    // Revoked / inactive are final: polling would only hammer the server with a doomed call.
    if (next is BadgeRevoked || next is BadgeInactive) return;
    _startTimer();
  }

  /// Every state write goes through here so the expiry timer always matches the current state.
  void _setState(BadgeViewState next) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    state = next;
    if (next is BadgeReady) {
      final margin = ref.read(badgeExpiryMarginProvider);
      final life = Duration(seconds: next.card.expiresInSeconds) - margin;
      final after = life < const Duration(seconds: 5) ? const Duration(seconds: 5) : life;
      _expiryTimer = Timer(after, () {
        if (_disposed || !identical(state, next)) return;
        // The token is about to die and nothing fresher arrived: never show it.
        state = const BadgeLoading();
      });
    }
  }

  static bool _isGatewayStatus(int? s) => s != null && s >= 500;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(ref.read(badgeRefreshIntervalProvider), () {
      if (!_disposed && !_paused) refresh(showLoading: false);
    });
  }

  void _onLifecycle(AppLifecycleState s) {
    if (_disposed) return;
    switch (s) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_paused) return;
        _paused = true;
        _generation++;
        _timer?.cancel();
        _timer = null;
        _expiryTimer?.cancel();
        _expiryTimer = null;
        // Hide the code now: whatever comes back from the foreground must be a fresh one.
        final cur = state;
        if (cur is BadgeReady || cur is BadgeOffline || cur is BadgeError) {
          _setState(const BadgeLoading());
        }
      case AppLifecycleState.resumed:
        if (!_paused) return;
        _paused = false;
        final cur = state;
        if (cur is BadgeRevoked || cur is BadgeInactive) return;
        refresh();
      case AppLifecycleState.inactive:
        break;
    }
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._onChange);
  final void Function(AppLifecycleState) _onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onChange(state);
}

final badgeControllerProvider =
    NotifierProvider.autoDispose<BadgeController, BadgeViewState>(BadgeController.new);
