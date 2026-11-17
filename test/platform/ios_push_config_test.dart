import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The three declarations iOS needs before it will accept this app for remote notifications.
///
/// Missing any one of them does not fail the build: the app launches, `firebase_messaging` answers
/// without an APNs token, and the app quietly treats push as unsupported on iOS. That is why this
/// is a test over the native project files rather than something Dart can assert at runtime — the
/// Dart side cannot see the Xcode project it was compiled from.
///
/// A fourth requirement lives outside the repository: Push Notifications must be enabled on the
/// App ID in the Apple Developer portal, and the provisioning profile must be regenerated after it
/// is. `codemagic.yaml` signs with `xcode-project use-profiles`, so a profile without the
/// capability strips `aps-environment` from the signed app even when this file is correct.
void main() {
  final entitlements = File('ios/Runner/Runner.entitlements');
  final infoPlist = File('ios/Runner/Info.plist');
  final project = File('ios/Runner.xcodeproj/project.pbxproj');

  group('iOS push capability', () {
    test('the entitlement file requests an APNs environment', () {
      final plist = entitlements.readAsStringSync();

      // Xcode sets this to `development`; a distribution profile supplies `production` at signing
      // time. Both are valid here — an empty or missing key is not.
      expect(
        plist,
        matches(
          RegExp(
            r'<key>aps-environment</key>\s*<(?:string)>(development|production)</(?:string)>',
          ),
        ),
        reason:
            'Runner.entitlements must contain aps-environment. Without it iOS never issues an APNs '
            'token, and firebase_messaging reports push as unsupported.',
      );
    });

    test('the Runner target declares the Push Notifications capability', () {
      final pbx = project.readAsStringSync();

      expect(
        pbx,
        contains('com.apple.Push'),
        reason:
            'Runner.xcodeproj must carry SystemCapabilities → com.apple.Push. Xcode uses it to '
            'enable the capability on the App ID and to keep it enabled when the profile is '
            'regenerated; without it the capability can silently drop off.',
      );
      expect(
        pbx,
        matches(RegExp(r'com\.apple\.Push = \{\s*enabled = 1;')),
        reason: 'the Push capability must be enabled, not merely mentioned',
      );
    });

    test('every Runner build configuration signs with the entitlement file', () {
      final pbx = project.readAsStringSync();
      final matches = RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;',
      ).allMatches(pbx);

      // Debug, Release and Profile. Release is the one that ships, but a configuration without the
      // file builds an app whose behaviour nobody tested.
      expect(
        matches.length,
        3,
        reason:
            'all three Runner configurations (Debug/Release/Profile) must point at '
            'Runner.entitlements; one without it is an app that cannot receive push.',
      );
    });

    test('the app declares the remote-notification background mode', () {
      final plist = infoPlist.readAsStringSync();

      final modes = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>([\s\S]*?)</array>',
      ).firstMatch(plist);

      expect(
        modes,
        isNotNull,
        reason: 'Info.plist has no UIBackgroundModes array',
      );
      expect(
        modes!.group(1),
        contains('<string>remote-notification</string>'),
        reason:
            'Without UIBackgroundModes → remote-notification, iOS will not wake the app for a '
            'silent/data push and background delivery is dropped.',
      );
    });
  });
}
