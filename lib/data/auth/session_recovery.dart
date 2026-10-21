// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unsent_work_counter.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Session recovery — what happens to a forced sign-out's leftovers
//
// A forced sign-out (the identity provider confirmed `invalid_grant`) is NOT a
// logout. Nobody consented to losing anything, and it routinely fires *while*
// the queues are trying to send: a technician who spent a week offline gets 401
// on the very first flush after reconnecting. Wiping Drift there deletes the
// work the flush was about to upload (audit F1).
//
// So the forced path clears credentials only and records who the local data
// belongs to. The decision is deferred to the next sign-in, which is the first
// moment anyone can be asked:
//
//   same account  → the data is theirs: keep it, and flush the queues (already
//                   running through the startup watchers; this module also
//                   triggers one explicitly).
//   other account → the previous tenant's rows must not be shown to this one,
//                   but the discard is made explicit on the session-recovery
//                   screen — never a silent wipe.
//
// The marker lives in SharedPreferences because the forced path deliberately
// does NOT clear prefs (clearing them is part of the wipe, and would also erase
// the very marker that says a wipe is pending). No Drift schema change.
//
// Identity: the marker stores the Zitadel OIDC `sub` (`AuthUser.id`), which is
// stable for an account across sign-ins, and, for diagnostics, the internal
// `Users.Id` the device last saw. The comparison is on the `sub` alone: at
// sign-in time the internal id in prefs is still the *previous* session's value
// (`/auth/me` has not answered yet), so comparing internal ids here would
// compare the previous session with itself and always "match".
// ══════════════════════════════════════════════════════════════════════════════

/// OIDC `sub` of the account whose local data a forced sign-out left behind.
const String sessionRetainedOwnerSubKey = 'session_recovery.owner_sub';

/// The internal `Users.Id` that account had last been seen with — diagnostics only, never the
/// comparison key (see the file comment).
const String sessionRetainedOwnerInternalIdKey = 'session_recovery.owner_internal_id';

/// What the router needs to know about a signed-in session's leftovers.
sealed class SessionRecoveryState {
  const SessionRecoveryState();
}

/// Nothing is waiting: no forced sign-out left data behind, the account that came back is the
/// one that owns it, or the previous owner's data has been discarded.
final class SessionRecoveryIdle extends SessionRecoveryState {
  const SessionRecoveryIdle();
}

/// A different account signed in on a device that still holds the previous account's local
/// data. The app must not proceed — and must not wipe silently — until the discard is confirmed.
/// [unsentCount] is how much unsent work goes with it.
final class SessionRecoveryNeedsDiscard extends SessionRecoveryState {
  const SessionRecoveryNeedsDiscard(this.unsentCount);

  final int unsentCount;

  @override
  bool operator ==(Object other) =>
      other is SessionRecoveryNeedsDiscard && other.unsentCount == unsentCount;

  @override
  int get hashCode => unsentCount.hashCode;

  @override
  String toString() => 'SessionRecoveryNeedsDiscard($unsentCount)';
}

/// Decides, once per signed-in account, whether the local data a forced sign-out left behind
/// belongs to the account now signing in, and exposes the discard action the recovery screen
/// needs.
class SessionRecoveryController extends StateNotifier<SessionRecoveryState> {
  SessionRecoveryController({
    required UnsentWorkCounter counter,
    required Future<void> Function() discardLocalData,
    Future<SharedPreferences> Function()? prefsLoader,
    Future<void> Function()? flushQueues,
  }) : _counter = counter,
       _discardLocalData = discardLocalData,
       _prefs = prefsLoader ?? SharedPreferences.getInstance,
       _flushQueues = flushQueues,
       super(const SessionRecoveryIdle());

  final UnsentWorkCounter _counter;

  /// The user-consented wipe itself — provided by `SessionEnder.discardRetainedData`.
  final Future<void> Function() _discardLocalData;

  final Future<SharedPreferences> Function() _prefs;

  /// Runs when the same account comes back: the queues are that account's own work and must be
  /// sent. Optional so the controller stays testable without the whole queue graph.
  final Future<void> Function()? _flushQueues;

  /// The account this controller already answered for. Sign-in for the same `sub` is asked once
  /// (the router calls [resolveFor] on every redirect), while a different account re-resolves.
  String? _resolvedFor;

  /// Answers "what should happen to the local data for [sub]?" and caches the answer for that
  /// account.
  ///
  /// Fail-open on a prefs read error (no marker → idle): a device whose preferences cannot be
  /// read has no retained-outbox marker to honour, and blocking every sign-in on a storage hiccup
  /// would lock the technician out of the app entirely.
  Future<SessionRecoveryState> resolveFor(String sub) async {
    if (_resolvedFor == sub) return state;
    _resolvedFor = sub;

    SharedPreferences prefs;
    try {
      prefs = await _prefs();
    } catch (_) {
      state = const SessionRecoveryIdle();
      return state;
    }

    final ownerSub = prefs.getString(sessionRetainedOwnerSubKey);
    if (ownerSub == null) {
      state = const SessionRecoveryIdle();
      return state;
    }

    if (ownerSub == sub) {
      // The owner is back. Their work is still theirs: clear the marker so this decision is not
      // re-made, and let the queues send what they kept. Fire-and-forget — navigation must not
      // wait for a flush that can take as long as the backlog does.
      await _clearMarker(prefs);
      final flush = _flushQueues;
      if (flush != null) unawaited(flush().catchError((Object _) {}));
      state = const SessionRecoveryIdle();
      return state;
    }

    // A counting failure must not skip the gate (that would be the silent wipe this exists to
    // prevent): report zero and still ask. The screen's copy has a zero-item wording.
    int count;
    try {
      count = (await _counter.count()).total;
    } catch (_) {
      count = 0;
    }
    state = SessionRecoveryNeedsDiscard(count);
    return state;
  }

  /// The explicit discard the recovery screen offers. Wipes only after the technician confirmed;
  /// the current session's credentials are untouched.
  Future<void> discard() async {
    await _discardLocalData();
    _resolvedFor = null;
    state = const SessionRecoveryIdle();
  }

  /// Forget the cached answer — call when the session ends (the technician chose "Esci" on the
  /// recovery screen) so the next sign-in is judged on its own.
  void reset() {
    _resolvedFor = null;
    state = const SessionRecoveryIdle();
  }

  Future<void> _clearMarker(SharedPreferences prefs) async {
    try {
      await prefs.remove(sessionRetainedOwnerSubKey);
      await prefs.remove(sessionRetainedOwnerInternalIdKey);
    } catch (_) {
      // Best-effort: the worst case is this decision being re-made on the next sign-in, which
      // resolves the same way.
    }
  }
}
