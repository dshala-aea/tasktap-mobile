import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../providers/auth_providers.dart';

/// User profile screen — shows user info and logout action.
class ProfiloScreen extends ConsumerWidget {
  const ProfiloScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final loginNotifier = ref.read(loginProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Profilo', style: AppTextStyles.titleLarge),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── User card ────────────────────────────────────────────────
            if (user != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.brand,
                      child: Text(
                        _initials(user.displayName ?? user.email),
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.onBrand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),

                    if (user.displayName != null) ...[
                      Text(
                        user.displayName!,
                        style: AppTextStyles.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],

                    Text(
                      user.email,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],

            const Spacer(),

            // ── Logout ───────────────────────────────────────────────────
            AppButton.danger(
              label: 'Disconnetti',
              icon: const Icon(Icons.logout, size: 18),
              onPressed: () async {
                final confirmed = await _confirmLogout(context);
                if (confirmed) {
                  await loginNotifier.signOut();
                  // Router redirect to /login happens automatically via
                  // authStateProvider stream.
                }
              },
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  String _initials(String nameOrEmail) {
    final parts = nameOrEmail.split(RegExp(r'[\s@]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnetti'),
        content: const Text(
          'Sei sicuro di voler uscire dall\'account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('Disconnetti'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
