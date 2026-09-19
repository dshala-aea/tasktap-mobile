import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';

/// The offer rule, with no database attached.
///
/// `moduleIsOffered` was extracted so the Altro hub could decide whether to draw a tile without
/// awaiting a Drift read on every build. The risk in doing that is the two answers drifting apart,
/// so the rule is tested once here and `EntitlementRepository.hasFeature` now delegates to it
/// rather than restating it.
void main() {
  Entitlement granting(Set<String> features, {String seatType = 'office'}) => Entitlement(
    features: features,
    capabilities: const {},
    seatType: seatType,
    fetchedAt: DateTime.utc(2026, 8, 16),
  );

  group('always-on modules', () {
    // The server enforces these true in code (`ModuleKeys.AlwaysOn`). A client that gated them off
    // would hide screens the backend would happily serve.
    for (final key in const ['clienti', 'team', 'sistema']) {
      test('$key is offered even when the server has never answered', () {
        expect(moduleIsOffered(key, null), isTrue);
      });

      test('$key is offered even when the cached features omit it', () {
        expect(moduleIsOffered(key, granting({'rapportini'})), isTrue);
      });
    }
  });

  group('before the server has ever answered', () {
    // A fresh install with no signal must not be a brick: the three things a field seat exists for
    // are offered unverified, and the server still refuses anything the tenant genuinely lacks.
    for (final key in const ['rapportini', 'presenze', 'interventi']) {
      test('$key is offered on the field-seat baseline', () {
        expect(moduleIsOffered(key, null), isTrue);
      });
    }

    // The paid office modules are the other half of the same rule. Offering them unverified is
    // what the Altro hub used to do for everybody, and it is why a technician on a tenant without
    // Cantieri found out by being refused three taps in.
    for (final key in const ['cantieri', 'contratti', 'magazzino', 'prodotti', 'pianificazione']) {
      test('$key is withheld until the server confirms it', () {
        expect(moduleIsOffered(key, null), isFalse);
      });
    }
  });

  group('once the server has answered', () {
    test('a granted module is offered', () {
      expect(moduleIsOffered('cantieri', granting({'cantieri', 'clienti'})), isTrue);
    });

    test('a module absent from the answer is withheld', () {
      expect(moduleIsOffered('cantieri', granting({'magazzino'})), isFalse);
    });

    test('the cache overrides the baseline in both directions', () {
      // A tenant that dropped Rapportini loses the tile even though it is in the baseline: the
      // baseline only covers the case where nothing is known, never a confirmed denial.
      expect(moduleIsOffered('rapportini', granting({'interventi'})), isFalse);
    });

    test('an unknown key is withheld rather than waved through', () {
      // A typo in a call site must not read as "entitled". It reads as a missing tile, which is
      // visible; the opposite failure is a screen that 403s.
      expect(moduleIsOffered('magazino', granting({'magazzino'})), isFalse);
    });
  });
}
