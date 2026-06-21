import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../providers/auth_providers.dart';
import '../../../domain/auth/auth_failure.dart';

/// Login screen — email / password sign-in via Supabase.
///
/// Features:
/// - Branded TaskTap design (yellow, Sora / Manrope typography)
/// - Email + password validation (client-side before network call)
/// - Friendly Italian error messages for every [AuthFailure] type
/// - Loading state disables form + shows spinner in CTA
/// - "Ricordami" checkbox (on by default — session persists across restarts)
/// - Password-reset seam (tap → future M implementation)
///
/// On success the [authStateProvider] stream emits a non-null user and
/// go_router's refresh redirect automatically sends the user to /oggi.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    // Clear any previous error first.
    ref.read(loginProvider.notifier).clearError();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(loginProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    // Router redirect handles navigation on success.
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginProvider);
    final isLoading = loginState.isLoading;
    final failure = loginState.failure;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxxl),

                // ── Logo / wordmark ──────────────────────────────────────
                const _TaskTapLogo(),

                const SizedBox(height: AppSpacing.xxxl),

                // ── Heading ──────────────────────────────────────────────
                Text(
                  'Accedi',
                  style: AppTextStyles.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Inserisci le tue credenziali per continuare.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),

                // ── Error banner ─────────────────────────────────────────
                if (failure != null) ...[
                  _ErrorBanner(message: authFailureMessage(failure)),
                  const SizedBox(height: AppSpacing.base),
                ],

                // ── Email ─────────────────────────────────────────────────
                AppTextField(
                  label: 'Email',
                  hint: 'nome@azienda.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  enabled: !isLoading,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Inserisci l\'email';
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                        .hasMatch(v.trim())) {
                      return 'Inserisci un\'email valida';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.base),

                // ── Password ──────────────────────────────────────────────
                AppTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  enabled: !isLoading,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Inserisci la password';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.sm),

                // ── Remember me ──────────────────────────────────────────
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      activeColor: AppColors.brand,
                      checkColor: AppColors.onBrand,
                      onChanged: isLoading
                          ? null
                          : (v) => setState(() => _rememberMe = v ?? true),
                    ),
                    Text(
                      'Ricordami',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── CTA ──────────────────────────────────────────────────
                AppButton(
                  label: 'Accedi',
                  onPressed: isLoading ? null : _onLogin,
                  isLoading: isLoading,
                ),

                const SizedBox(height: AppSpacing.base),

                // ── Forgot password seam ──────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            // Future: password reset flow.
                          },
                    child: Text(
                      'Password dimenticata?',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Text(
            'TT',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onBrand,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'TaskTap',
          style: AppTextStyles.headlineMedium,
        ),
      ],
    );
  }
}

/// Red error banner shown above the form when auth fails.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(20),
        border: Border.all(color: AppColors.error.withAlpha(80)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
