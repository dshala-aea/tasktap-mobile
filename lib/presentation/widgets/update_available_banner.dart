// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';

/// Soft nudge for a build below the recommended one: dismissible, and the dismissal is remembered
/// for 7 days (`AppVersionStatusNotifier.dismissAvailable`). Has its own [Material]: it lives in
/// the app shell's `builder`, above any Scaffold.
class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({super.key, required this.onUpdate, required this.onDismiss});

  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('updateAvailableBanner'),
      color: context.colors.bg3,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'È disponibile una nuova versione di TaskTap.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: context.colors.ink,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                key: const Key('updateAvailableButton'),
                label: 'Aggiorna',
                fullWidth: false,
                onPressed: onUpdate,
              ),
              // No tooltip: this banner lives above the Navigator (no Overlay ancestor).
              Semantics(
                label: 'Nascondi per 7 giorni',
                button: true,
                excludeSemantics: true,
                child: IconButton(
                  key: const Key('updateAvailableDismiss'),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(LucideIcons.x, color: context.colors.ink),
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
