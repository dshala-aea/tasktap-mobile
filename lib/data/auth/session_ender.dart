// dart format width=100
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/notification_service.dart';
import '../../domain/auth/i_auth_repository.dart';
import '../local/app_database.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SessionEnder
//
// The ONE teardown that ends a session on this device, whatever ended it: the
// technician pressing "Esci", or the identity provider confirming the refresh
// token is dead and the network layer forcing them out.
//
// It exists because there used to be two sequences, and only one of them was
// finished. `LoginNotifier.signOut` wiped the Drift database, cleared prefs and
// reset the business zone; `AuthInterceptor`'s forced path called
// `IAuthRepository.signOut` instead, which deletes the secure-storage refresh
// token and the cached identity and nothing else. So when an expired session
// forced a sign-out, the previous user's tickets, customers, cantieri and
// settings stayed on the device — on vans and shared tablets where the next
// person to sign in may be from a different tenant entirely.
//
// Anything that ends a session goes through [end]. Two callers, one sequence,
// and a step added here cannot be missing from one of them.
// ══════════════════════════════════════════════════════════════════════════════

class SessionEnder {
  SessionEnder({
    required IAuthRepository repo,
    required AppDatabase db,
    required Future<void> Function() resetBusinessZone,
  }) : _repo = repo,
       _db = db,
       _resetBusinessZone = resetBusinessZone;

  final IAuthRepository _repo;
  final AppDatabase _db;

  /// Riverpod state outlives the prefs wipe: without this the next tenant would inherit this
  /// tenant's business zone until its own `/me` answers. Passed in rather than read here so this
  /// stays free of the providers layer — the interceptor reaches it through `sessionEnderProvider`
  /// (`presentation/providers/auth_providers.dart`).
  final Future<void> Function() _resetBusinessZone;

  /// End the session: unregister this device from push, drop the credentials, and leave nothing of
  /// the previous user behind.
  ///
  /// The order is load-bearing. The FCM unregister has to happen *before* `signOut()`, because the
  /// access token it needs is gone the moment sign-out completes — and a device that stays
  /// registered keeps receiving push for an account no longer signed in on it. This mirrors the same
  /// guard/token-source `_syncPushRegistration` uses in impostazioni_provider.dart.
  Future<void> end() async {
    if (NotificationService.isAvailable) {
      final token = _repo.currentUser?.accessToken;
      if (token != null && token.isNotEmpty) {
        await NotificationService.instance.unregisterDeviceToken(token);
      }
    }
    await _repo.signOut();

    // This is a shared/rotating-device field-service app (van tablets, rotating technicians) —
    // leaving the local Drift DB and SharedPreferences populated after sign-out would let the next
    // person to sign in on this device (possibly a different tenant entirely) see the previous
    // account's full cached tickets/customers/cantieri/notifications and settings.
    try {
      await _db.wipeAllData();
      await (await SharedPreferences.getInstance()).clear();
    } finally {
      // In `finally` so a failing wipe cannot skip it.
      await _resetBusinessZone();
    }
  }
}
