// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_tappable.dart';
import '../../core/widgets/permission_purpose_card.dart';

/// Outcome of checking or requesting one permission, coarse enough to drive one shared UI for
/// every onboarding permission step regardless of which platform API backs it.
enum PermissionStepStatus {
  /// Not yet asked, or asked and still allowed to ask again.
  notDetermined,
  granted,

  /// The OS won't show its own dialog again — only Settings can change this now.
  deniedForever,

  /// This device/build can't honour the permission at all (e.g. no biometrics enrolled, Firebase
  /// unavailable) — no dialog to offer, real or otherwise.
  unavailable,
}

/// One page of the onboarding flow: explains a permission, then requests it.
///
/// Deliberately knows nothing about which permission it's for — [checkStatus] and [request] are
/// the only two places platform-specific logic enters, each supplied by the concrete step in
/// `onboarding_screen.dart`. This is what lets Location/Notifiche/Fotocamera e microfono/Blocco
/// biometrico share one implementation instead of four near-identical ones.
class PermissionStepPage extends StatefulWidget {
  const PermissionStepPage({
    super.key,
    required this.icon,
    required this.titolo,
    required this.motivo,
    required this.senzaDiEsso,
    required this.ctaLabel,
    required this.checkStatus,
    required this.request,
    required this.onDone,
    this.onOpenSettings,
    this.requiresSystemDialog = false,
  });

  final IconData icon;
  final String titolo;
  final String motivo;
  final String senzaDiEsso;

  /// Label for the primary action when the answer is still undecided — e.g. "Consenti la
  /// posizione". Not used once the state is [PermissionStepStatus.deniedForever] (the button
  /// becomes "Apri impostazioni" instead) or [PermissionStepStatus.granted]/[PermissionStepStatus.unavailable]
  /// (no primary button at all).
  final String ctaLabel;

  /// Read-only: must not itself trigger an OS dialog. Called once when the page first builds.
  final Future<PermissionStepStatus> Function() checkStatus;

  /// May trigger the real OS dialog. Called when the primary button is tapped.
  final Future<PermissionStepStatus> Function() request;

  /// Called when this step's decision is final — a skip ("Non ora"), a granted/unavailable state
  /// the technician has acknowledged, or (via the auto-advance below) shortly after granting.
  final VoidCallback onDone;

  /// Opens the OS's app-settings page, when the permission is permanently denied. Defaults to
  /// [onDone] (treat "open settings" the same as "move on") for a step where opening settings
  /// isn't meaningful — none of onboarding's four steps take that default; each supplies a real
  /// settings-opening callback.
  final VoidCallback? onOpenSettings;

  /// When true, this step's ask is the real system dialog and nothing else: it is fired as soon
  /// as the purpose card is on screen, and there is no app-drawn "Consenti / Non ora" for the
  /// technician to answer instead.
  ///
  /// This is an App Store rule, not a preference. Consent has to come from the system dialog; an
  /// app-crafted allow/deny pair that stands in for it is a 5.1.1 rejection risk (it mimics a
  /// system permission dialog) and the OS never sees the answer, so what the app records is a
  /// local preference dressed up as consent. Notifications are where this bites hardest: on iOS a
  /// recorded "Non ora" costs the technician the one system dialog they will ever be shown, and
  /// nothing in the app can give it back to them.
  ///
  /// Set by the three OS-permission steps — Location, Notifiche, Fotocamera e microfono. Not by
  /// Blocco biometrico, which is an app setting with no OS consent dialog behind it, so its
  /// Consenti/Non ora is a real choice about a feature rather than a stand-in for system consent.
  final bool requiresSystemDialog;

  @override
  State<PermissionStepPage> createState() => _PermissionStepPageState();
}

enum _Ui { loading, ask, granted, deniedForever, unavailable }

class _PermissionStepPageState extends State<PermissionStepPage> with WidgetsBindingObserver {
  _Ui _ui = _Ui.loading;
  bool _busy = false;
  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  /// Coming back from the system settings page this step just sent the technician to is the one
  /// moment the answer can change without this page asking for it. Without the re-check the page
  /// kept saying "Apri impostazioni" over a permission that was already granted, and the
  /// technician had to leave via "Continua" to find out it had worked — the opposite of the
  /// "open the system settings" escape this step offers.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ui == _Ui.deniedForever) _load();
  }

  Future<void> _load() async {
    final status = await widget.checkStatus();
    if (!mounted) return;
    setState(() => _ui = _uiFor(status));
    if (_ui == _Ui.granted) {
      _scheduleAutoAdvance();
      return;
    }
    // The system dialog is the prompt: fire it as soon as the purpose card is on screen, so the
    // technician is never asked to answer a consent screen of the app's own making.
    if (_ui == _Ui.ask && widget.requiresSystemDialog) unawaited(_consenti());
  }

  _Ui _uiFor(PermissionStepStatus status) => switch (status) {
    PermissionStepStatus.granted => _Ui.granted,
    PermissionStepStatus.deniedForever => _Ui.deniedForever,
    PermissionStepStatus.unavailable => _Ui.unavailable,
    PermissionStepStatus.notDetermined => _Ui.ask,
  };

  void _scheduleAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _ui == _Ui.granted) widget.onDone();
    });
  }

  Future<void> _consenti() async {
    if (_busy) return;
    setState(() => _busy = true);
    final PermissionStepStatus status;
    try {
      status = await widget.request();
    } catch (_) {
      // A platform call that throws — Firebase misconfigured after init, a channel error — is not
      // an answer. Leaving `_busy` set would strand the page on a spinner with no way forward,
      // which on a [PermissionStepPage.requiresSystemDialog] step (no skip at all) traps the
      // technician inside onboarding. Report it as "this device can't ask right now", the state
      // that always carries a continue.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ui = _Ui.unavailable;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ui = _uiFor(status);
    });
    if (_ui == _Ui.granted) _scheduleAutoAdvance();
  }

  /// Label for the secondary action. On a [PermissionStepPage.requiresSystemDialog] step it is a
  /// plain "Continua": it only ever appears after the OS has already answered, and it must not
  /// read as an app-authored "Non ora" that the app could mistake for a decision of its own.
  String get _continueLabel => widget.requiresSystemDialog ? 'Continua' : 'Non ora';

  @override
  Widget build(BuildContext context) {
    if (_ui == _Ui.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PermissionPurposeCard(
            icon: widget.icon,
            titolo: widget.titolo,
            motivo: widget.motivo,
            senzaDiEsso: widget.senzaDiEsso,
          ),
          const SizedBox(height: AppSpacing.lg),
          ..._actions(),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    switch (_ui) {
      case _Ui.loading:
        return const [];
      case _Ui.granted:
        return [
          AppTappable(
            onTap: widget.onDone,
            semanticLabel: 'Consentito',
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('Consentito', textAlign: TextAlign.center),
            ),
          ),
        ];
      case _Ui.unavailable:
        return [
          const Text('Non disponibile su questo dispositivo.', textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.base),
          AppButton.secondary(
            label: _continueLabel,
            onPressed: widget.onDone,
            size: AppButtonSize.lg,
          ),
        ];
      case _Ui.deniedForever:
        return [
          AppButton(
            label: 'Apri impostazioni',
            onPressed: widget.onOpenSettings ?? widget.onDone,
            size: AppButtonSize.lg,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(
            label: _continueLabel,
            onPressed: widget.onDone,
            size: AppButtonSize.lg,
          ),
        ];
      case _Ui.ask:
        return [
          AppButton(
            label: widget.ctaLabel,
            isLoading: _busy,
            onPressed: _busy ? null : _consenti,
            size: AppButtonSize.lg,
          ),
          // No skip on a requiresSystemDialog step: the only way past the undecided state is the
          // real system dialog, so the answer is always the OS's and never the app's.
          if (!widget.requiresSystemDialog) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton.secondary(
              label: _continueLabel,
              onPressed: widget.onDone,
              size: AppButtonSize.lg,
            ),
          ],
        ];
    }
  }
}
