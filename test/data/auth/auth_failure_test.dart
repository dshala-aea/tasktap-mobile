import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';

void main() {
  group('authFailureMessage — Italian error strings', () {
    test('InvalidCredentials returns email/password message', () {
      const failure = InvalidCredentials();
      final msg = authFailureMessage(failure);
      expect(msg, contains('Email o password errati'));
    });

    test('AccountDisabled returns disabled message', () {
      const failure = AccountDisabled();
      final msg = authFailureMessage(failure);
      expect(msg, contains('disabilitato'));
    });

    test('EmailNotFound returns not-found message', () {
      const failure = EmailNotFound();
      final msg = authFailureMessage(failure);
      expect(msg, contains('Nessun account'));
    });

    test('TooManyRequests returns rate-limit message', () {
      const failure = TooManyRequests();
      final msg = authFailureMessage(failure);
      expect(msg, contains('Troppi tentativi'));
    });

    test('NetworkError returns connectivity message', () {
      const failure = NetworkError();
      final msg = authFailureMessage(failure);
      expect(msg, contains('connessione'));
    });

    test('SessionExpired returns session message', () {
      const failure = SessionExpired();
      final msg = authFailureMessage(failure);
      expect(msg, contains('scaduta'));
    });

    test('UnknownAuthError includes the raw message', () {
      const failure = UnknownAuthError('boom');
      final msg = authFailureMessage(failure);
      expect(msg, contains('boom'));
    });

    test('AdditionalFactorRequired returns a verification-needed message', () {
      expect(
        authFailureMessage(const AdditionalFactorRequired()),
        'Serve una verifica aggiuntiva. Accedi dal browser per continuare.',
      );
    });

    test('all failure types return non-empty Italian strings', () {
      final failures = <AuthFailure>[
        const InvalidCredentials(),
        const AccountDisabled(),
        const EmailNotFound(),
        const TooManyRequests(),
        const NetworkError(),
        const SessionExpired(),
        const UnknownAuthError('test'),
      ];
      for (final f in failures) {
        final msg = authFailureMessage(f);
        expect(msg, isNotEmpty, reason: '$f produced empty string');
      }
    });
  });
}
