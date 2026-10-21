// dart format width=100
// LogoutFlow — requirement (c) of P0-1: a manual logout with unsent work cannot proceed on the
// generic "Sei sicuro?" confirmation, and "Invia ora" must never sign out while work is still
// stuck (that would be the same silent loss the dialog exists to prevent).
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/altro/logout_flow.dart';

void main() {
  group('prepare', () {
    test('N > 0 requires the explicit, count-naming confirmation', () async {
      final flow = LogoutFlow(
        unsentCount: () async => 7,
        flush: () async {},
        signOut: () async => fail('prepare must not sign out'),
      );

      final prompt = await flow.prepare();

      expect(prompt.requiresConfirmation, isTrue);
      expect(prompt.unsentCount, 7);
    });

    test('N == 0 keeps the generic dialog', () async {
      final flow = LogoutFlow(
        unsentCount: () async => 0,
        flush: () async {},
        signOut: () async => fail('prepare must not sign out'),
      );

      final prompt = await flow.prepare();

      expect(prompt.requiresConfirmation, isFalse);
      expect(prompt.unsentCount, 0);
    });
  });

  group('apply', () {
    test('cancel never signs out and never flushes', () async {
      var flushes = 0;
      var signOuts = 0;
      final flow = LogoutFlow(
        unsentCount: () async => 3,
        flush: () async => flushes++,
        signOut: () async => signOuts++,
      );

      final result = await flow.apply(LogoutIntent.cancel);

      expect(result.signedOut, isFalse);
      expect(flushes, 0);
      expect(signOuts, 0);
    });

    test('signOutAnyway signs out — the technician was shown (and accepted) the count', () async {
      final flow = LogoutFlow(
        unsentCount: () async => 3,
        flush: () async => fail('"Esci comunque" must not send'),
        signOut: () async {},
      );

      final result = await flow.apply(LogoutIntent.signOutAnyway);

      expect(result.signedOut, isTrue);
    });

    test('sendNow signs out only once nothing is left', () async {
      var remaining = 4;
      var signOuts = 0;
      final flow = LogoutFlow(
        unsentCount: () async => remaining,
        flush: () async => remaining = 0,
        signOut: () async => signOuts++,
      );

      final result = await flow.apply(LogoutIntent.sendNow);

      expect(result.signedOut, isTrue);
      expect(signOuts, 1);
    });

    test('sendNow refuses to sign out while work is still stuck, and reports the remainder', () async {
      var signOuts = 0;
      final flow = LogoutFlow(
        unsentCount: () async => 2,
        flush: () async {}, // offline: nothing sent
        signOut: () async => signOuts++,
      );

      final result = await flow.apply(LogoutIntent.sendNow);

      expect(result.signedOut, isFalse);
      expect(result.remaining, 2);
      expect(signOuts, 0, reason: 'logging out here would destroy exactly what failed to send');
    });
  });
}
