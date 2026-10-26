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
    // The 250 ms page transition, then one more frame. The step reads the OS status from
    // `initState`, so the frame the transition lands on is still the loading spinner — the answer
    // only reaches a build after that read completes. Settling here would work today too, but
    // only because the granted step's auto-advance is a Timer rather than a scheduled frame;
    // this sequence does not lean on that.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Dove sei intervenuto'), findsOneWidget);
  });

  testWidgets('a granted Location step advances itself to the Notifiche step', (tester) async {
    await tester.pumpWidget(_wrap('user-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();
    // The granted step leaves by itself after a short beat. That is a Timer, and settling runs no
    // clock — so the beat has to be advanced explicitly before the transition it starts can be
    // settled, along with the Notifiche step's own status read.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('Avvisi sul lavoro'), findsOneWidget);
    // Firebase is not initialised in tests, so the Notifiche step is in its unavailable state: no
    // OS dialog to offer, and a plain "Continua" is the only action — never a consent screen.
    expect(find.text('Non disponibile su questo dispositivo.'), findsOneWidget);
    expect(find.text('Non ora'), findsNothing);
  });
}
