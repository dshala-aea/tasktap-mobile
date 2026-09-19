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
        reason:
            'android/app/build.gradle.kts must set the appAuthRedirectScheme placeholder — '
            'without it the sign-in callback reaches no activity and login hangs',
      );
      expect(placeholder!.group(1), scheme);
    });

    /// The redirect has to come back to the task that is waiting for it.
    ///
    /// AppAuth's AuthorizationManagementActivity is `launchMode="singleTask"`, and a singleTask
    /// activity is placed in the task matching its affinity. An activity with an EMPTY affinity
    /// belongs to no task, so Android gives it a fresh one each launch — the instance holding the
    /// pending authorization request is never the instance that receives the browser's redirect,
    /// and AppAuth reports "No stored state - unable to handle response". The app shows no error;
    /// it stays on the login screen.
    ///
    /// Flutter's template puts `android:taskAffinity=""` on MainActivity to stop another app
    /// claiming this one's task. It cannot stay while AppAuth is in use, and giving AppAuth the
    /// same empty affinity does not rescue it — emptiness is what breaks singleTask.
    test('MainActivity does not strip the task affinity AppAuth needs', () {
      final element = RegExp(
        r'<activity[\s\S]*?android:name="\.MainActivity"[\s\S]*?>',
      ).firstMatch(manifest);
      expect(element, isNotNull, reason: 'MainActivity must be declared');

      final affinity = RegExp(r'android:taskAffinity="([^"]*)"').firstMatch(element!.group(0)!);

      if (affinity == null) return; // Default affinity — the application id. Correct.

      expect(
        affinity.group(1),
        isNotEmpty,
        reason:
            'an empty taskAffinity puts AppAuth\'s singleTask activity in a new task every '
            'time, so the sign-in response arrives where no request is stored',
      );

      // A non-default affinity is allowed, but AppAuth has to be moved onto it too.
      for (final activity in const [
        'net.openid.appauth.RedirectUriReceiverActivity',
        'net.openid.appauth.AuthorizationManagementActivity',
      ]) {
        final appAuth = RegExp(
          '<activity[^>]*android:name="${RegExp.escape(activity)}"[^>]*/>',
        ).firstMatch(manifest);

        expect(appAuth, isNotNull, reason: '$activity must be declared to share that affinity');
        expect(
          RegExp(r'android:taskAffinity="([^"]*)"').firstMatch(appAuth!.group(0)!)?.group(1),
          affinity.group(1),
          reason: activity,
        );
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
