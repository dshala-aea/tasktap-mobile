// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/config/issuer_allowlist.dart';
import 'package:tasktap_mobile/core/update/app_version_policy_repository.dart';
import 'package:tasktap_mobile/data/api/app_version_policy_api.dart';
import 'package:tasktap_mobile/data/auth/auth_config_source.dart';

const _defines = AuthConfig(
  issuer: 'https://define.test',
  clientId: 'client-define',
  redirectUri: 'app.tasktap://callback',
);

AuthConfigSource _source(Future<AppVersionPolicy?> Function() read) =>
    AuthConfigSource(compileTime: _defines, readPolicy: read);

AuthConfigSource _withAuth(ServerAuthConfig? auth) =>
    _source(() async => AppVersionPolicy(auth: auth));

void main() {
  test('current is the dart-defines before the first load', () {
    expect(_withAuth(null).current.issuer, 'https://define.test');
  });

  test('a valid server config wins over the dart-defines', () async {
    final cfg = await _withAuth(
      const ServerAuthConfig(
        issuer: 'https://id.advantedgeautomation.com',
        clientId: 'client-new',
        redirectUri: 'app.tasktap://callback',
      ),
    ).load();

    expect(cfg.issuer, 'https://id.advantedgeautomation.com');
    expect(cfg.clientId, 'client-new');
    expect(cfg.fromServer, isTrue);
  });

  test('the issuer is normalised (trimmed, no trailing slash)', () async {
    final cfg = await _withAuth(
      const ServerAuthConfig(issuer: ' https://id.advantedgeautomation.com/ ', clientId: 'c'),
    ).load();
    expect(cfg.issuer, 'https://id.advantedgeautomation.com');
  });

  test('no policy cached, or no auth block: dart-defines', () async {
    expect((await _source(() async => null).load()).issuer, 'https://define.test');
    final cfg = await _withAuth(null).load();
    expect(cfg.issuer, 'https://define.test');
    expect(cfg.fromServer, isFalse);
  });

  for (final bad in <String, ServerAuthConfig>{
    'missing issuer': const ServerAuthConfig(clientId: 'c'),
    'missing clientId': const ServerAuthConfig(issuer: 'https://id.advantedgeautomation.com'),
    'blank clientId': const ServerAuthConfig(issuer: 'https://id.advantedgeautomation.com', clientId: '  '),
    'http issuer': const ServerAuthConfig(issuer: 'http://id.advantedgeautomation.com', clientId: 'c'),
    'not a URL': const ServerAuthConfig(issuer: 'id.advantedgeautomation.com', clientId: 'c'),
    'custom scheme issuer': const ServerAuthConfig(issuer: 'app://id.advantedgeautomation.com', clientId: 'c'),
    'issuer with user-info': const ServerAuthConfig(issuer: 'https://a@id.advantedgeautomation.com', clientId: 'c'),
    'issuer with query': const ServerAuthConfig(issuer: 'https://id.advantedgeautomation.com?x=1', clientId: 'c'),
  }.entries) {
    test('falls back to the dart-defines on ${bad.key} (never mixes the two)', () async {
      final cfg = await _withAuth(bad.value).load();
      expect(cfg.issuer, 'https://define.test');
      expect(cfg.clientId, 'client-define');
      expect(cfg.fromServer, isFalse);
    });
  }

  group('host allow-list', () {
    Future<AuthConfig> load(String issuer, {List<String>? extra, AuthConfig? defines}) =>
        AuthConfigSource(
          compileTime: defines ?? _defines,
          extraSuffixes: extra,
          readPolicy: () async =>
              AppVersionPolicy(auth: ServerAuthConfig(issuer: issuer, clientId: 'c')),
        ).load();

    for (final bad in [
      'https://evil.example',
      'https://evilid.advantedgeautomation.com.evil.example',
      'https://advantedgeautomation.com.evil.example',
      'https://notadvantedgeautomation.com',
      'https://id.advantedgeautomation.com:8443',
      'https://127.0.0.1',
      'https://[::1]',
    ]) {
      test('rejects $bad -> dart-defines', () async {
        final cfg = await load(bad);
        expect(cfg.issuer, 'https://define.test');
        expect(cfg.fromServer, isFalse);
      });
    }

    for (final good in [
      'https://id.advantedgeautomation.com',
      'https://advantedgeautomation.com',
      'https://auth.tasktap.it',
      'https://ID.AdvantEdgeAutomation.COM',
      'https://id.advantedgeautomation.com:443',
      'https://define.test',
      'https://sub.define.test',
    ]) {
      test('accepts $good', () async {
        final cfg = await load(good);
        expect(cfg.fromServer, isTrue);
        expect(cfg.issuer, cfg.issuer.toLowerCase().replaceAll(RegExp(r'/$'), ''));
      });
    }

    test('the host is lowercased in the resolved issuer', () async {
      expect((await load('https://ID.TaskTap.IT/')).issuer, 'https://id.tasktap.it');
    });

    test('the OIDC_ISSUER_ALLOWED_SUFFIXES list extends the allow-list', () async {
      expect((await load('https://idp.partner.example', extra: ['partner.example'])).fromServer,
          isTrue);
      expect((await load('https://idp.partner.example')).fromServer, isFalse);
      expect(parseIssuerSuffixes(' A.Example, ,.b.example ,'), ['a.example', 'b.example']);
    });

    test('a previously cached bad block is ignored on read', () async {
      final cfg = await load('https://evil.example');
      expect(cfg.issuer, _defines.issuer);
      expect(cfg.clientId, _defines.clientId);
    });

    test('the policy repository does not persist a bad auth block', () {
      const bad = AppVersionPolicy(
        minimumVersion: '1.0.0',
        auth: ServerAuthConfig(issuer: 'https://evil.example', clientId: 'c'),
      );
      const good = AppVersionPolicy(
        auth: ServerAuthConfig(issuer: 'https://id.advantedgeautomation.com', clientId: 'c'),
      );
      final stripped = AppVersionPolicyRepository.withAllowedAuth(bad);
      expect(stripped.auth, isNull);
      expect(stripped.minimumVersion, '1.0.0');
      expect(AppVersionPolicyRepository.withAllowedAuth(good).auth?.clientId, 'c');
    });
  });

  group('redirectUri', () {
    Future<String> redirectFor(String? server) async => (await _withAuth(
      ServerAuthConfig(issuer: 'https://id.advantedgeautomation.com', clientId: 'c', redirectUri: server),
    ).load()).redirectUri;

    test('absent: compiled value', () async {
      expect(await redirectFor(null), 'app.tasktap://callback');
    });

    test('same scheme: honoured', () async {
      expect(await redirectFor('APP.tasktap://callback/v2'), 'APP.tasktap://callback/v2');
    });

    test('a different scheme is ignored (the native scheme is compile-time)', () async {
      expect(await redirectFor('evil.app://callback'), 'app.tasktap://callback');
      expect(await redirectFor('https://x.test/cb'), 'app.tasktap://callback');
    });
  });

  test('a throwing or hanging cache falls back to the dart-defines', () async {
    expect((await _source(() async => throw StateError('prefs')).load()).issuer,
        'https://define.test');
    final slow = AuthConfigSource(
      compileTime: _defines,
      readPolicy: () => Future<AppVersionPolicy?>.delayed(const Duration(seconds: 1)),
      readTimeout: const Duration(milliseconds: 10),
    );
    expect((await slow.load()).issuer, 'https://define.test');
  });

  test('the policy cache round-trips the auth block and tolerates caches without one', () {
    final policy = AppVersionPolicy.fromJson({
      'minimumVersion': '1.0.0',
      'auth': {'issuer': 'https://id.advantedgeautomation.com', 'clientId': 'c', 'redirectUri': 'x://y'},
    });
    final again = AppVersionPolicy.fromJson(policy.toJson());
    expect(again.auth?.issuer, 'https://id.advantedgeautomation.com');
    expect(again.auth?.clientId, 'c');

    expect(AppVersionPolicy.fromJson({'minimumVersion': '1.0.0'}).auth, isNull);
    expect(AppVersionPolicy.fromJson({'auth': 'garbage'}).auth, isNull);
  });
}
