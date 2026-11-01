// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import 'onboarding_provider.dart';

/// One-time, post-login welcome.
///
/// Deliberately short: the only permission worth asking for before the technician needs it is
/// notifications (assignment alerts are useless if discovered weeks later). Location, camera and
/// microphone prompt themselves the first time the capability is actually used, and biometric
/// unlock stays an opt-in in Impostazioni — a first-run gauntlet through four consent pages was
/// getting in the way of the first shift.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _completing = false;
  bool _notificationsGranted = false;

  Future<void> _complete() async {
    if (_completing) return;
    _completing = true;
    await ref
        .read(onboardingCompletedProvider(widget.userId).notifier)
        .markCompleted();
    // The router's redirect takes it from here.
  }

  Future<void> _askNotifications() async {
    if (!NotificationService.isAvailable) return;
    final granted = await NotificationService.instance.ensurePermission();
    if (mounted) setState(() => _notificationsGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAvailable = NotificationService.isAvailable;

    return Scaffold(
      backgroundColor: context.colors.bg1,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Benvenuto in TaskTap',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Archivo Narrow',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: context.colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  'Ti avvisiamo quando ti viene assegnato un intervento o quando un rapportino ha '
                  'bisogno di te. Gli altri permessi li chiederemo quando servono davvero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 15,
                    color: context.colors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (notificationsAvailable && !_notificationsGranted)
                  AppButton.secondary(
                    label: 'Attiva le notifiche',
                    onPressed: _askNotifications,
                  )
                else if (_notificationsGranted)
                  Text(
                    'Notifiche attive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.inkMuted),
                  )
                else
                  Text(
                    'Non disponibile su questo dispositivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.inkMuted),
                  ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(label: 'Inizia', onPressed: _complete, size: AppButtonSize.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
