// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';

/// Shown while an update is required but [pending] items are still waiting to be sent. Calm, not an
/// alarm: the app stays usable and the queues keep flushing; the blocking screen takes over only
/// once the count reaches zero. The button lets the user update anyway (the new build reads the
/// queue that is already on the phone), for the case where a flush never completes.
class UpdatePendingSyncBanner extends StatelessWidget {
  const UpdatePendingSyncBanner({super.key, required this.pending, required this.onUpdate});

  final int pending;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final what = pending == 1 ? '1 elemento in attesa di invio' : '$pending elementi in attesa di invio';
    return Material(
      key: const Key('updatePendingSyncBanner'),
      color: context.colors.bg3,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sincronizza, poi aggiorna',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$what. Restano al sicuro sul telefono: dopo l’invio, o dopo '
                      'l’aggiornamento, non si perde nulla.',
                      style: TextStyle(fontSize: 13, height: 1.3, color: context.colors.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                key: const Key('updatePendingSyncButton'),
                label: 'Aggiorna',
                fullWidth: false,
                onPressed: onUpdate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
