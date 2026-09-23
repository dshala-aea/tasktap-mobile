// dart format width=100
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entitlements/entitlement_providers.dart';

/// Hides [child] unless the cached entitlement holds [capability] — the Flutter equivalent of the
/// web's `<Can>`. Fail-closed, matching [EntitlementRepository.hasCapability]'s own rule: nothing
/// cached, or the cache still loading, hides the child. Hide-only by design (no alert-on-tap
/// variant) — a denied action simply doesn't render.
class CapabilityGate extends ConsumerWidget {
  const CapabilityGate({super.key, required this.capability, required this.child});

  final String capability;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlement = ref.watch(cachedEntitlementProvider).value;
    if (entitlement == null || !entitlement.capabilities.contains(capability)) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
