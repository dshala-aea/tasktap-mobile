// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';

/// Shown in place of the app when this build is below the server's minimum AND nothing is waiting
/// to be sent (see `updateGateMode`). Big type and one big button: it is read gloved and in sun.
/// The copy says the data on the phone is safe, because that is the one fear this screen raises.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.onUpdate, this.message});

  final VoidCallback onUpdate;

  /// Operator-written note from the policy, shown under the standard text when present.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final extra = message?.trim();
    return Scaffold(
      key: const Key('updateRequiredScreen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(LucideIcons.download, size: 56, color: context.colors.ink),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Aggiornamento necessario',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: context.colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Per continuare a usare TaskTap serve la versione più recente dell’app. '
                  'I dati salvati su questo telefono sono al sicuro: verranno inviati dopo '
                  'l’aggiornamento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, height: 1.4, color: context.colors.ink),
                ),
                if (extra != null && extra.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    extra,
                    key: const Key('updateRequiredMessage'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.4, color: context.colors.inkMuted),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  key: const Key('updateRequiredButton'),
                  label: 'Aggiorna ora',
                  size: AppButtonSize.lg,
                  icon: const Icon(LucideIcons.download),
                  onPressed: onUpdate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
