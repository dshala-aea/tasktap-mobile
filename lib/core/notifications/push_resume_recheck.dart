import 'dart:async';

import 'push_reporting.dart';

/// SharedPreferences key of the in-app "Notifiche push" switch (Impostazioni). Shared so the
/// resume re-check reads the very value the switch writes.
const String kPushPreferenceKey = 'settings.push_abilitate';

/// Re-evaluates push registration when the app returns to the foreground.
///
/// Covers two things that otherwise wait for the next cold start: permission granted in the iOS
/// Settings app while TaskTap was in the background, and an APNs token that arrived after the first
/// fetch gave up. It NEVER asks the OS for permission — Apple only allows that through the system
/// prompt, which stays behind the "Notifiche push" sheet / onboarding. A permission that is not
/// already granted ends the check.
///
/// The in-app preference wins: when the technician switched "Notifiche push" off, nothing is
/// fetched or registered here (the switch already unregistered the device).
///
/// Everything is injected so the policy is testable without a lifecycle or a platform.
class PushResumeRecheck {
  PushResumeRecheck({
    required this.accessToken,
    required this.pushPreferenceEnabled,
    required this.permissionGranted,
    required this.hasToken,
    required this.fetchToken,
    required this.register,
    DateTime Function()? now,
    this.maxAttempts = 3,
    this.baseBackoff = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  /// The signed-in user's access token, or null when nobody is signed in.
  final String? Function() accessToken;
  final Future<bool> Function() pushPreferenceEnabled;
  final Future<bool> Function() permissionGranted;
  final bool Function() hasToken;

  /// Runs the bounded APNs-wait fetch; true when a token is now held.
  final Future<bool> Function() fetchToken;
  final Future<void> Function(String accessToken) register;
  final DateTime Function() _now;

  /// Fetch attempts allowed per app run; a device that keeps failing does not loop on every resume.
  final int maxAttempts;

  /// Wait before the second attempt, doubling after each further one.
  final Duration baseBackoff;

  bool _inFlight = false;
  int _attempts = 0;
  DateTime? _lastAttempt;

  /// Call on `AppLifecycleState.resumed`. Never throws.
  Future<void> onResumed() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _run();
    } catch (e) {
      pushBreadcrumb('resume re-check failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _run() async {
    final token = accessToken();
    if (token == null || token.isEmpty) return;
    if (hasToken()) return;
    if (_attempts >= maxAttempts) return;

    final last = _lastAttempt;
    if (last != null) {
      final wait = baseBackoff * (1 << (_attempts - 1));
      if (_now().difference(last) < wait) return;
    }

    if (!await pushPreferenceEnabled()) {
      pushBreadcrumb('resume re-check skipped: push switched off in the app');
      return;
    }

    if (!await permissionGranted()) {
      reportPushEvent(
        PushStage.permission,
        'resume re-check: permission not granted',
        onceKey: 'resume:denied',
      );
      return;
    }

    reportPushEvent(
      PushStage.permission,
      'resume re-check: permission granted, no token yet',
      onceKey: 'resume:granted',
    );
    _attempts++;
    _lastAttempt = _now();

    if (!await fetchToken()) return;
    reportPushEvent(
      PushStage.tokenFetch,
      'resume re-check: token obtained',
      onceKey: 'resume:token',
    );
    await register(token);
    reportPushEvent(
      PushStage.deviceRegistration,
      'resume re-check: registration requested',
      onceKey: 'resume:registered',
    );
  }
}
