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

  @override
  State<PermissionStepPage> createState() => _PermissionStepPageState();
}

enum _Ui { loading, ask, granted, deniedForever, unavailable }

class _PermissionStepPageState extends State<PermissionStepPage> {
  _Ui _ui = _Ui.loading;
  bool _busy = false;
  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await widget.checkStatus();
    if (!mounted) return;
    setState(() => _ui = _uiFor(status));
    if (_ui == _Ui.granted) _scheduleAutoAdvance();
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
    final status = await widget.request();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ui = _uiFor(status);
    });
    if (_ui == _Ui.granted) _scheduleAutoAdvance();
  }

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
          AppButton.secondary(label: 'Non ora', onPressed: widget.onDone, size: AppButtonSize.lg),
        ];
      case _Ui.deniedForever:
        return [
          AppButton(
            label: 'Apri impostazioni',
            onPressed: widget.onOpenSettings ?? widget.onDone,
            size: AppButtonSize.lg,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Non ora', onPressed: widget.onDone, size: AppButtonSize.lg),
        ];
      case _Ui.ask:
        return [
          AppButton(
            label: widget.ctaLabel,
            isLoading: _busy,
            onPressed: _busy ? null : _consenti,
            size: AppButtonSize.lg,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Non ora', onPressed: widget.onDone, size: AppButtonSize.lg),
        ];
    }
  }
}
