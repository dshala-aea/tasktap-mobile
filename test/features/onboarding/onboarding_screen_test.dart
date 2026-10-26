import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_screen.dart';

class _GrantingLocationService extends ILocationService {
  const _GrantingLocationService();

  @override
  Future<GpsCoords?> getCurrentPosition() async => (lat: 0.0, lng: 0.0, accuracy: null);

  @override
  Future<GpsPermissionStatus> permissionStatus() async => GpsPermissionStatus.granted;
}

Widget _wrap(String userId) {
  return ProviderScope(
    overrides: [
      locationServiceProvider.overrideWithValue(const _GrantingLocationService()),
    ],
    child: MaterialApp(home: OnboardingScreen(userId: userId)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the welcome page first', (tester) async {
    await tester.pumpWidget(_wrap('user-1'));
    await tester.pumpAndSettle();

    expect(find.text('Inizia'), findsOneWidget);
  });

  testWidgets('Inizia advances to the Location step', (tester) async {
    await tester.pumpWidget(_wrap('user-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    // The page transition only. A full settle would run past this page: location is already
    // granted here, and a granted step advances itself after a short beat.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Dove sei intervenuto'), findsOneWidget);
  });

  testWidgets('a granted Location step advances itself to the Notifiche step', (tester) async {
    await tester.pumpWidget(_wrap('user-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();

    expect(find.text('Avvisi sul lavoro'), findsOneWidget);
    // Firebase is not initialised in tests, so the Notifiche step is in its unavailable state: no
    // OS dialog to offer, and a plain "Continua" is the only action — never a consent screen.
    expect(find.text('Non disponibile su questo dispositivo.'), findsOneWidget);
    expect(find.text('Non ora'), findsNothing);
  });
}
