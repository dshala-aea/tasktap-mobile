// One welcome page. The five-step permission wizard is gone: only notifications is worth asking
// for before the technician needs it; location, camera and microphone prompt themselves the
// first time the capability is used, and biometric unlock is opt-in in Impostazioni.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_provider.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_screen.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_notification_ask.dart';

class _RecordingNotifier extends OnboardingCompletedNotifier {
  _RecordingNotifier(super.arg);

  int completions = 0;

  @override
  Future<void> markCompleted() async {
    completions++;
    state = const AsyncData(true);
  }
}

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

  ({Widget widget, ProviderContainer container, _SpyLocationService location})
  build({List<Override> overrides = const []}) {
    final location = _SpyLocationService();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        ...overrides,
      ],
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

  testWidgets('the welcome offers Inizia and asks nothing else', (
    tester,
  ) async {
    final built = build();
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    expect(find.text('Benvenuto in TaskTap'), findsOneWidget);
    expect(find.text('Inizia'), findsOneWidget);

    // Firebase is not initialised in tests, so notifications report themselves unavailable
    // rather than offering an OS dialog — the same copy the wizard used.
    expect(find.text('Non disponibile su questo dispositivo.'), findsOneWidget);
  });

  testWidgets('opening the welcome raises no location request', (tester) async {
    final built = build();
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    expect(built.location.calls, 0);
  });

  testWidgets('a notification request that throws is not an unhandled error', (
    tester,
  ) async {
    final location = _SpyLocationService();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        onboardingNotificationAskProvider.overrideWithValue(
          () async => throw Exception('channel error'),
        ),
        notificationAvailableProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen(userId: 'user-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Attiva le notifiche'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Non è stato possibile attivare le notifiche. Riprova.'),
      findsOneWidget,
    );
    // The action stays available to retry.
    expect(find.text('Attiva le notifiche'), findsOneWidget);
  });

  testWidgets(
    'an already-granted device shows the granted state, not the ask',
    (tester) async {
      final built = build(
        overrides: [
          notificationAvailableProvider.overrideWithValue(true),
          onboardingNotificationStatusProvider.overrideWithValue(
            () async => AuthorizationStatus.authorized,
          ),
        ],
      );
      await tester.pumpWidget(built.widget);
      await tester.pumpAndSettle();

      expect(find.text('Notifiche attive.'), findsOneWidget);
      expect(find.text('Attiva le notifiche'), findsNothing);
    },
  );

  testWidgets(
    'a denied device is pointed at Impostazioni instead of a dead button',
    (tester) async {
      final built = build(
        overrides: [
          notificationAvailableProvider.overrideWithValue(true),
          onboardingNotificationStatusProvider.overrideWithValue(
            () async => AuthorizationStatus.denied,
          ),
        ],
      );
      await tester.pumpWidget(built.widget);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Le notifiche sono disattivate. Puoi attivarle da Impostazioni.',
        ),
        findsOneWidget,
      );
      expect(find.text('Apri Impostazioni'), findsOneWidget);
      expect(find.text('Attiva le notifiche'), findsNothing);
    },
  );

  testWidgets('a device never asked gets the ask', (tester) async {
    final built = build(
      overrides: [
        notificationAvailableProvider.overrideWithValue(true),
        onboardingNotificationStatusProvider.overrideWithValue(
          () async => AuthorizationStatus.notDetermined,
        ),
      ],
    );
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    expect(find.text('Attiva le notifiche'), findsOneWidget);
  });

  testWidgets('a second tap on Inizia completes once', (tester) async {
    final notifier = _RecordingNotifier('user-1');
    final built = build(
      overrides: [onboardingCompletedProvider.overrideWith2((_) => notifier)],
    );
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inizia'));
    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();

    expect(notifier.completions, 1);
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

  testWidgets('a second tap on Inizia does not fail or double-complete', (
    tester,
  ) async {
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
