import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/security/passkey_support.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/auth/account_methods_api_client.dart';
import '../../providers/auth_providers.dart';
import '../../../domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'access_request_sheet.dart';

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

  /// Which half of the flow is on screen. The email is asked first because both backends need
  /// it before anything can happen — the password BFF takes it with the password, and the
  /// ZITADEL session behind the passkey path needs a user to challenge.
  _LoginStep _step = _LoginStep.email;

  /// Whether "Continua" is asking the backend which methods the account has. The method step is
  /// not shown until the answer (or the fallback) is in hand.
  bool _isCheckingMethods = false;

  /// The account's methods once known. Null while the check is in flight;
  /// [AccountMethods.fallback] (both true) when it failed, so a broken check never hides a way in.
  AccountMethods? _methods;

  /// Last email used on this device, so the first step is not retyped every time. A plain
  /// preference — never a token; the value only prefills an editable field.
  static const _lastEmailKey = 'login.last_email';

  @override
  void initState() {
    super.initState();
    unawaited(_prefillLastEmail());
  }

  Future<void> _prefillLastEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_lastEmailKey);
      // Only fill an empty field on the first step: a late-resolving preference must not
      // overwrite what the technician already typed, nor the email shown on the method step.
      if (email != null &&
          email.isNotEmpty &&
          mounted &&
          _step == _LoginStep.email &&
          _usernameCtrl.text.isEmpty) {
        _usernameCtrl.text = email;
      }
    } catch (_) {
      // A preference that cannot be read is not worth blocking sign-in over.
    }
  }

  Future<void> _rememberEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastEmailKey, _usernameCtrl.text.trim());
    } catch (_) {
      // Same: the convenience of a prefill must never fail a sign-in.
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// A deliberately loose shape check: the invite flow creates the account with the email as
  /// the ZITADEL login name, so a non-address can never authenticate. It only gates the button;
  /// the server stays the authority on whether the account exists.
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool _looksLikeEmail(String value) => _emailShape.hasMatch(value.trim());

  Future<void> _onContinue() async {
    if (_isCheckingMethods || !_looksLikeEmail(_usernameCtrl.text)) return;
    final email = _usernameCtrl.text.trim();
    ref.read(loginProvider.notifier).clearError();
    setState(() {
      _isCheckingMethods = true;
      _methods = null;
    });

    AccountMethods methods;
    try {
      methods = await ref.read(accountMethodsApiClientProvider).fetch(email);
    } catch (_) {
      // Network error, timeout or a 5xx: the check must never block sign-in. Fall back to the
      // pre-endpoint behaviour — every method the device can actually use.
      methods = AccountMethods.fallback;
    }

    if (!mounted) return;
    setState(() {
      _isCheckingMethods = false;
      _methods = methods;
      _step = _LoginStep.method;
    });
  }

  void _onChangeEmail() {
    ref.read(loginProvider.notifier).clearError();
    setState(() {
      _step = _LoginStep.email;
      _methods = null;
    });
  }

  Future<void> _onLogin() async {
    ref.read(loginProvider.notifier).clearError();
    await ref
        .read(loginProvider.notifier)
        .signInWithPassword(_usernameCtrl.text.trim(), _passwordCtrl.text);
    // Router redirect handles navigation on success.
    if (ref.read(loginProvider).failure == null) {
      // Tells the platform autofill service (password manager) the credentials just used were
      // valid, so it can offer to save them — must only fire on success, never on a failed
      // attempt.
      TextInput.finishAutofillContext();
      await _rememberEmail();
    }
  }

  Future<void> _onPasskey() async {
    // Guard inside the callback as well as on the button: two taps can land before the rebuild
    // that removes the button, and a second attempt would open a second native sheet.
    if (ref.read(loginProvider).isLoading) return;
    ref.read(loginProvider.notifier).clearError();
    await ref.read(loginProvider.notifier).signInWithPasskey(_usernameCtrl.text.trim());
    if (ref.read(loginProvider).failure == null) {
      await _rememberEmail();
    }
    // Deliberately no TextInput.finishAutofillContext() here: the passkey path is not a
    // username/password fill, so there is nothing for the password manager to save.
  }

  Future<void> _onForgotPassword() async {
    ref.read(loginProvider.notifier).clearError();
    // Zitadel's own hosted page has its own password-reset link — no need to build one here.
    await ref.read(loginProvider.notifier).signIn();
  }

  void _onRequestAccess() {
    unawaited(showAccessRequestSheet(context, initialEmail: _usernameCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginProvider);
    final isLoading = loginState.isLoading;
    final failure = loginState.failure;
    // Fails closed while the gate is loading or errored, so the password path is the only offer.
    final passkeySupported = ref.watch(passkeySupportedProvider).valueOrNull ?? false;

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
          // One group across both steps: the email and the password stay one credential pair
          // for the platform password manager even though they are asked on separate screens.
          child: AutofillGroup(
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
                  _step == _LoginStep.email
                      ? (_isCheckingMethods
                            ? 'Verifico come accedere…'
                            : 'Inserisci la tua email per continuare.')
                      : 'Scegli come accedere.',
                  style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
                ),

                const SizedBox(height: AppSpacing.xxl),

                if (_step == _LoginStep.email)
                  ..._emailStep()
                else
                  ..._methodStep(isLoading, failure, passkeySupported),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep() {
    return [
      AppTextField(
        key: const ValueKey('login-username'),
        controller: _usernameCtrl,
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username],
        readOnly: _isCheckingMethods,
        onEditingComplete: _onContinue,
      ),
      const SizedBox(height: AppSpacing.base),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _usernameCtrl,
        builder: (context, value, _) => AppButton(
          label: 'Continua',
          isLoading: _isCheckingMethods,
          onPressed: _looksLikeEmail(value.text) && !_isCheckingMethods ? _onContinue : null,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Center(
        child: TextButton(onPressed: _onRequestAccess, child: const Text('Richiedi accesso')),
      ),
    ];
  }

  List<Widget> _methodStep(bool isLoading, AuthFailure? failure, bool passkeySupported) {
    final methods = _methods ?? AccountMethods.fallback;
    final hasPassword = methods.hasPassword;
    final hasPasskey = methods.hasPasskey;
    final accountUnknown = !hasPassword && !hasPasskey;
    final passkeyOnlyUnsupported = hasPasskey && !hasPassword && !passkeySupported;

    return [
      // The email stays visible (and inside the AutofillGroup) so the pair reads as one
      // credential; "Cambia" is the way back to editing it.
      AppTextField(
        key: const ValueKey('login-username'),
        controller: _usernameCtrl,
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.username],
        readOnly: true,
        suffixIcon: TextButton(
          onPressed: isLoading ? null : _onChangeEmail,
          child: const Text('Cambia'),
        ),
      ),
      const SizedBox(height: AppSpacing.base),
      if (accountUnknown) ...[
        InlineAlert(
          message: 'Account non trovato. Controlla l\'email o richiedi accesso.',
          icon: LucideIcons.alertCircle,
        ),
      ] else if (passkeyOnlyUnsupported) ...[
        InlineAlert(
          message: 'Questo account usa una passkey, ma questo dispositivo non la supporta.',
          icon: LucideIcons.alertCircle,
        ),
      ] else ...[
        if (hasPassword) ...[
          AppTextField(
            key: const ValueKey('login-password'),
            controller: _passwordCtrl,
            label: 'Password',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onEditingComplete: isLoading ? null : _onLogin,
            autofillHints: const [AutofillHints.password],
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        if (failure != null) ...[
          InlineAlert(message: authFailureMessage(failure), icon: LucideIcons.alertCircle),
          const SizedBox(height: AppSpacing.base),
        ],
        if (failure != null && failure is! InvalidCredentials) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : _onForgotPassword,
              child: const Text('Accedi con il browser'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (hasPassword) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : _onForgotPassword,
              child: const Text('Password dimenticata?'),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          AppButton(label: 'Accedi', onPressed: isLoading ? null : _onLogin, isLoading: isLoading),
        ],
        if (hasPasskey && passkeySupported && !isLoading) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: _onPasskey, child: const Text('Accedi con passkey')),
        ],
      ],
      const SizedBox(height: AppSpacing.base),
      Center(
        child: TextButton(
          onPressed: isLoading ? null : _onRequestAccess,
          child: const Text('Richiedi accesso'),
        ),
      ),
    ];
  }
}

enum _LoginStep { email, method }

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
            color: AppColors.Y,
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
