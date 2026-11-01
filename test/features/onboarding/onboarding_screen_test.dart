// One welcome page. The five-step permission wizard is gone: only notifications is worth asking
// for before the technician needs it; location, camera and microphone prompt themselves the
// first time the capability is used, and biometric unlock is opt-in in Impostazioni.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_provider.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_screen.dart';

class _SpyLocationService extends ILocationService {
  int calls = 0;

  @override
  Future<GpsCoords?> getCurrentPosition() async {
    calls++;
    return null;
  }

  @override
  Future<GpsPermissionStatus> permissionStatus() async {
    calls++;
    return GpsPermissionStatus.granted;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ({Widget widget, ProviderContainer container, _SpyLocationService location}) build() {
    final location = _SpyLocationService();
    final container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(location)],
    );
    addTearDown(container.dispose);
    return (
      widget: UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen(userId: 'user-1')),
      ),
      container: container,
      location: location,
    );
  }

  testWidgets('the welcome offers Inizia and asks nothing else', (tester) async {
    final built = build();
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    expect(find.text('Benvenuto in TaskTap'), findsOneWidget);
    expect(find.text('Inizia'), findsOneWidget);

    // Firebase is not initialised in tests, so notifications report themselves unavailable
    // rather than offering an OS dialog — the same copy the wizard used.
    expect(find.text('Non disponibile su questo dispositivo.'), findsOneWidget);
  });

  testWidgets('opening the welcome raises no location prompt', (tester) async {
    final built = build();
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    expect(built.location.calls, 0);
  });

  testWidgets('Inizia completes onboarding for the user', (tester) async {
    final built = build();
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();

    expect(
      await built.container.read(onboardingCompletedProvider('user-1').future),
      isTrue,
    );
  });

  testWidgets('a second tap on Inizia does not fail or double-complete', (tester) async {
    final built = build();
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();

    expect(
      await built.container.read(onboardingCompletedProvider('user-1').future),
      isTrue,
    );
  });
}
