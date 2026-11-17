import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS permission_handler compiles each permission in or out at build time.
///
/// Under CocoaPods the `PERMISSION_*` macros default to `0`, and a compiled-out permission
/// answers `PermissionStatus.denied` no matter what the technician chose in Settings. A missing
/// macro therefore does not fail the build or the analyzer: the microphone button simply refuses
/// to start, and the app reports that the OS denied a permission the OS never asked about.
///
/// The macros live in the Podfile's `post_install` block. This repository ships no Podfile, so
/// Flutter generated the default one on the build machine — which defines none of them. That made
/// the behaviour depend on whether that machine used CocoaPods or Swift Package Manager (SPM
/// derives the macros from Info.plist). Pinning the Podfile makes the CocoaPods path deterministic.
void main() {
  final podfile = File('ios/Podfile');

  /// `Permission.microphone` → `PERMISSION_MICROPHONE`, and so on.
  ///
  /// Only the identifiers the app actually uses are mapped, so adding a call that this test does
  /// not understand fails loudly instead of silently shipping a disabled permission.
  const macroForPermission = <String, String>{
    'microphone': 'PERMISSION_MICROPHONE',
    'camera': 'PERMISSION_CAMERA',
    'speech': 'PERMISSION_SPEECH_RECOGNIZER',
    'photos': 'PERMISSION_PHOTOS',
    'photosAddOnly': 'PERMISSION_PHOTOS_ADD_ONLY',
    'location': 'PERMISSION_LOCATION',
    'locationWhenInUse': 'PERMISSION_LOCATION',
    'locationAlways': 'PERMISSION_LOCATION',
    'notification': 'PERMISSION_NOTIFICATIONS',
    'contacts': 'PERMISSION_CONTACTS',
    'events': 'PERMISSION_EVENTS',
    'reminders': 'PERMISSION_REMINDERS',
    'mediaLibrary': 'PERMISSION_MEDIA_LIBRARY',
    'sensors': 'PERMISSION_SENSORS',
    'bluetooth': 'PERMISSION_BLUETOOTH',
    'phone': 'PERMISSION_PHONE',
    'storage': 'PERMISSION_STORAGE',
    'criticalAlerts': 'PERMISSION_CRITICAL_ALERTS',
    'assistant': 'PERMISSION_ASSISTANT',
    'appTrackingTransparency': 'PERMISSION_APP_TRACKING_TRANSPARENCY',
  };

  Set<String> permissionsUsedByLib() {
    final buffer = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buffer.writeln(entity.readAsStringSync());
      }
    }
    return RegExp(r'\bPermission\.(\w+)')
        .allMatches(buffer.toString())
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('the Podfile exists so permission macros do not depend on the build machine', () {
    expect(
      podfile.existsSync(),
      isTrue,
      reason:
          'ios/Podfile is missing. Flutter would generate the template on CI, which leaves every '
          'PERMISSION_* macro at 0 and makes permission_handler deny permissions the OS allows.',
    );
  });

  test('every permission_handler permission used by lib/ is compiled in', () {
    final used = permissionsUsedByLib();
    expect(
      used,
      isNotEmpty,
      reason: 'the app no longer calls permission_handler; this guard can be removed',
    );

    final podfileText = podfile.readAsStringSync();
    for (final permission in used) {
      final macro = macroForPermission[permission];
      expect(
        macro,
        isNotNull,
        reason:
            'Permission.$permission has no known iOS macro. Add it to the map in this test and to '
            'ios/Podfile before shipping, or the permission is silently compiled out.',
      );
      expect(
        podfileText,
        matches(RegExp("'$macro=1'")),
        reason:
            'lib/ calls Permission.$permission, so ios/Podfile must define $macro=1 in its '
            'post_install block. Without it iOS treats the permission as denied regardless of the '
            'OS setting.',
      );
    }
  });

  test('the Podfile matches the Runner deployment target', () {
    final podfileText = podfile.readAsStringSync();
    expect(
      podfileText,
      contains("platform :ios, '15.5'"),
      reason:
          'Runner.xcodeproj targets iOS 15.5. A lower Podfile platform builds every pod against a '
          'target the app no longer supports, and a higher one is rejected by Flutter plugins.',
    );
  });

  test('the Podfile installs Flutter plugins and adjusts their build settings', () {
    final podfileText = podfile.readAsStringSync();
    expect(podfileText, contains('flutter_install_all_ios_pods'));
    expect(podfileText, contains('flutter_additional_ios_build_settings(target)'));
  });
}
