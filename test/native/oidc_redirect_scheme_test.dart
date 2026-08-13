import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/config/env.dart';

/// The sign-in callback has to be registered in three places, and any two of them agreeing is
/// worth nothing.
///
/// `flutter_appauth` receives the identity provider's redirect through an activity registered
/// against the `appAuthRedirectScheme` manifest placeholder. Dart names the redirect URI; Gradle
/// names the scheme Android will listen for; Zitadel names the URI it is willing to redirect to.
/// Only the first two live in this repository, so only those two can be checked here — but they
/// were the ones that disagreed: the placeholder was never set at all, so the built app listened
/// for nothing.
///
/// The failure that causes is quiet. The browser completes the sign-in and stops on the last page,
/// the app keeps waiting for a result Android has nowhere to deliver, and nothing reports an
/// error. That is why this could sit in a "code-complete" state through a full review: every Dart
/// unit test passes, because none of them involve Android.
void main() {
  group('OIDC redirect', () {
    late final String gradle;
    late final String manifest;

    setUpAll(() {
      gradle = File('android/app/build.gradle.kts').readAsStringSync();
      manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    });

    test('Android registers the scheme Dart redirects to', () {
      final scheme = Uri.parse(Env.oidcRedirectUri).scheme;

      expect(
        scheme,
        isNotEmpty,
        reason: 'OIDC_REDIRECT_URI must be a custom-scheme URI, e.g. it.tasktap.app://callback',
      );

      final placeholder = RegExp(
        r'''manifestPlaceholders\["appAuthRedirectScheme"\]\s*=\s*"([^"]+)"''',
      ).firstMatch(gradle);

      expect(
        placeholder,
        isNotNull,
        reason: 'android/app/build.gradle.kts must set the appAuthRedirectScheme placeholder — '
            'without it the sign-in callback reaches no activity and login hangs',
      );
      expect(placeholder!.group(1), scheme);
    });

    /// The redirect has to come back to the task that is waiting for it.
    ///
    /// MainActivity carries `android:taskAffinity=""` from Flutter's template. AppAuth's own
    /// activities default to the application id, which is a different task — so the browser's
    /// redirect starts AuthorizationManagementActivity somewhere the pending request is not, and
    /// AppAuth gives up with "No stored state - unable to handle response". The app shows no
    /// error: it simply stays on the login screen having done every other thing correctly.
    test('AppAuth shares MainActivity\'s task affinity', () {
      final mainAffinity = RegExp(
        r'android:name="\.MainActivity"[\s\S]*?android:taskAffinity="([^"]*)"',
      ).firstMatch(manifest);

      // Nothing to align if the template ever stops setting it — the defaults then agree already.
      if (mainAffinity == null) return;

      for (final activity in const [
        'net.openid.appauth.RedirectUriReceiverActivity',
        'net.openid.appauth.AuthorizationManagementActivity',
      ]) {
        // Bounded to the one <activity … /> element. Scanning further than its closing bracket
        // finds the NEXT activity's affinity and calls a missing attribute a match — which is
        // exactly what this test did on its first run, passing against a manifest with the
        // attribute deleted.
        final element = RegExp(
          '<activity[^>]*android:name="${RegExp.escape(activity)}"[^>]*/>',
        ).firstMatch(manifest);

        expect(
          element,
          isNotNull,
          reason: '$activity must be declared in the app manifest so its task affinity can be '
              'aligned with MainActivity',
        );

        final declared =
            RegExp(r'android:taskAffinity="([^"]*)"').firstMatch(element!.group(0)!);

        expect(
          declared,
          isNotNull,
          reason: '$activity must declare a taskAffinity matching MainActivity, or the sign-in '
              'redirect lands in a second task and AppAuth reports "No stored state"',
        );
        expect(declared!.group(1), mainAffinity.group(1), reason: activity);
      }
    });

    /// A scheme has to be globally unique on the device: a second app claiming it can intercept
    /// the authorization code. Reverse-DNS is the convention that makes that unlikely.
    test('the scheme is reverse-DNS, not a bare word', () {
      final scheme = Uri.parse(Env.oidcRedirectUri).scheme;

      expect(scheme.contains('.'), isTrue, reason: 'scheme was "$scheme"');
      expect(scheme, isNot(equals('http')));
      expect(scheme, isNot(equals('https')));
    });
  });
}
