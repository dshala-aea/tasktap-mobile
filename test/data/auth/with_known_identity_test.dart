import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/auth/zitadel_auth_repository.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';

AuthUser _user({String id = '', String email = '', String? name, String access = 'a', String refresh = 'r'}) =>
    AuthUser(
      id: id,
      email: email,
      displayName: name,
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.utc(2030),
    );

void main() {
  group('withKnownIdentity', () {
    test('an id-less refresh keeps the known identity but takes the fresh tokens', () {
      final fresh = _user(access: 'new-access', refresh: 'new-refresh');
      final known = _user(id: 'sub-1', email: 'a@b.it', name: 'Mario');

      final merged = ZitadelAuthRepository.withKnownIdentity(fresh, known);

      expect(merged.id, 'sub-1');
      expect(merged.email, 'a@b.it');
      expect(merged.displayName, 'Mario');
      expect(merged.accessToken, 'new-access');
      expect(merged.refreshToken, 'new-refresh');
    });

    test('a refresh that has an id is returned untouched', () {
      final fresh = _user(id: 'sub-2', email: 'x@y.it');
      expect(identical(ZitadelAuthRepository.withKnownIdentity(fresh, _user(id: 'sub-1')), fresh), isTrue);
    });

    test('with nothing known the fresh user is returned as is', () {
      final fresh = _user();
      expect(identical(ZitadelAuthRepository.withKnownIdentity(fresh, null), fresh), isTrue);
    });
  });
}
