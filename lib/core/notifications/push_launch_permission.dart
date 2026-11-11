import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_reporting.dart';
import 'push_resume_recheck.dart' show kPushPreferenceKey;

/// SharedPreferences flag: the launch-time system dialog was already raised once on this install.
const String kPushLaunchAskedKey = 'push.launch_permission_asked';

/// Raises the OS notification dialog once per install, right after the first frame.
///
/// Owner decision: the system dialog is the only ask, and it comes at launch rather than waiting
/// for the "Notifiche push" switch (Apple allows this: no custom pre-prompt may gate it and the
/// user may decline). Trade-off knowingly accepted: the prompt appears before the app has shown
/// anything about itself.
///
/// It asks only when ALL hold: the OS has never been asked ([AuthorizationStatus.notDetermined]),
/// this install has not asked before ([kPushLaunchAskedKey]) and the in-app switch is not
/// explicitly off (the technician's in-app choice wins). Any failure is swallowed — it must never
/// break launch. Everything is injected so the policy is testable without a platform.
class PushLaunchPermission {
  PushLaunchPermission({
    required this.status,
    required this.ask,
    this.onDone,
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  /// The current OS authorization status.
  final Future<AuthorizationStatus> Function() status;

  /// The system prompt (`NotificationService.ensurePermission`); true when granted.
  final Future<bool> Function() ask;

  /// Called after an ask completed, with the outcome (used to reconcile the in-app switch).
  final Future<void> Function(bool granted)? onDone;

  final Future<SharedPreferences> Function() _prefs;

  /// Returns true when the system dialog was requested.
  Future<bool> run() async {
    try {
      final prefs = await _prefs();
      if (prefs.getBool(kPushPreferenceKey) == false) return false;
      if (prefs.getBool(kPushLaunchAskedKey) == true) return false;
      if (await status() != AuthorizationStatus.notDetermined) return false;

      // Flag first: a crash or kill mid-dialog must not make the next launch ask again.
      await prefs.setBool(kPushLaunchAskedKey, true);
      var granted = false;
      try {
        granted = await ask();
      } finally {
        try {
          await onDone?.call(granted);
        } catch (e) {
          debugPrint('Push launch permission follow-up failed: $e');
        }
      }
      return true;
    } catch (e, st) {
      debugPrint('Push launch permission ask failed: $e');
      reportPushFailure(PushStage.permission, e, stackTrace: st, onceKey: 'launch-ask');
      return false;
    }
  }
}
