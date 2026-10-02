import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'business_time.dart';

/// SharedPreferences key holding the last known tenant IANA zone id.
const tenantTimeZonePrefsKey = 'tenant_time_zone';

/// Persists the tenant zone. Every access is guarded: a prefs failure reads as
/// "nothing cached" and writes are dropped.
class BusinessZoneStore {
  Future<String?> readCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(tenantTimeZonePrefsKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String zoneId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tenantTimeZonePrefsKey, zoneId);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(tenantTimeZonePrefsKey);
    } catch (_) {}
  }
}

final businessZoneStoreProvider = Provider<BusinessZoneStore>(
  (_) => BusinessZoneStore(),
);

/// Current tenant business zone id. Starts as Rome, hydrates lazily from the
/// store, and never reads a boot-time override, so a rebuild or [reset] cannot
/// resurrect a stale value.
class BusinessZoneIdNotifier extends Notifier<String> {
  int _epoch = 0;
  Future<void>? _hydration;

  BusinessZoneStore get _store => ref.read(businessZoneStoreProvider);

  @override
  String build() {
    // Riverpod 2.x has no `ref.mounted`: invalidate in-flight hydration instead.
    ref.onDispose(() => _epoch++);
    _hydration = _hydrate();
    return kDefaultBusinessZoneId;
  }

  Future<void> _hydrate() async {
    final epoch = _epoch;
    final cached = await _store.readCached();
    if (epoch != _epoch) return;
    state = resolveBusinessZoneId(cached);
  }

  @visibleForTesting
  Future<void> hydrateForTest() => _hydration ?? Future<void>.value();

  /// Adopts [zoneId] when it is a known IANA id; null, empty and unknown ids
  /// keep the current value.
  Future<void> set(String? zoneId) async {
    if (zoneId == null || zoneId.trim().isEmpty) return;
    if (resolveBusinessZoneId(zoneId) != zoneId) return;
    _epoch++;
    state = zoneId;
    await _store.write(zoneId);
  }

  /// Back to Rome and forget the persisted value (sign-out).
  Future<void> reset() async {
    _epoch++;
    state = kDefaultBusinessZoneId;
    await _store.clear();
  }
}

final businessZoneIdProvider = NotifierProvider<BusinessZoneIdNotifier, String>(
  BusinessZoneIdNotifier.new,
);

final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final businessTimeProvider = Provider<BusinessTime>(
  (ref) => BusinessTime(
    ref.watch(businessZoneIdProvider),
    clock: ref.watch(clockProvider),
  ),
);
