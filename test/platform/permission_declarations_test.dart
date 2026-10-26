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
      'microphone': ('SpeechToText', 'NSMicrophoneUsageDescription'),
      'speech recognition': ('SpeechToText', 'NSSpeechRecognitionUsageDescription'),
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
        // The trigger is the recogniser, not the string "record" — which any comment mentioning
        // recording satisfies by accident, and which would keep this passing after the feature
        // was removed.
        'NSMicrophoneUsageDescription': 'SpeechToText',
        'NSSpeechRecognitionUsageDescription': 'SpeechToText',
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

  /// Export compliance is the one App Store question that ships with the binary rather than being
  /// answered once in a form. Without the key, every upload lands at "Missing Compliance" in App
  /// Store Connect and stays undeliverable to testers until someone fills the questionnaire in by
  /// hand — a step that is easy to miss precisely because the build itself succeeded.
  group('App Store export compliance', () {
    test('the export-compliance answer ships inside the bundle', () {
      expect(
        plist,
        matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
        reason:
            'ios/Runner/Info.plist must declare ITSAppUsesNonExemptEncryption. A build without it '
            'is not rejected, it is simply stuck at Missing Compliance and never reaches testers.',
      );
    });

    test('no app-level crypto dependency makes that "false" answer wrong', () {
      // "false" says the app only hashes and speaks TLS, both exempt. A library that encrypts
      // data itself (or a local database declared encrypted, below) would make it false in the
      // other sense of the word, and the honest answer becomes a self-classification someone has
      // to do deliberately. Fail here instead of at App Review.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      const appLevelCrypto = [
        'encrypt:',
        'pointycastle:',
        'cryptography:',
        'cryptography_flutter:',
        'openpgp:',
        'sodium:',
      ];

      for (final dep in appLevelCrypto) {
        final declared = RegExp('^\\s*$dep', multiLine: true).hasMatch(pubspec);
        expect(
          declared,
          isFalse,
          reason:
              'pubspec.yaml now depends on $dep, so the app encrypts data itself. Revisit '
              'ITSAppUsesNonExemptEncryption in ios/Runner/Info.plist before shipping.',
        );
      }

      final db = File('lib/data/local/app_database.dart').readAsStringSync();
      expect(
        RegExp(r'passphrase|PRAGMA key|sqlcipher', caseSensitive: false).hasMatch(db),
        isFalse,
        reason:
            'the offline database is now encrypted at rest, which is non-exempt encryption. '
            'ITSAppUsesNonExemptEncryption must be revisited.',
      );
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
        'android.permission.RECORD_AUDIO': 'SpeechToText',
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
