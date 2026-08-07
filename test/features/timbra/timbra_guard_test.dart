// Tests for the server-guard merge rule (backend ADR-0013 §C.5).
//
// The web client can render `availableActions` directly. This one cannot: it is offline-first,
// so the server's answer is one input among several, and the rule for combining them is where
// the bugs would live. That rule is `resolveGuard`, and these tests are about its judgement
// calls rather than its plumbing:
//
//   - offline must never block the punch (that is most of why the app exists)
//   - a stale server view must not block a punch the local queue already justifies
//   - a payroll lock must block it anyway, because it is not about the queue at all
//
// Pure function, no Riverpod, no Drift, no Dio.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

GiornataDto _giornata({
  String status = 'ClockedOut',
  bool locked = false,
  List<GiornataActionDto> actions = const [],
}) =>
    GiornataDto(
      status: status,
      workedMinutes: 0,
      breakMinutes: 0,
      isPayrollLocked: locked,
      actions: actions,
    );

void main() {
  group('resolveGuard', () {
    test('allows everything when the server could not be reached', () {
      final guard = resolveGuard(
        giornata: null,
        hasPendingSync: false,
        action: 'ClockIn',
      );

      expect(guard.blocked, isFalse);
    });

    test('allows an action the server offers', () {
      final guard = resolveGuard(
        giornata: _giornata(actions: [
          const GiornataActionDto(action: 'ClockIn', enabled: true),
        ]),
        hasPendingSync: false,
        action: 'ClockIn',
      );

      expect(guard.blocked, isFalse);
    });

    test('blocks an action the server refuses, and carries the reason', () {
      final guard = resolveGuard(
        giornata: _giornata(actions: [
          const GiornataActionDto(
            action: 'ClockIn',
            enabled: false,
            reasonCode: 'already_clocked_in',
            reason: 'Sei già in servizio.',
          ),
        ]),
        hasPendingSync: false,
        action: 'ClockIn',
      );

      expect(guard.blocked, isTrue);
      expect(guard.reason, contains('servizio'));
    });

    // The server has not seen what is sitting in the local queue, so its idea of "are you
    // clocked in" is stale by construction. Enforcing it here would refuse a punch the device
    // has every reason to accept.
    test('ignores a stale refusal while events are waiting to sync', () {
      final guard = resolveGuard(
        giornata: _giornata(actions: [
          const GiornataActionDto(
            action: 'ClockOut',
            enabled: false,
            reasonCode: 'not_clocked_in',
            reason: 'Non sei in servizio.',
          ),
        ]),
        hasPendingSync: true,
        action: 'ClockOut',
      );

      expect(guard.blocked, isFalse);
    });

    // ...but a closed payroll period is not about the queue. It is true whatever this device
    // has pending, so it survives the exception above.
    test('still blocks a payroll lock while events are waiting to sync', () {
      final guard = resolveGuard(
        giornata: _giornata(locked: true, actions: [
          const GiornataActionDto(
            action: 'ClockIn',
            enabled: false,
            reasonCode: 'payroll_locked',
            reason: 'Il periodo è chiuso per le buste paga.',
          ),
        ]),
        hasPendingSync: true,
        action: 'ClockIn',
      );

      expect(guard.blocked, isTrue);
      expect(guard.reason, contains('buste paga'));
    });

    test('allows an action the server did not mention at all', () {
      final guard = resolveGuard(
        giornata: _giornata(actions: [
          const GiornataActionDto(action: 'ClockIn', enabled: true),
        ]),
        hasPendingSync: false,
        action: 'Submit',
      );

      expect(guard.blocked, isFalse);
    });

    // A reason code this build predates must still explain itself, using the prose the server
    // sent — otherwise adding a reason server-side silently blanks the message on every phone
    // that has not been updated.
    test('falls back to the server text for an unknown reason code', () {
      final guard = resolveGuard(
        giornata: _giornata(actions: [
          const GiornataActionDto(
            action: 'ClockIn',
            enabled: false,
            reasonCode: 'shift_not_started',
            reason: 'Il turno inizia alle 14:00.',
          ),
        ]),
        hasPendingSync: false,
        action: 'ClockIn',
      );

      expect(guard.blocked, isTrue);
      expect(guard.reason, 'Il turno inizia alle 14:00.');
    });
  });

  group('GiornataDto.fromJson', () {
    test('reads the wire shape the API returns', () {
      final dto = GiornataDto.fromJson({
        'date': '2026-06-15T00:00:00',
        'status': 'Working',
        'activeEntryId': 'wl-1',
        'activeSince': '09:00:00',
        'workedMinutes': 125,
        'breakMinutes': 30,
        'isPayrollLocked': false,
        'availableActions': [
          {'action': 'ClockIn', 'enabled': false, 'reasonCode': 'already_clocked_in', 'reason': 'Sei già in servizio.'},
          {'action': 'ClockOut', 'enabled': true, 'reasonCode': null, 'reason': null},
        ],
      });

      expect(dto.status, 'Working');
      expect(dto.workedMinutes, 125);
      expect(dto.breakMinutes, 30);
      expect(dto.action('ClockOut')?.enabled, isTrue);
      expect(dto.action('ClockIn')?.reasonCode, 'already_clocked_in');
      expect(dto.action('Submit'), isNull);
    });

    test('survives a response missing the fields it can do without', () {
      final dto = GiornataDto.fromJson({'status': 'ClockedOut'});

      expect(dto.workedMinutes, 0);
      expect(dto.isPayrollLocked, isFalse);
      expect(dto.actions, isEmpty);
    });
  });
}
