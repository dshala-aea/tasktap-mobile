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

import '../../core/time/business_time_providers.dart';
import '../../presentation/providers/auth_providers.dart';
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
    // Every /me answer decides the zone: a missing or invalid one resets to Rome.
    onTenantTimeZone: (zone) => ref.read(businessZoneIdProvider.notifier).applyServerZone(zone),
    currentSessionId: () => ref.read(authRepositoryProvider).currentUser?.id,
  );
});

/// Whether a module should be offered. Read this rather than the repository directly.
final hasFeatureProvider = FutureProvider.family<bool, String>((ref, moduleKey) {
  return ref.watch(entitlementRepositoryProvider).hasFeature(moduleKey);
});

/// Whether a specific `module.resource.action` capability is held. Unlike [hasFeatureProvider],
/// fail-closed when nothing is cached — see [EntitlementRepository.hasCapability]'s own doc
/// comment for why a capability has no safe baseline to guess at. Read by [CapabilityGate].
final hasCapabilityProvider = FutureProvider.family<bool, String>((ref, key) {
  return ref.watch(entitlementRepositoryProvider).hasCapability(key);
});

/// The cached answer, for screens that want to show when it was last confirmed.
final cachedEntitlementProvider = FutureProvider<Entitlement?>((ref) {
  return ref.watch(entitlementRepositoryProvider).read();
});

/// The effective clock-in method as a plain string ('Both'/'QrOnly'/'ButtonOnly'), defaulting to
/// 'Both' before the first successful /auth/me — matching the same "no answer means allow"
/// asymmetry the rest of this file's entitlement reads already use.
final effectiveClockInMethodProvider = Provider<String>((ref) {
  final cached = ref.watch(cachedEntitlementProvider).valueOrNull;
  return cached?.clockInMethod ?? 'Both';
});

/// Whether today is an approved smart-working day for the signed-in technician.
///
/// null = unknown (never refreshed, the process restarted, nobody is signed in, or the last answer
/// belongs to a different user). Callers must fail OPEN on null: unknown must neither hide the punch
/// button nor claim an approved day.
///
/// The identity gate — not merely the presence of a user — is load-bearing. The flag is
/// memory-only, so it survives a sign-out (a cold start is the only thing that clears it), and this
/// device can be a shared van/tablet where the next person belongs to another tenant
/// (`SessionEnder`'s own class comment). Someone being signed in therefore proves nothing about
/// whose answer is in hand; the repository records the session that answered and hands it back only
/// to that same user, so this read is correct by construction, not by invalidating from outside.
final smartWorkingTodayProvider = Provider<bool?>((ref) {
  final signedIn = ref.watch(authStateProvider).valueOrNull;
  if (signedIn == null) return null;
  return ref.watch(entitlementRepositoryProvider).smartWorkingTodayFor(signedIn.id);
});

/// Fetches `/auth/me`'s entitlement answer now, and invalidates the cache-reading providers only
/// on a real change — a failed refresh must not churn the UI into re-reading a cache that did not
/// move.
///
/// Called by [initEntitlementRefreshWatcher] (app start + reconnect) and by HomeShell on every app
/// resume: a tenant that changed this user's timbratura mode, seat type or modules while the app sat
/// backgrounded is exactly the change nothing used to pick up — reconnect never fires on a device
/// that never lost its network interface, so the answer stayed at whatever it was at launch.
Future<void> refreshEntitlements(WidgetRef ref) async {
  final updated = await ref.read(entitlementServiceProvider).refresh();
  if (updated) {
    ref.invalidate(cachedEntitlementProvider);
    ref.invalidate(hasFeatureProvider);
    // Not backed by a FutureProvider, so nothing else would rebuild a reader after the refresh.
    ref.invalidate(smartWorkingTodayProvider);
  }
}

/// Call once on app start, alongside initAuthReconnectWatcher.
///
/// Fetches immediately as well as on every reconnect. Reconnect alone was not enough and the
/// omission was invisible: a device that is online at launch and never drops signal never
/// reconnects, so it never fetched, so the cache stayed null and every screen reading it fell back
/// to the field-seat baseline forever. An office user on good wifi would have been the *worst*
/// served by a watcher that only listens for the network coming back.
///
/// Returns the cancel function to invoke from the caller's `dispose()` — without it, a widget
/// remount (e.g. forced sign-out → re-login) leaves the old closure's `ref` in the listener list
/// forever, and the next reconnect throws on that stale entry.
VoidCallback initEntitlementRefreshWatcher(WidgetRef ref) {
  refreshEntitlements(ref);
  return ref.read(connectivityProvider.notifier).onReconnect(() => refreshEntitlements(ref));
}
