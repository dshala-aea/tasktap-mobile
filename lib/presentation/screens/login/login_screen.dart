import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../providers/auth_providers.dart';
import '../../../domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Login screen — Zitadel OIDC sign-in.
///
/// Credentials are entered in the system browser (Authorization Code + PKCE),
/// so this screen is just branding + a single "Accedi" button that launches the
/// flow. On success [authStateProvider] emits a non-null user and go_router's
/// refresh redirect sends the user into the app.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  Future<void> _onLogin() async {
    ref.read(loginProvider.notifier).clearError();
    await ref.read(loginProvider.notifier).signIn();
    // Router redirect handles navigation on success.
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginProvider);
    final isLoading = loginState.isLoading;
    final failure = loginState.failure;

    return Scaffold(
      backgroundColor: context.colors.bg1,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxxl),

              // ── Logo / wordmark ──────────────────────────────────────────
              const _TaskTapLogo(),

              const SizedBox(height: AppSpacing.xxxl),

              // ── Heading ──────────────────────────────────────────────────
              Text('Accedi', style: AppTextStyles.headlineLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Verrai reindirizzato all\'accesso sicuro TaskTap.',
                style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── Error banner ─────────────────────────────────────────────
              if (failure != null) ...[
                _ErrorBanner(message: authFailureMessage(failure)),
                const SizedBox(height: AppSpacing.base),
              ],

              // ── CTA ──────────────────────────────────────────────────────
              AppButton(
                label: 'Accedi',
                onPressed: isLoading ? null : _onLogin,
                isLoading: isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline TaskTap logo — yellow pill with wordmark.
class _TaskTapLogo extends StatelessWidget {
  const _TaskTapLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Text(
            'TT',
            style: AppTextStyles.titleLarge.copyWith(
              color: context.colors.brandOn,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text('TaskTap', style: AppTextStyles.headlineMedium),
      ],
    );
  }
}

/// Red error banner shown when auth fails.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.red.withAlpha(20),
        border: Border.all(color: context.colors.red.withAlpha(80)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertCircle, color: context.colors.red, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: context.colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
