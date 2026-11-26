import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../providers/auth_providers.dart';
import '../../../domain/auth/auth_failure.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

import 'access_request_sheet.dart';

/// Login screen — one button, the system browser.
///
/// Sign-in happens at the identity service ([LoginNotifier.signIn]: browser sheet, authorization
/// code + PKCE); the app never shows a password or passkey field of its own. On success
/// [authStateProvider] emits a non-null user and go_router's refresh redirect sends the user into
/// the app. A cancelled, offline or failed attempt only shows a calm message: a stored session and
/// any unsent work are never touched from here.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  /// Calm outcomes (the user closed the browser, no signal) read as a hint, not as an error.
  static bool _isCalm(AuthFailure failure) =>
      failure is SignInCancelled || failure is NetworkError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              // Long-press is the only way in to kiosk activation (see KioskActivationScreen's
              // own doc comment for why this is deliberately unadvertised) — an ordinary
              // technician signing in never has a reason to hold their finger on the logo.
              // Bare GestureDetector, not AppTappable — an InkWell ripple would visibly hint
              // the logo is interactive, defeating the point (see
              // tappable_convention_test.dart's `allowed` entry for this file).
              GestureDetector(
                onLongPress: () => context.push(AppRoutes.kioskActivate),
                child: const _TaskTapLogo(),
              ),

              const SizedBox(height: AppSpacing.xxxl),

              Text('Accedi', style: AppTextStyles.headlineLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Si apre il browser per accedere in modo sicuro con il tuo account. '
                'Puoi usare la password o la passkey.',
                style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
              ),

              const SizedBox(height: AppSpacing.xxl),

              if (failure != null) ...[
                InlineAlert(
                  message: authFailureMessage(failure),
                  icon: LucideIcons.alertCircle,
                  color: _isCalm(failure) ? context.colors.amber : null,
                ),
                const SizedBox(height: AppSpacing.base),
              ],

              AppButton(
                label: 'Accedi',
                size: AppButtonSize.lg,
                isLoading: isLoading,
                onPressed: isLoading
                    ? null
                    : () {
                        ref.read(loginProvider.notifier).clearError();
                        unawaited(ref.read(loginProvider.notifier).signIn());
                      },
              ),

              const SizedBox(height: AppSpacing.base),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
                  onPressed: isLoading ? null : () => unawaited(showAccessRequestSheet(context)),
                  child: const Text('Richiedi accesso'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline TaskTap logo — accent pill with wordmark.
class _TaskTapLogo extends StatelessWidget {
  const _TaskTapLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Text(
            'TT',
            style: AppTextStyles.titleLarge.copyWith(
              color: Colors.white,
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
