// dart format width=100
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Device biometrics, behind an interface so the lock can be tested without a fingerprint reader.
///
/// The Impostazioni screen has offered "Autenticazione biometrica — Accesso con impronta o Face
/// ID" since it was written, with no biometrics package in the project at all. The toggle flipped
/// a bool that nothing read: a technician could switch it on, believe the customer and intervento
/// data on their phone was protected, and it was not. A security control that only claims to exist
/// is worse than an absent one, because it stops the user looking for a real one.
abstract class IBiometricService {
  /// Whether this device can actually prompt — hardware present AND something enrolled.
  Future<bool> isAvailable();

  /// Prompts. True only on a successful match; false on cancel, lockout or any failure.
  Future<bool> authenticate({required String reason});
}

class BiometricService implements IBiometricService {
  const BiometricService(this._auth);

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      // Both halves matter. `isDeviceSupported` is hardware; `canCheckBiometrics` plus a non-empty
      // enrolled list is whether the technician has actually registered a finger or a face. A
      // device with a sensor and nothing enrolled would let the toggle switch on and then never
      // be able to prompt.
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Biometrics only — no PIN/pattern fallback. The point of this lock is that the phone
          // may be handed around a site; a device passcode a colleague has watched being typed
          // would defeat it.
          biometricOnly: true,
          // Keep the lock up while the OS prompt is showing, so the app behind it is never
          // briefly visible in the task switcher.
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      // Includes lockout after too many failures, and a device where enrolment was removed
      // between enabling the setting and now. Failing closed is correct: the caller keeps the
      // lock up.
      return false;
    }
  }
}

final biometricServiceProvider = Provider<IBiometricService>((ref) {
  return BiometricService(LocalAuthentication());
});
