// dart format width=100
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import 'onboarding_notification_ask.dart';
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
  bool _notificationRequestFailed = false;

  /// What the OS says about notifications right now. `null` means "not asked yet" (or the
  /// status could not be read) — the one state that offers the ask.
  bool? _notificationsGranted;

  Future<void> _complete() async {
    if (_completing) return;
    _completing = true;
    await ref
        .read(onboardingCompletedProvider(widget.userId).notifier)
        .markCompleted();
    // The router's redirect takes it from here.
  }

  @override
  void initState() {
    super.initState();
    if (ref.read(notificationAvailableProvider)) {
      // Seed the real state: a device that already authorized us must not be asked again, and
      // one that denied must not get a silent no-op button.
      Future.microtask(_loadNotificationStatus);
    }
  }

  Future<void> _loadNotificationStatus() async {
    try {
      final status = await ref.read(onboardingNotificationStatusProvider)();
      if (!mounted) return;
      setState(() {
        _notificationsGranted = switch (status) {
          AuthorizationStatus.authorized ||
          AuthorizationStatus.provisional => true,
          // firebase_messaging 16 adds `deniedPermanently` (Android 13+ only); for the
          // onboarding ask it is the same outcome as `denied`.
          AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => false,
          AuthorizationStatus.notDetermined => null,
        };
      });
    } catch (_) {
      // Unreadable status leaves the ask available; it is not worth failing the screen.
    }
  }

  Future<void> _askNotifications() async {
    try {
      final granted = await ref.read(onboardingNotificationAskProvider)();
      if (mounted) {
        setState(() {
          _notificationsGranted = granted;
          _notificationRequestFailed = false;
        });
      }
    } catch (_) {
      // A platform/channel failure must not escape as an unhandled async error: the welcome
      // stays usable and the action can be retried.
      if (mounted) setState(() => _notificationRequestFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAvailable = ref.watch(notificationAvailableProvider);

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
                if (!notificationsAvailable)
                  Text(
                    'Non disponibile su questo dispositivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.inkMuted),
                  )
                else if (_notificationsGranted == true)
                  Text(
                    'Notifiche attive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.inkMuted),
                  )
                else if (_notificationsGranted == false)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Le notifiche sono disattivate. Puoi attivarle da Impostazioni.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Archivo',
                          fontSize: 14,
                          color: context.colors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton.secondary(
                        label: 'Apri Impostazioni',
                        onPressed: openAppSettings,
                      ),
                    ],
                  )
                else
                  AppButton.secondary(
                    label: 'Attiva le notifiche',
                    onPressed: _askNotifications,
                  ),
                if (_notificationRequestFailed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Non è stato possibile attivare le notifiche. Riprova.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.inkMuted),
                  ),
                ],
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
