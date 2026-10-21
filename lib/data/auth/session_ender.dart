// dart format width=100
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/pending_recording_store.dart';
import '../../core/notifications/notification_service.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../entitlements/entitlement_service.dart' show internalUserIdPrefsKey;
import '../local/app_database.dart';
import 'session_recovery.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SessionEnder
//
// The ONE place a session ends on this device, with two deliberately different
// endings — because "the technician tapped Esci" and "the identity provider says
// the refresh token is dead" are not the same event and must not have the same
// consequences.
//
//   end()          manual logout. The technician was told how much unsent work
//                  exists (the logout dialog, `UnsentWorkCounter`) and chose to
//                  go anyway: drop credentials AND wipe the local data.
//
//   endForced()    the interceptor's forced sign-out after a confirmed
//                  `invalid_grant`. Nobody consented to anything, and this fires
//                  on the flush after a long offline period — i.e. precisely
//                  when the queues are full of work the server has never seen.
//                  Drop credentials ONLY: Drift and prefs stay. A marker records
//                  who the data belongs to, and `SessionRecoveryController`
//                  decides at the next sign-in (same account → send it; other
//                  account → explicit, confirmed discard). Never a silent wipe.
//
//   discardRetainedData()  the wipe alone, no credential change — what the
//                  recovery screen's confirmed "Elimina e continua" runs.
//
// It exists because there used to be two sequences, and only one of them was
// finished. `LoginNotifier.signOut` wiped the Drift database, cleared prefs and
// reset the business zone; `AuthInterceptor`'s forced path called
// `IAuthRepository.signOut` instead, which deletes the secure-storage refresh
// token and the cached identity and nothing else. So when an expired session
// forced a sign-out, the previous user's tickets, customers, cantieri and
// settings stayed on the device — on vans and shared tablets where the next
// person to sign in may be from a different tenant entirely. The fix for that
// cannot be "wipe on both paths": the audit's F1 is what that costs, because the
// forced path runs while unsent work is still queued. One class, two endings,
// and a wipe that only the consented paths can reach.
// ══════════════════════════════════════════════════════════════════════════════

class SessionEnder {
  SessionEnder({
    required IAuthRepository repo,
    required AppDatabase db,
    required Future<void> Function() resetBusinessZone,
    Future<void> Function()? wipePendingVoice,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _wipePendingVoice = wipePendingVoice ?? _wipeAppPendingVoice,
       _prefs = prefsLoader ?? SharedPreferences.getInstance,
       _repo = repo,
       _db = db,
       _resetBusinessZone = resetBusinessZone;

  /// Unsent voice recordings are raw audio of the previous user: removed on logout. Best-effort,
  /// like the rest of the wipe (a failure here must not skip the Drift/prefs wipe).
  final Future<void> Function() _wipePendingVoice;

  static Future<void> _wipeAppPendingVoice() async =>
      (await PendingRecordingStore.forApp()).wipe();

  final IAuthRepository _repo;
  final AppDatabase _db;
  final Future<SharedPreferences> Function() _prefs;

  /// Riverpod state outlives the prefs wipe: without this the next tenant would inherit this
  /// tenant's business zone until its own `/me` answers. Passed in rather than read here so this
  /// stays free of the providers layer — the interceptor reaches it through `sessionEnderProvider`
  /// (`presentation/providers/auth_providers.dart`).
  final Future<void> Function() _resetBusinessZone;

  /// Manual logout — the consented ending: credentials and local data both go.
  ///
  /// The order is load-bearing. The FCM unregister has to happen *before* `signOut()`, because the
  /// access token it needs is gone the moment sign-out completes — and a device that stays
  /// registered keeps receiving push for an account no longer signed in on it. This mirrors the same
  /// guard/token-source `_syncPushRegistration` uses in impostazioni_provider.dart.
  Future<void> end() async {
    await _unregisterPush();
    await _repo.signOut();
    await _wipeLocalData();
  }

  /// Forced sign-out — the identity provider confirmed the session is dead
  /// ([SessionExpired]). Credentials only: the local database and preferences are KEPT, because
  /// the work in them is still unsent and may belong to the technician who is about to sign back
  /// in. See the class comment and `SessionRecoveryController`.
  Future<void> endForced() async {
    // Before signOut: the OIDC subject is only readable while the session still exists, and the
    // marker is what tells the next sign-in whose data this is. If the process dies right after
    // this line, nothing has been lost — the data is still there, only the marker is set.
    await _recordRetainedOwner();
    await _unregisterPush();
    await _repo.signOut();
  }

  /// Wipe the previous owner's local data WITHOUT touching the current session — the confirmed
  /// discard from the session-recovery screen. Same wipe as [end], minus the credential teardown.
  Future<void> discardRetainedData() => _wipeLocalData();

  Future<void> _unregisterPush() async {
    if (!NotificationService.isAvailable) return;
    final token = _repo.currentUser?.accessToken;
    if (token == null || token.isEmpty) return;
    await NotificationService.instance.unregisterDeviceToken(token);
  }

  /// Name the owner of the data this forced sign-out leaves behind.
  ///
  /// Best-effort: a device whose prefs cannot be written still keeps its data (the important part);
  /// the consequence is only that the next sign-in cannot tell "same account" from "different
  /// account", so it treats the data as foreign and asks before discarding — the safe direction.
  Future<void> _recordRetainedOwner() async {
    final sub = _repo.currentUser?.id;
    if (sub == null || sub.isEmpty) return;
    try {
      final prefs = await _prefs();
      final internalId = prefs.getString(internalUserIdPrefsKey);
      await prefs.setString(sessionRetainedOwnerSubKey, sub);
      if (internalId != null && internalId.isNotEmpty) {
        await prefs.setString(sessionRetainedOwnerInternalIdKey, internalId);
      }
    } catch (_) {
      // Best-effort, as above.
    }
  }

  /// This is a shared/rotating-device field-service app (van tablets, rotating technicians) —
  /// leaving the local Drift DB and SharedPreferences populated after a CONSENTED sign-out would
  /// let the next person to sign in on this device (possibly a different tenant entirely) see the
  /// previous account's full cached tickets/customers/cantieri/notifications and settings.
  ///
  /// Only the consented paths reach this: [end] and the recovery screen's explicit discard.
  Future<void> _wipeLocalData() async {
    try {
      await _wipePendingVoice();
    } on Object {
      // best-effort: never block the rest of the teardown
    }
    try {
      await _db.wipeAllData();
      await (await _prefs()).clear();
    } finally {
      // In `finally` so a failing wipe cannot skip it.
      await _resetBusinessZone();
    }
  }
}
