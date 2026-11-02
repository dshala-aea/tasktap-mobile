// dart format width=100
//
// Who owns the local database a session ending left on this device?
//
// A session can end without anyone consenting to it in two ways, and both of them KEEP the Drift
// database on purpose (a dead session routinely fires on the first flush after a week offline,
// i.e. with every outbox full — offline audit F1):
//
//   1. in flight — a 401 the identity provider confirmed as `invalid_grant`, handled by
//      `AuthInterceptor` → `SessionEnder.endForced()`;
//   2. at cold start — the stored refresh token is already dead when `_restore()` redeems it, so
//      there was never a request to fail.
//
// Neither leaves a signed-in account behind, and the next person at the device may be a different
// tenant entirely (van tablets, rotating technicians). So before the identity goes, both paths
// must write the same marker saying whose data this is. `SessionRecoveryController` reads it at the
// next sign-in: same account → the data is theirs and the queues flush; other account → the
// explicit discard screen.
//
// This file exists because that marker used to be written in exactly one of the two places
// (`SessionEnder`), and the cold-start path silently skipped it. A missing marker reads as
// "nothing waiting", so a different account inherited the previous tenant's tickets, customers and
// sync cursor with no prompt — and then synced a delta from that stale cursor.
// ══════════════════════════════════════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

import '../entitlements/entitlement_service.dart' show internalUserIdPrefsKey;

/// OIDC `sub` of the account whose local data a session ending left behind.
const String sessionRetainedOwnerSubKey = 'session_recovery.owner_sub';

/// The internal `Users.Id` that account had last been seen with — diagnostics only, never the
/// comparison key (see `SessionRecoveryController.resolveFor`).
const String sessionRetainedOwnerInternalIdKey = 'session_recovery.owner_internal_id';

/// Name [sub] as the owner of the local data this session ending leaves on the device.
///
/// Best-effort by contract, and honest about what that costs: a failed write must not block the
/// ending (the local data is kept either way — that is the important part), but a missing marker
/// is NOT read as "foreign". `SessionRecoveryController.resolveFor` answers "idle" when there is
/// no marker, so no gate fires — the exact leak this file exists to close. The write is therefore
/// bounded ([timeout]) but never skipped, and the only case it is skipped is [sub] being
/// null/empty: nobody is left to name, and inventing a sentinel would gate an account that never
/// owned the data.
///
/// [timeout] is not decoration. The cold-start caller awaits this BEFORE it emits, and the router
/// stays on the splash screen until something is emitted (the App Store build-1.0 hang) — so a
/// wedged `SharedPreferences` platform channel must cost a couple of seconds, never the whole
/// start.
Future<void> recordRetainedOwner(
  String? sub, {
  Future<SharedPreferences> Function()? prefsLoader,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (sub == null || sub.isEmpty) return;
  try {
    await _write(sub, prefsLoader ?? SharedPreferences.getInstance).timeout(timeout);
  } catch (_) {
    // Best-effort, as above.
  }
}

Future<void> _write(
  String sub,
  Future<SharedPreferences> Function() prefsLoader,
) async {
  final prefs = await prefsLoader();
  final internalId = prefs.getString(internalUserIdPrefsKey);
  await prefs.setString(sessionRetainedOwnerSubKey, sub);
  if (internalId != null && internalId.isNotEmpty) {
    await prefs.setString(sessionRetainedOwnerInternalIdKey, internalId);
  }
}
