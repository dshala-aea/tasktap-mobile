// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entitlements/entitlement_providers.dart';
import '../../data/entitlements/entitlement_repository.dart';

/// What a route needs to be reachable — checked centrally in [buildRouter]'s `redirect`
/// callback, the same place kiosk-mode and auth are already checked, rather than per-screen.
///
/// A page a technician shouldn't reach must never simply render because nothing besides a
/// hidden tile kept them off it — that's the class of bug this closes (already fixed server-side
/// and on web; see the access-control-scoping plan). [buildRouter] matches a visited path against
/// a table of these and redirects to [AppRoutes.forbidden] when one is not satisfied.
sealed class RouteRequirement {
  const RouteRequirement();

  /// Satisfied when the cached entitlement offers module [moduleKey] — see [moduleIsOffered] for
  /// the exact rule (always-on modules, and the field-seat baseline before the first sync ever
  /// completes).
  const factory RouteRequirement.module(String moduleKey) = _ModuleRequirement;

  /// Satisfied when the cached entitlement holds the finer-grained `module.resource.action`
  /// capability [key]. Unlike [module], nothing cached means denied — there is no safe baseline
  /// to guess a specific action from (mirrors [EntitlementRepository.hasCapability]).
  const factory RouteRequirement.capability(String key) = _CapabilityRequirement;

  /// null = not yet known (the entitlement cache is still loading, e.g. cold start) — the caller
  /// must NOT redirect in this case, matching the existing `kioskState.loading`/
  /// `authAsync.loading` "stay put" treatment already in `buildRouter`'s `redirect`.
  bool? isSatisfied(WidgetRef ref);
}

class _ModuleRequirement extends RouteRequirement {
  const _ModuleRequirement(this.moduleKey);
  final String moduleKey;

  @override
  bool? isSatisfied(WidgetRef ref) {
    final cached = ref.read(cachedEntitlementProvider);
    return cached.when(
      data: (entitlement) => moduleIsOffered(moduleKey, entitlement),
      loading: () => null,
      error: (_, _) => null,
    );
  }
}

class _CapabilityRequirement extends RouteRequirement {
  const _CapabilityRequirement(this.key);
  final String key;

  @override
  bool? isSatisfied(WidgetRef ref) {
    final cached = ref.read(cachedEntitlementProvider);
    return cached.when(
      data: (entitlement) => entitlement?.capabilities.contains(key) ?? false,
      loading: () => null,
      error: (_, _) => null,
    );
  }
}
