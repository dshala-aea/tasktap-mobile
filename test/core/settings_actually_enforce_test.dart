import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/security/biometric_lock.dart';
import 'package:tasktap_mobile/core/security/biometric_service.dart';

/// Two settings claimed a control they did not have.
///
/// "Geolocalizzazione" wrote a bool nothing read, while `cantiere_timbra_screen` captured a
/// position on every clock-in regardless. "Autenticazione biometrica" offered fingerprint/Face ID
/// unlock with no biometrics package in the project at all.
///
/// A settings switch that reports a choice it does not enforce is worse than no switch: it stops
/// the user looking for a real control, and under a consent audit it is a false statement about
/// processing. These tests assert enforcement, not the presence of a widget.
class _FakeBiometrics implements IBiometricService {
  _FakeBiometrics({this.succeeds = true});

  bool succeeds;
  int prompts = 0;

  // The lock never asks — availability is checked once in Impostazioni, before the setting may be
  // switched on, so by the time the lock exists the device is known to be capable.
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return succeeds;
  }
}

void main() {
  group('the GPS setting gates capture', () {
    ILocationService serviceWith(bool allowed) {
      final container = ProviderContainer(
        overrides: [gpsPreferenceProvider.overrideWithValue(allowed)],
      );
      addTearDown(container.dispose);
      return container.read(locationServiceProvider);
    }

    test('off means no position is ever produced', () async {
      final service = serviceWith(false);

      expect(service, isA<DisabledLocationService>());
      // Null is what every call site already handles as "denied", so the record simply carries no
      // position rather than a fabricated one.
      expect(await service.getCurrentPosition(), isNull);
    });

    test('on uses the real service', () {
      expect(serviceWith(true), isA<LocationService>());
    });

    test('the gate is a single choke point, not a per-call-site check', () {
      // The defect was that honouring the setting depended on every call site remembering it.
      // Resolving the service through the provider is what makes a future call site gated by
      // default rather than by diligence.
      final container = ProviderContainer(
        overrides: [gpsPreferenceProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);

      expect(container.read(locationServiceProvider), isA<DisabledLocationService>());
    });
  });

  group('the biometric setting gates the app', () {
    Future<_FakeBiometrics> pumpLock(
      WidgetTester tester, {
      required bool enabled,
      bool succeeds = true,
    }) async {
      final fake = _FakeBiometrics(succeeds: succeeds);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [biometricServiceProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: BiometricLock(
              enabled: enabled,
              child: const Scaffold(body: Text('dati riservati')),
            ),
          ),
        ),
      );
      await tester.pump();
      return fake;
    }

    testWidgets('off is a pass-through and never prompts', (tester) async {
      final fake = await pumpLock(tester, enabled: false);

      expect(find.text('dati riservati'), findsOneWidget);
      expect(fake.prompts, 0);
    });

    testWidgets('on covers the content until the prompt succeeds', (tester) async {
      final fake = await pumpLock(tester, enabled: true, succeeds: false);
      await tester.pumpAndSettle();

      expect(fake.prompts, greaterThan(0), reason: 'the lock must actually call the platform');
      expect(find.text('TaskTap è bloccato'), findsOneWidget);
    });

    testWidgets('a successful prompt reveals the app', (tester) async {
      await pumpLock(tester, enabled: true);
      await tester.pumpAndSettle();

      expect(find.text('TaskTap è bloccato'), findsNothing);
      expect(find.text('dati riservati'), findsOneWidget);
    });

    testWidgets('the covered child keeps its state rather than being disposed', (tester) async {
      // A running timer or a half-written rapportino must survive being locked, so the lock
      // covers the tree instead of replacing it.
      final fake = await pumpLock(tester, enabled: true, succeeds: false);
      await tester.pumpAndSettle();

      expect(fake.prompts, greaterThan(0));
      expect(
        find.text('dati riservati', skipOffstage: false),
        findsOneWidget,
        reason: 'the child stays in the tree beneath the lock',
      );
    });

    testWidgets('a failed prompt offers a way to retry', (tester) async {
      // A lock with no retry after a dismissed OS prompt is a lock-out.
      await pumpLock(tester, enabled: true, succeeds: false);
      await tester.pumpAndSettle();

      expect(find.text('Sblocca'), findsOneWidget);
    });
  });
}
