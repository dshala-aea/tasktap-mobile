// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/auth/access.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';

Entitlement _entitlement({Set<String> capabilities = const {}, String seatType = 'office'}) {
  return Entitlement(
    features: const {},
    capabilities: capabilities,
    seatType: seatType,
    fetchedAt: DateTime.utc(2026, 11, 9),
  );
}

void main() {
  group('capabilityHeld', () {
    test('denies when nothing has ever been cached', () {
      expect(capabilityHeld(null, 'contratti.contract.read'), isFalse);
    });

    test('denies a capability the cached entitlement does not hold', () {
      expect(
        capabilityHeld(
          _entitlement(capabilities: {'contratti.contract.read'}),
          'team.squadra.read',
        ),
        isFalse,
      );
    });

    test('allows a capability the cached entitlement holds', () {
      expect(
        capabilityHeld(
          _entitlement(capabilities: {'contratti.contract.read'}),
          'contratti.contract.read',
        ),
        isTrue,
      );
    });
  });

  group('isOfficeSeat', () {
    test('is false when nothing has ever been cached — office-only stays withheld', () {
      expect(isOfficeSeat(null), isFalse);
    });

    test('is true for an office seat', () {
      expect(isOfficeSeat(_entitlement(seatType: 'office')), isTrue);
    });

    test('is false for a field seat', () {
      expect(isOfficeSeat(_entitlement(seatType: 'field')), isFalse);
    });
  });

  test('the shared refusal copy is stable', () {
    expect(noPermissionReason, 'Non hai i permessi per questa azione.');
    expect(officeOnlyReason, 'Solo ufficio o amministrazione.');
  });
}
