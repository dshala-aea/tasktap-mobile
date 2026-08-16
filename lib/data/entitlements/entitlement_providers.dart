// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// Entitlement providers
//
// The cache is refreshed on reconnect for the same reason the auth session is:
// a technician who was offline should get the current answer as soon as there
// is one, not on the next incidental API call.
//
// Nothing here can *deny* on failure — see EntitlementRepository for why that
// asymmetry is deliberate.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../sync/connectivity_provider.dart';
import '../sync/sync_service.dart';
import 'entitlement_repository.dart';
import 'entitlement_service.dart';

final entitlementRepositoryProvider = Provider<EntitlementRepository>((ref) {
  return EntitlementRepository(ref.watch(appDatabaseProvider));
});

final entitlementServiceProvider = Provider<EntitlementService>((ref) {
  return EntitlementService(
    dio: ref.watch(dioProvider),
    repository: ref.watch(entitlementRepositoryProvider),
  );
});

/// Whether a module should be offered. Read this rather than the repository directly.
final hasFeatureProvider = FutureProvider.family<bool, String>((ref, moduleKey) {
  return ref.watch(entitlementRepositoryProvider).hasFeature(moduleKey);
});

/// The cached answer, for screens that want to show when it was last confirmed.
final cachedEntitlementProvider = FutureProvider<Entitlement?>((ref) {
  return ref.watch(entitlementRepositoryProvider).read();
});

/// Call once on app start, alongside initAuthReconnectWatcher.
///
/// Fetches immediately as well as on every reconnect. Reconnect alone was not enough and the
/// omission was invisible: a device that is online at launch and never drops signal never
/// reconnects, so it never fetched, so the cache stayed null and every screen reading it fell back
/// to the field-seat baseline forever. An office user on good wifi would have been the *worst*
/// served by a watcher that only listens for the network coming back.
void initEntitlementRefreshWatcher(WidgetRef ref) {
  Future<void> refresh() async {
    final updated = await ref.read(entitlementServiceProvider).refresh();
    // Only invalidate on a real change — a failed refresh must not churn the UI into
    // re-reading a cache that did not move.
    if (updated) {
      ref.invalidate(cachedEntitlementProvider);
      ref.invalidate(hasFeatureProvider);
    }
  }

  refresh();
  ref.read(connectivityProvider.notifier).onReconnect(refresh);
}
