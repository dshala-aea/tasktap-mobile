// dart format width=100
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/availability.dart';
import 'package:passkeys/types.dart';

/// The platform availability numbers the passkey gate needs, behind a seam.
///
/// The real implementation wraps `PasskeyAuthenticator().getAvailability()`;
/// tests inject a fake so they never touch platform channels.
abstract interface class PasskeyAvailabilitySource {
  Future<AvailabilityTypeAndroid> androidAvailability();

  Future<AvailabilityTypeIOS> iosAvailability();
}

class _PluginAvailabilitySource implements PasskeyAvailabilitySource {
  _PluginAvailabilitySource(this._availability);

  final GetAvailability _availability;

  @override
  Future<AvailabilityTypeAndroid> androidAvailability() => _availability.android();

  @override
  Future<AvailabilityTypeIOS> iosAvailability() => _availability.iOS();
}

/// Whether this device can actually use passkeys.
///
/// A passkey button that leads nowhere is worse than no button at all: Android
/// needs OS support and a user-verifying platform authenticator, iOS needs OS
/// support and enrolled biometrics. Anything else — another platform, a
/// plugin failure — fails closed, so the password path stays the only offer.
class PasskeySupport {
  PasskeySupport({PasskeyAvailabilitySource? availability})
    : _availability =
          availability ?? _PluginAvailabilitySource(PasskeyAuthenticator().getAvailability());

  final PasskeyAvailabilitySource _availability;

  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = await _availability.androidAvailability();
          return android.hasPasskeySupport &&
              (android.isUserVerifyingPlatformAuthenticatorAvailable ?? false);
        case TargetPlatform.iOS:
          final ios = await _availability.iosAvailability();
          return ios.hasPasskeySupport && ios.hasBiometrics;
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          return false;
      }
    } catch (_) {
      // Includes MissingPluginException and any platform-channel error. Failing
      // closed keeps the passkey button hidden instead of offering a dead end.
      return false;
    }
  }
}

final passkeySupportProvider = Provider<PasskeySupport>((ref) => PasskeySupport());

/// Gate consumed by the login screen before rendering "Accedi con passkey".
final passkeySupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(passkeySupportProvider).isAvailable(),
);
