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

    setUpAll(() {
      gradle = File('android/app/build.gradle.kts').readAsStringSync();
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
