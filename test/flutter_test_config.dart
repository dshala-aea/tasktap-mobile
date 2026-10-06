import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Global test setup.
///
/// The flutter_secure_storage platform channel has no host side in `flutter test` and, unlike an
/// unregistered plugin on a device, NEVER replies — so any code that reads the keychain just
/// hangs. That used to be invisible. Cold start is now bounded (5s keychain timeouts in
/// `ZitadelAuthRepository._restore` and `KioskModeNotifier._init`), and a hung read therefore
/// leaves a pending Timer that fails every widget test reaching those providers.
///
/// Answering "empty keychain" (null for every call) makes those paths settle immediately, exactly
/// as a fresh install would. Tests that need real behaviour mock `FlutterSecureStorage` /
/// `KioskCredentialsStore` themselves (mocktail) and are unaffected.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null,
  );
  await testMain();
}
