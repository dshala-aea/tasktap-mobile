// dart format width=100
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys/types.dart';
import 'package:tasktap_mobile/core/security/passkey_support.dart';

AvailabilityTypeAndroid _android({
  required bool hasPasskeySupport,
  required bool isUserVerifyingPlatformAuthenticatorAvailable,
}) {
  return AvailabilityTypeAndroid(
    hasPasskeySupport: hasPasskeySupport,
    isNative: true,
    isUserVerifyingPlatformAuthenticatorAvailable: isUserVerifyingPlatformAuthenticatorAvailable,
  );
}

AvailabilityTypeIOS _ios({required bool hasPasskeySupport, required bool hasBiometrics}) {
  return AvailabilityTypeIOS(
    hasPasskeySupport: hasPasskeySupport,
    isNative: true,
    hasBiometrics: hasBiometrics,
  );
}

class _FakeAvailability implements PasskeyAvailabilitySource {
  _FakeAvailability({this.androidResult, this.iosResult, this.error});

  final AvailabilityTypeAndroid? androidResult;
  final AvailabilityTypeIOS? iosResult;
  final Object? error;

  int androidCalls = 0;
  int iosCalls = 0;

  @override
  Future<AvailabilityTypeAndroid> androidAvailability() async {
    androidCalls++;
    if (error != null) throw error!;
    return androidResult!;
  }

  @override
  Future<AvailabilityTypeIOS> iosAvailability() async {
    iosCalls++;
    if (error != null) throw error!;
    return iosResult!;
  }
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('PasskeySupport.isAvailable — Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('android is available only with support and a verifying authenticator', () async {
      final available = _FakeAvailability(
        androidResult: _android(
          hasPasskeySupport: true,
          isUserVerifyingPlatformAuthenticatorAvailable: true,
        ),
      );
      expect(await PasskeySupport(availability: available).isAvailable(), isTrue);

      final noSupport = _FakeAvailability(
        androidResult: _android(
          hasPasskeySupport: false,
          isUserVerifyingPlatformAuthenticatorAvailable: true,
        ),
      );
      expect(await PasskeySupport(availability: noSupport).isAvailable(), isFalse);

      final noVerifier = _FakeAvailability(
        androidResult: _android(
          hasPasskeySupport: true,
          isUserVerifyingPlatformAuthenticatorAvailable: false,
        ),
      );
      expect(await PasskeySupport(availability: noVerifier).isAvailable(), isFalse);
    });

    test('a platform exception is reported as unavailable', () async {
      final failing = _FakeAvailability(error: StateError('platform channel down'));
      expect(await PasskeySupport(availability: failing).isAvailable(), isFalse);
    });
  });

  group('PasskeySupport.isAvailable — iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('ios requires support and biometrics', () async {
      final available = _FakeAvailability(
        iosResult: _ios(hasPasskeySupport: true, hasBiometrics: true),
      );
      expect(await PasskeySupport(availability: available).isAvailable(), isTrue);

      final noSupport = _FakeAvailability(
        iosResult: _ios(hasPasskeySupport: false, hasBiometrics: true),
      );
      expect(await PasskeySupport(availability: noSupport).isAvailable(), isFalse);

      final noBiometrics = _FakeAvailability(
        iosResult: _ios(hasPasskeySupport: true, hasBiometrics: false),
      );
      expect(await PasskeySupport(availability: noBiometrics).isAvailable(), isFalse);
    });

    test('a platform exception is reported as unavailable', () async {
      final failing = _FakeAvailability(error: StateError('platform channel down'));
      expect(await PasskeySupport(availability: failing).isAvailable(), isFalse);
    });
  });

  test('other platforms are unavailable without querying the plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final untouched = _FakeAvailability();

    expect(await PasskeySupport(availability: untouched).isAvailable(), isFalse);
    expect(untouched.androidCalls, 0);
    expect(untouched.iosCalls, 0);
  });

  test('passkeySupportedProvider exposes the gate result', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final available = _FakeAvailability(
      androidResult: _android(
        hasPasskeySupport: true,
        isUserVerifyingPlatformAuthenticatorAvailable: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        passkeySupportProvider.overrideWithValue(PasskeySupport(availability: available)),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(passkeySupportedProvider.future), isTrue);
  });
}
