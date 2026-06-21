import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';

/// Placeholder login screen.
///
/// Auth implementation is in M2. This screen holds the branded shell
/// and navigation seam so routing works end-to-end in M1.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      // M2: replace with Supabase auth call.
      context.go(AppRoutes.oggi);
    }
  }

  @override
  Widget build(BuildContext context) {
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

                // ── Logo / wordmark ─────────────────────────────────────
                _TaskTapLogo(),

                const SizedBox(height: AppSpacing.xxxl),

                // ── Heading ─────────────────────────────────────────────
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

                // ── Email ────────────────────────────────────────────────
                AppTextField(
                  label: 'Email',
                  hint: 'nome@azienda.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Inserisci l\'email';
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.base),

                // ── Password ─────────────────────────────────────────────
                AppTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Inserisci la password';
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── CTA ──────────────────────────────────────────────────
                AppButton(
                  label: 'Accedi',
                  onPressed: _onLogin,
                ),

                const SizedBox(height: AppSpacing.base),

                // ── Forgot password seam ─────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: () {
                      // M2: password reset flow.
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
