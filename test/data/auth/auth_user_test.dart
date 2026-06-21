import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';

void main() {
  AuthUser makeUser({DateTime? expiresAt}) {
    return AuthUser(
      id: 'user-123',
      email: 'tech@tasktap.io',
      displayName: 'Marco Rossi',
      accessToken: 'token-abc',
      refreshToken: 'refresh-xyz',
      expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  group('AuthUser', () {
    test('isExpired returns false when token is in the future', () {
      final user = makeUser(
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      expect(user.isExpired, isFalse);
    });

    test('isExpired returns true when token is in the past', () {
      final user = makeUser(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      );
      expect(user.isExpired, isTrue);
    });

    test('equality is based on id + accessToken', () {
      final a = makeUser();
      final b = AuthUser(
        id: a.id,
        email: a.email,
        accessToken: a.accessToken,
        refreshToken: 'different-refresh',
        expiresAt: a.expiresAt,
      );
      expect(a, equals(b));
    });

    test('different accessToken means different user', () {
      final a = makeUser();
      final b = AuthUser(
        id: a.id,
        email: a.email,
        accessToken: 'other-token',
        refreshToken: a.refreshToken,
        expiresAt: a.expiresAt,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes id and email', () {
      final user = makeUser();
      expect(user.toString(), contains('user-123'));
      expect(user.toString(), contains('tech@tasktap.io'));
    });
  });
}
