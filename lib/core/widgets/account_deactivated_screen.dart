// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Shown in place of every screen — not a banner above content, the way [SuspendedBanner] is —
/// because a deactivated user is a different failure shape entirely: TenantMiddleware cannot
/// resolve a tenant for them at all, so reads fail too, not just writes. There is nothing behind
/// this screen worth showing; every request would 400 the same way.
///
/// Only ever rendered when [EntitlementRepository]'s cache has a positively confirmed
/// `isAccountDeactivated` — never on a guess, never on a generic network failure (see
/// `EntitlementService.refresh`'s own doc comment for the exact, narrow condition that sets it).
class AccountDeactivatedScreen extends StatelessWidget {
  const AccountDeactivatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.userMinus, size: 48, color: context.colors.red),
                const SizedBox(height: AppSpacing.base),
                const Text(
                  'Account disattivato',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Il tuo account è stato disattivato da un amministratore. '
                  'Contatta il tuo amministratore per riattivarlo.',
                  style: TextStyle(fontSize: 14, color: context.colors.inkMuted, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
