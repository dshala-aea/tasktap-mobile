import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every OS permission the app requests must be declared with a purpose string.
///
/// This exists because the app shipped without `NSCameraUsageDescription` or
/// `NSPhotoLibraryUsageDescription` while `image_picker` used both sources. On iOS that is not a
/// store-review nit — the OS **terminates the process** the moment a permission is requested with
/// no matching usage-description key, so attaching a photo to a rapportino would have crashed the
/// app on every iPhone. Nothing in the Dart toolchain catches it: the analyzer sees a valid
/// plugin call and the widget tests never touch the platform channel.
///
/// The mapping is deliberately written from *what lib/ actually calls* rather than from a
/// checklist, so adding a plugin without its declaration fails here rather than on a device.
void main() {
  final lib = Directory('lib');
  final infoPlist = File('ios/Runner/Info.plist');
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  String allDartSource() {
    final buffer = StringBuffer();
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buffer.writeln(entity.readAsStringSync());
      }
    }
    return buffer.toString();
  }

  late String source;
  late String plist;

  setUpAll(() {
    source = allDartSource();
    plist = infoPlist.readAsStringSync();
  });

  group('iOS usage descriptions', () {
    /// Each entry: the call that triggers the OS prompt, and the key iOS demands for it.
    const required = <String, (String trigger, String key)>{
      'camera': ('ImageSource.camera', 'NSCameraUsageDescription'),
      'photo library': ('ImageSource.gallery', 'NSPhotoLibraryUsageDescription'),
      'location': ('Geolocator', 'NSLocationWhenInUseUsageDescription'),
    };

    for (final entry in required.entries) {
      test('${entry.key} is declared because lib/ requests it', () {
        final (trigger, key) = entry.value;
        if (!source.contains(trigger)) {
          markTestSkipped('$trigger is not used; no declaration needed');
          return;
        }

        expect(
          plist,
          contains('<key>$key</key>'),
          reason:
              'lib/ calls $trigger, so iOS requires $key. Without it the OS kills the app at the '
              'permission prompt — this is a crash, not a warning.',
        );
      });
    }

    test('every usage description says what the data is for', () {
      // A purpose string that does not name a purpose fails App Review, and more importantly
      // tells the technician nothing at the moment they are asked to decide.
      final matches = RegExp(
        r'<key>(NS\w*UsageDescription)</key>\s*<string>([^<]*)</string>',
      ).allMatches(plist);

      expect(matches, isNotEmpty, reason: 'no usage descriptions found at all');

      for (final m in matches) {
        final key = m.group(1)!;
        final text = m.group(2)!.trim();
        expect(text.length, greaterThan(40), reason: '$key is too terse to be a real purpose');
        expect(
          text.toLowerCase(),
          contains('tasktap'),
          reason: '$key should name the app and the reason, not just the permission',
        );
      }
    });

    test('nothing is declared that the app does not use', () {
      // A declared-but-unused permission is a data-minimisation problem and an App Review
      // question nobody can answer.
      const declaredToTrigger = {
        'NSCameraUsageDescription': 'ImageSource.camera',
        'NSPhotoLibraryUsageDescription': 'ImageSource.gallery',
        'NSLocationWhenInUseUsageDescription': 'Geolocator',
        'NSMicrophoneUsageDescription': 'record',
      };

      for (final entry in declaredToTrigger.entries) {
        if (!plist.contains('<key>${entry.key}</key>')) continue;
        expect(
          source.contains(entry.value),
          isTrue,
          reason: '${entry.key} is declared but lib/ never calls ${entry.value}',
        );
      }
    });
  });

  group('Android manifest', () {
    test('location permissions are declared because lib/ requests them', () {
      final xml = manifest.readAsStringSync();
      if (!source.contains('Geolocator')) {
        markTestSkipped('Geolocator is not used');
        return;
      }
      expect(xml, contains('android.permission.ACCESS_FINE_LOCATION'));
    });

    test('no permission is declared that lib/ never uses', () {
      final xml = manifest.readAsStringSync();
      const declaredToTrigger = {
        'android.permission.ACCESS_FINE_LOCATION': 'Geolocator',
        'android.permission.RECORD_AUDIO': 'record',
      };

      for (final entry in declaredToTrigger.entries) {
        if (!xml.contains(entry.key)) continue;
        expect(
          source.contains(entry.value),
          isTrue,
          reason: '${entry.key} is declared but lib/ never calls ${entry.value}',
        );
      }
    });
  });
}
