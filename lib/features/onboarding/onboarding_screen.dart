// dart format width=100
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/dictation/dictation_service.dart';
import '../../core/icons/app_lucide_icons.dart';
import '../../core/location/location_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../altro/biometric_setup.dart';
import '../altro/impostazioni_provider.dart';
import 'onboarding_provider.dart';
import 'permission_step_page.dart';

/// One-time, post-login setup: explains and requests the four permissions/settings the app can
/// use, in the order a new technician is most likely to need them. See
/// `docs/superpowers/specs/2026-09-17-onboarding-flow-design.md` for why this exists and why each
/// step delegates to an existing service rather than inventing new permission logic.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  static const _pageCount = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_controller.page == null) return;
    final next = _controller.page!.round() + 1;
    if (next >= _pageCount) {
      ref.read(onboardingCompletedProvider(widget.userId).notifier).markCompleted();
      return; // The router's own redirect takes it from here.
    }
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg1,
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _WelcomePage(onNext: _next),
            PermissionStepPage(
              icon: LucideIcons.mapPin,
              titolo: 'Dove sei intervenuto',
              motivo:
                  'La posizione viene registrata quando timbri su un cantiere, come prova di dove '
                  'sei intervenuto.',
              senzaDiEsso: 'Puoi comunque timbrare e compilare rapportini: resteranno senza '
                  'coordinate.',
              ctaLabel: 'Consenti la posizione',
              checkStatus: () async =>
                  _fromGps(await ref.read(locationServiceProvider).permissionStatus()),
              request: () async {
                final coords = await ref.read(locationServiceProvider).getCurrentPosition();
                return coords != null
                    ? PermissionStepStatus.granted
                    : _fromGps(await ref.read(locationServiceProvider).permissionStatus());
              },
              onDone: _next,
              onOpenSettings: () => openAppSettings(),
            ),
            PermissionStepPage(
              icon: LucideIcons.bell,
              titolo: 'Avvisi sul lavoro',
              motivo:
                  'Ti avvisiamo quando ti viene assegnato un intervento, quando cambia un '
                  'appuntamento e quando un rapportino ha bisogno di te.',
              senzaDiEsso:
                  'Senza notifiche l\'app funziona lo stesso: trovi tutto in Dashboard e in '
                  'Calendario, ma lo scopri quando apri l\'app.',
              ctaLabel: 'Attiva le notifiche',
              checkStatus: () async {
                if (!NotificationService.isAvailable) return PermissionStepStatus.unavailable;
                final status = await NotificationService.instance.authorizationStatus();
                if (status == AuthorizationStatus.authorized ||
                    status == AuthorizationStatus.provisional) {
                  return PermissionStepStatus.granted;
                }
                // Android's areNotificationsEnabled() check collapses "never asked" and
                // "explicitly denied" to the same `denied` value — only iOS can report
                // notDetermined here — so `denied` from a status CHECK (not yet asked) can't be
                // treated as final on Android.
                return Platform.isAndroid
                    ? PermissionStepStatus.notDetermined
                    : _fromAuthorization(status);
              },
              request: () async {
                if (!NotificationService.isAvailable) return PermissionStepStatus.unavailable;
                final granted = await NotificationService.instance.ensurePermission();
                // An actual ask just happened (or the OS silently declined to show one) — denied
                // here is final on both platforms, unlike the ambiguous pre-ask status check
                // above.
                return granted ? PermissionStepStatus.granted : PermissionStepStatus.deniedForever;
              },
              onDone: _next,
              onOpenSettings: () => openAppSettings(),
            ),
            PermissionStepPage(
              icon: LucideIcons.camera,
              titolo: 'Fotocamera e microfono',
              motivo:
                  'La fotocamera serve per allegare foto dell\'intervento al rapportino; il '
                  'microfono per dettare la descrizione invece di scriverla.',
              senzaDiEsso: 'Puoi comunque compilare i rapportini a mano, senza foto.',
              ctaLabel: 'Consenti',
              checkStatus: _cameraMicStatus,
              request: _cameraMicRequest,
              onDone: _next,
              onOpenSettings: () => openAppSettings(),
            ),
            PermissionStepPage(
              icon: LucideIcons.fingerprint,
              titolo: 'Blocco biometrico',
              motivo:
                  'Richiedi impronta o Face ID all\'apertura dell\'app, a protezione dei dati di '
                  'clienti e interventi su questo dispositivo.',
              senzaDiEsso: 'Puoi attivarlo in qualsiasi momento da Impostazioni.',
              ctaLabel: 'Attiva',
              checkStatus: () async {
                final settings = ref.read(impostazioniProvider);
                if (settings.autenticazioneBiometrica) return PermissionStepStatus.granted;
                final available = await ref.read(biometricServiceProvider).isAvailable();
                return available ? PermissionStepStatus.notDetermined : PermissionStepStatus.unavailable;
              },
              request: () async {
                final enabled = await enableBiometricLock(context, ref);
                return enabled ? PermissionStepStatus.granted : PermissionStepStatus.notDetermined;
              },
              onDone: _next,
              onOpenSettings: () => openAppSettings(),
            ),
          ],
        ),
      ),
    );
  }

  Future<PermissionStepStatus> _cameraMicStatus() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    if (camera.isGranted && mic.isGranted) return PermissionStepStatus.granted;
    if (camera.isPermanentlyDenied || mic.isPermanentlyDenied) {
      return PermissionStepStatus.deniedForever;
    }
    return PermissionStepStatus.notDetermined;
  }

  Future<PermissionStepStatus> _cameraMicRequest() async {
    final cameraResult = await Permission.camera.request();
    // Mic's actual grant still goes through DictationService, not permission_handler, so the app
    // keeps exactly one place that decides "dictation actually works" (capability + permission
    // together) — see step_dettagli.dart's own capability() call for the other consumer of this.
    final micCapability = await ref.read(dictationServiceProvider).capability();
    final micStatus = await Permission.microphone.status;
    if (cameraResult.isGranted && (micCapability.microphoneGranted || micStatus.isGranted)) {
      return PermissionStepStatus.granted;
    }
    if (cameraResult.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
      return PermissionStepStatus.deniedForever;
    }
    return PermissionStepStatus.notDetermined;
  }

  PermissionStepStatus _fromGps(GpsPermissionStatus status) => switch (status) {
    GpsPermissionStatus.granted => PermissionStepStatus.granted,
    GpsPermissionStatus.deniedForever ||
    GpsPermissionStatus.serviceDisabled => PermissionStepStatus.deniedForever,
    GpsPermissionStatus.notDetermined => PermissionStepStatus.notDetermined,
  };

  PermissionStepStatus _fromAuthorization(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PermissionStepStatus.granted,
    AuthorizationStatus.denied => PermissionStepStatus.deniedForever,
    AuthorizationStatus.notDetermined => PermissionStepStatus.notDetermined,
  };
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            'Configuriamo insieme i permessi di cui TaskTap ha bisogno per funzionare al meglio '
            'sul campo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Archivo', fontSize: 15, color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Inizia', onPressed: onNext, size: AppButtonSize.lg),
        ],
      ),
    );
  }
}
