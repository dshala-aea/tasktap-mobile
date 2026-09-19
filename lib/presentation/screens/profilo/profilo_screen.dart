import 'package:flutter/material.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
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
      // A `Spacer()`-based fixed Column (no scroll) overflows the moment a long display name
      // wraps to 2 lines or the viewport is short (small phone, split-screen, large system font)
      // — every other detail screen in the app scrolls; this one didn't. The card now scrolls on
      // its own and the logout button stays pinned below it via Expanded, instead of `Spacer`
      // requiring the whole Column to fit exactly.
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── User card ────────────────────────────────────────────────
                  if (user != null)
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: AppColors.Y,
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
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: context.colors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Logout ───────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              context.navClearance,
            ),
            child: AppButton.danger(
              label: 'Disconnetti',
              icon: const Icon(LucideIcons.logOut, size: 18),
              onPressed: () async {
                final confirmed = await _confirmLogout(context);
                if (confirmed) {
                  await loginNotifier.signOut();
                  // Router redirect to /login happens automatically via
                  // authStateProvider stream.
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String nameOrEmail) {
    final parts = nameOrEmail.split(RegExp(r'[\s@]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<bool> _confirmLogout(BuildContext context) => confirmDeleteDialog(
    context,
    title: 'Disconnetti',
    message: 'Sei sicuro di voler uscire dall\'account?',
    confirmLabel: 'Disconnetti',
  );
}
