import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/security/biometric_service.dart';
import 'package:tasktap_mobile/features/altro/biometric_setup.dart';
import 'package:tasktap_mobile/features/altro/impostazioni_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBiometricService implements IBiometricService {
  _FakeBiometricService({this.available = true, this.authenticates = true});
  final bool available;
  final bool authenticates;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => authenticates;
}

Widget _wrap(Widget child, {required IBiometricService biometrics}) {
  return ProviderScope(
    overrides: [biometricServiceProvider.overrideWithValue(biometrics)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('enables the lock when the device supports it and verification succeeds', (
    tester,
  ) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          },
        ),
        biometrics: _FakeBiometricService(),
      ),
    );
    await tester.pumpAndSettle();

    final result = await enableBiometricLock(capturedContext, capturedRef);

    expect(result, isTrue);
    expect(capturedRef.read(impostazioniProvider).autenticazioneBiometrica, isTrue);

    // Reading `impostazioniProvider` above lazily constructs `ImpostazioniNotifier`, whose
    // constructor fires an unawaited server reconcile (see impostazioni_provider.dart). Settling
    // here drains that in-flight request before teardown, matching the pattern every other test
    // that touches this provider already relies on (tema_scuro_test.dart, impostazioni_screen_test.dart) —
    // otherwise the test framework flags its pending timer as a leak.
    await tester.pumpAndSettle();
  });

  testWidgets('does not enable the lock when the device has no biometrics enrolled', (
    tester,
  ) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          },
        ),
        biometrics: _FakeBiometricService(available: false),
      ),
    );
    await tester.pumpAndSettle();

    final result = await enableBiometricLock(capturedContext, capturedRef);
    await tester.pump();

    expect(result, isFalse);
    expect(capturedRef.read(impostazioniProvider).autenticazioneBiometrica, isFalse);
    expect(find.textContaining('Nessuna impronta'), findsOneWidget);

    // See the first test's comment: drains the notifier's unawaited server reconcile.
    await tester.pumpAndSettle();
  });

  testWidgets('does not enable the lock when verification fails', (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
            return const SizedBox();
          },
        ),
        biometrics: _FakeBiometricService(authenticates: false),
      ),
    );
    await tester.pumpAndSettle();

    final result = await enableBiometricLock(capturedContext, capturedRef);
    await tester.pump();

    expect(result, isFalse);
    expect(capturedRef.read(impostazioniProvider).autenticazioneBiometrica, isFalse);
    expect(find.textContaining('Verifica non riuscita'), findsOneWidget);

    // See the first test's comment: drains the notifier's unawaited server reconcile.
    await tester.pumpAndSettle();
  });
}
