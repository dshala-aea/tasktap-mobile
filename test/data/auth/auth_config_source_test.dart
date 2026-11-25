// dart format width=100
import 'package:flutter_test/flutter_test.dart';
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
        issuer: 'https://id.new.test',
        clientId: 'client-new',
        redirectUri: 'app.tasktap://callback',
      ),
    ).load();

    expect(cfg.issuer, 'https://id.new.test');
    expect(cfg.clientId, 'client-new');
    expect(cfg.fromServer, isTrue);
  });

  test('the issuer is normalised (trimmed, no trailing slash)', () async {
    final cfg = await _withAuth(
      const ServerAuthConfig(issuer: ' https://id.new.test/ ', clientId: 'c'),
    ).load();
    expect(cfg.issuer, 'https://id.new.test');
  });

  test('no policy cached, or no auth block: dart-defines', () async {
    expect((await _source(() async => null).load()).issuer, 'https://define.test');
    final cfg = await _withAuth(null).load();
    expect(cfg.issuer, 'https://define.test');
    expect(cfg.fromServer, isFalse);
  });

  for (final bad in <String, ServerAuthConfig>{
    'missing issuer': const ServerAuthConfig(clientId: 'c'),
    'missing clientId': const ServerAuthConfig(issuer: 'https://id.new.test'),
    'blank clientId': const ServerAuthConfig(issuer: 'https://id.new.test', clientId: '  '),
    'http issuer': const ServerAuthConfig(issuer: 'http://id.new.test', clientId: 'c'),
    'not a URL': const ServerAuthConfig(issuer: 'id.new.test', clientId: 'c'),
    'custom scheme issuer': const ServerAuthConfig(issuer: 'app://id.new.test', clientId: 'c'),
    'issuer with user-info': const ServerAuthConfig(issuer: 'https://a@id.new.test', clientId: 'c'),
    'issuer with query': const ServerAuthConfig(issuer: 'https://id.new.test?x=1', clientId: 'c'),
  }.entries) {
    test('falls back to the dart-defines on ${bad.key} (never mixes the two)', () async {
      final cfg = await _withAuth(bad.value).load();
      expect(cfg.issuer, 'https://define.test');
      expect(cfg.clientId, 'client-define');
      expect(cfg.fromServer, isFalse);
    });
  }

  group('redirectUri', () {
    Future<String> redirectFor(String? server) async => (await _withAuth(
      ServerAuthConfig(issuer: 'https://id.new.test', clientId: 'c', redirectUri: server),
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
      'auth': {'issuer': 'https://id.new.test', 'clientId': 'c', 'redirectUri': 'x://y'},
    });
    final again = AppVersionPolicy.fromJson(policy.toJson());
    expect(again.auth?.issuer, 'https://id.new.test');
    expect(again.auth?.clientId, 'c');

    expect(AppVersionPolicy.fromJson({'minimumVersion': '1.0.0'}).auth, isNull);
    expect(AppVersionPolicy.fromJson({'auth': 'garbage'}).auth, isNull);
  });
}
