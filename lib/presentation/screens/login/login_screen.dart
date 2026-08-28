import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_vetro_palette.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../providers/auth_providers.dart';
import '../../../domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Login screen — native username/password sign-in.
///
/// Credentials are entered in-app and submitted directly via
/// [LoginNotifier.signInWithPassword]. If the account needs more than a
/// password (MFA, passkey, …), the notifier automatically falls back to the
/// system-browser OIDC flow ([LoginNotifier.signIn]) — the same flow used by
/// the "Password dimenticata?" link. On success [authStateProvider] emits a
/// non-null user and go_router's refresh redirect sends the user into the app.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    ref.read(loginProvider.notifier).clearError();
    await ref.read(loginProvider.notifier).signInWithPassword(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
    );
    // Router redirect handles navigation on success.
    if (ref.read(loginProvider).failure == null) {
      // Tells the platform autofill service (password manager) the credentials just used were
      // valid, so it can offer to save them — must only fire on success, never on a failed
      // attempt.
      TextInput.finishAutofillContext();
    }
  }

  Future<void> _onForgotPassword() async {
    ref.read(loginProvider.notifier).clearError();
    // Zitadel's own hosted page has its own password-reset link — no need to build one here.
    await ref.read(loginProvider.notifier).signIn();
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
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            // No nav clearance here: login is the one screen outside the shell.
            AppSpacing.pagePadding,
          ),
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
                'Inserisci le tue credenziali TaskTap.',
                style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── Error banner ─────────────────────────────────────────────
              if (failure != null) ...[
                _ErrorBanner(message: authFailureMessage(failure)),
                const SizedBox(height: AppSpacing.base),
              ],

              // ── Form fields ──────────────────────────────────────────────
              // AutofillGroup ties the two fields together so the platform password manager
              // treats them as one credential pair (username + password), matching the fill/save
              // behavior the old browser-based OIDC flow got for free.
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      key: const ValueKey('login-username'),
                      controller: _usernameCtrl,
                      label: 'Email o nome utente',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: AppSpacing.base),
                    AppTextField(
                      key: const ValueKey('login-password'),
                      controller: _passwordCtrl,
                      label: 'Password',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: isLoading ? null : _onLogin,
                      autofillHints: const [AutofillHints.password],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading ? null : _onForgotPassword,
                  child: const Text('Password dimenticata?'),
                ),
              ),

              // ── Browser fallback (unexpected errors only) ───────────────
              // A wrong-password error just lets the technician retry the same form — no browser
              // detour needed. Anything else unexpected (network hiccup, backend error, …) gets a
              // manual way out via the same browser-based flow "Password dimenticata?" uses.
              if (failure != null && failure is! InvalidCredentials) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isLoading ? null : _onForgotPassword,
                    child: const Text('Accedi con il browser'),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.base),

              // ── CTA ──────────────────────────────────────────────────────
              VetroButton(
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

/// Inline TaskTap logo — accent pill with wordmark.
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppVetroColors.tint, AppVetroColors.tintStrong],
            ),
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
