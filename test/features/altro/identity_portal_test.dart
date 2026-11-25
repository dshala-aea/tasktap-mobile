// "Gestisci passkey e account": opens the identity service (the issuer root) in the browser, https
// only. The exact account page path is an open decision (see identity_portal.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/api/app_version_policy_api.dart';
import 'package:tasktap_mobile/data/auth/auth_config_source.dart';
import 'package:tasktap_mobile/features/altro/identity_portal.dart';

AuthConfigSource _source(String issuer, {ServerAuthConfig? server}) => AuthConfigSource(
  compileTime: AuthConfig(issuer: issuer, clientId: 'c', redirectUri: 'app.tasktap://callback'),
  readPolicy: () async => AppVersionPolicy(auth: server),
);

void main() {
  group('resolveIdentityPortalUri', () {
    test('is the configured https issuer', () async {
      final uri = await resolveIdentityPortalUri(_source('https://id.advantedgeautomation.com'));
      expect(uri, Uri.parse('https://id.advantedgeautomation.com'));
    });

    test('follows the server-provided issuer', () async {
      final uri = await resolveIdentityPortalUri(
        _source(
          'https://auth.tasktap.it',
          server: const ServerAuthConfig(
            issuer: 'https://id.advantedgeautomation.com',
            clientId: 'client-new',
            redirectUri: 'app.tasktap://callback',
          ),
        ),
      );
      expect(uri?.host, 'id.advantedgeautomation.com');
    });

    test('is null for a non-https issuer', () async {
      expect(await resolveIdentityPortalUri(_source('http://auth.tasktap.it')), isNull);
    });

    test('is null when no issuer is configured', () async {
      expect(await resolveIdentityPortalUri(_source('')), isNull);
    });
  });

  group('openIdentityPortal', () {
    test('launches the resolved URL', () async {
      Uri? launched;
      final ok = await openIdentityPortal(
        resolve: () async => Uri.parse('https://id.example.test'),
        launch: (uri) async {
          launched = uri;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(launched, Uri.parse('https://id.example.test'));
    });

    test('never launches when there is no safe URL', () async {
      var launches = 0;
      final ok = await openIdentityPortal(
        resolve: () async => null,
        launch: (uri) async {
          launches++;
          return true;
        },
      );
      expect(ok, isFalse);
      expect(launches, 0);
    });

    test('reports a failed launch', () async {
      final ok = await openIdentityPortal(
        resolve: () async => Uri.parse('https://id.example.test'),
        launch: (_) async => false,
      );
      expect(ok, isFalse);
    });
  });
}
