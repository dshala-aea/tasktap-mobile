// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/biometric_service.dart';
import '../../core/widgets/app_toast.dart';
import 'impostazioni_provider.dart';

/// Attempts to turn the biometric lock on: checks the device actually has biometrics enrolled,
/// then proves the technician can pass the prompt right now, before persisting the setting.
/// Returns `true` only if the lock is now genuinely enabled.
///
/// Shared by Impostazioni's toggle and the onboarding flow so both go through the identical
/// sequence — a lock nobody can open is its own failure mode, and that was true the one time this
/// existed only inline in `impostazioni_screen.dart`.
Future<bool> enableBiometricLock(BuildContext context, WidgetRef ref) async {
  final service = ref.read(biometricServiceProvider);

  if (!await service.isAvailable()) {
    if (!context.mounted) return false;
    showAppToast(
      context,
      message:
          'Nessuna impronta o Face ID configurati su questo dispositivo. '
          'Aggiungili nelle impostazioni del telefono, poi riprova.',
      tone: ToastTone.warning,
    );
    return false;
  }

  final ok = await service.authenticate(
    reason: 'Conferma la tua identità per attivare il blocco biometrico',
  );

  if (!ok) {
    if (!context.mounted) return false;
    showAppToast(
      context,
      message: 'Verifica non riuscita. Blocco biometrico non attivato.',
      tone: ToastTone.error,
    );
    return false;
  }

  ref.read(impostazioniProvider.notifier).toggle(key: 'autenticazioneBiometrica');
  return true;
}
