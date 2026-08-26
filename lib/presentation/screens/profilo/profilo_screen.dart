import 'package:flutter/material.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_vetro_palette.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../providers/auth_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// User profile screen — shows user info and logout action.
class ProfiloScreen extends ConsumerWidget {
  const ProfiloScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final loginNotifier = ref.read(loginProvider.notifier);

    return Scaffold(
      backgroundColor: context.colors.bg1,
      appBar: ScreenHeaderBar(title: 'Profilo', showBack: true),
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
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.borderMedium),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: context.vetro.tint,
                      child: Text(
                        _initials(user.displayName ?? user.email),
                        style: AppTextStyles.titleLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),

                    if (user.displayName != null) ...[
                      Text(user.displayName!, style: AppTextStyles.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                    ],

                    Text(
                      user.email,
                      style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],

            const Spacer(),

            // ── Logout ───────────────────────────────────────────────────
            VetroButton(
              label: 'Disconnetti',
              icon: const Icon(LucideIcons.logOut, size: 18),
              gradientColors: const [AppColors.stopLight, AppColors.stopDark],
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
        content: const Text('Sei sicuro di voler uscire dall\'account?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.red),
            child: const Text('Disconnetti'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
