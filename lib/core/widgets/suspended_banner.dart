// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../data/entitlements/entitlement_providers.dart';

/// Shown once, in [HomeShell], above every screen — never buried in a single tab. The backend
/// keeps reads working during suspension (EntitlementMiddleware only gates writes), so this is
/// informational, not a lockout screen: it exists so a technician sees *why* saving a rapportino
/// or clocking in silently fails instead of just hitting an unexplained error mid-shift.
class SuspendedBanner extends ConsumerWidget {
  const SuspendedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlement = ref.watch(cachedEntitlementProvider).value;
    if (entitlement == null || !entitlement.isSuspended) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      // Fixed danger red, same as offline_guard's SnackBar — the one danger red does not flip
      // with theme, so the white text pairing below is safe under both.
      color: context.colors.red,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(LucideIcons.alertTriangle, size: 16, color: AppColors.WHITE),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Abbonamento non attivo. I dati sono consultabili, ma non è possibile salvare o '
              'modificare finché non viene riattivato.',
              style: const TextStyle(color: AppColors.WHITE, fontSize: 12, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
