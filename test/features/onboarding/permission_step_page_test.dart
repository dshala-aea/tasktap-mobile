import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/onboarding/permission_step_page.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('not-yet-decided shows the purpose card with Consenti and Non ora', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.granted,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Posizione'), findsOneWidget);
    expect(find.text('Consenti'), findsOneWidget);
    expect(find.text('Non ora'), findsOneWidget);
  });

  testWidgets('tapping Consenti calls request and shows the granted state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.granted,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Consenti'));
    await tester.pumpAndSettle();

    expect(find.text('Consentito'), findsOneWidget);
    expect(find.text('Consenti'), findsNothing);
  });

  testWidgets('tapping Non ora calls onDone without calling request', (tester) async {
    var requested = false;
    var done = false;
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async {
            requested = true;
            return PermissionStepStatus.granted;
          },
          onDone: () => done = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Non ora'));
    await tester.pumpAndSettle();

    expect(requested, isFalse);
    expect(done, isTrue);
  });

  testWidgets('already granted on checkStatus skips straight to the granted state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.granted,
          request: () async => PermissionStepStatus.granted,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Consentito'), findsOneWidget);
    expect(find.text('Consenti'), findsNothing);
  });

  testWidgets('permanently denied on checkStatus offers Apri impostazioni, not Consenti', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Posizione',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.deniedForever,
          request: () async => PermissionStepStatus.deniedForever,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apri impostazioni'), findsOneWidget);
    expect(find.text('Consenti'), findsNothing);
  });

  testWidgets('request resolving to deniedForever switches the button to Apri impostazioni', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.camera_alt,
          titolo: 'Fotocamera',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti',
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.deniedForever,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Consenti'));
    await tester.pumpAndSettle();

    expect(find.text('Apri impostazioni'), findsOneWidget);
  });

  testWidgets('unavailable shows an explanatory message and no action button', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.fingerprint,
          titolo: 'Blocco biometrico',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Attiva',
          checkStatus: () async => PermissionStepStatus.unavailable,
          request: () async => PermissionStepStatus.unavailable,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attiva'), findsNothing);
    expect(find.text('Non ora'), findsOneWidget); // still a way to move on
  });

  // ── requiresSystemDialog: the App Store 5.1.1 shape ──────────────────────────
  //
  // On these steps the OS dialog *is* the consent screen: it is fired as soon as the page shows,
  // and the app never offers its own allow/deny pair to answer instead.

  testWidgets('system-dialog step fires the OS ask on its own, with no crafted consent', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.notifications,
          titolo: 'Avvisi sul lavoro',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Attiva le notifiche',
          requiresSystemDialog: true,
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async {
            requests++;
            return PermissionStepStatus.granted;
          },
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requests, 1); // asked without a tap
    expect(find.text('Non ora'), findsNothing);
    expect(find.text('Continua'), findsNothing);
  });

  testWidgets('system-dialog step sends a refusal to Apri impostazioni and a plain Continua', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.notifications,
          titolo: 'Avvisi sul lavoro',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Attiva le notifiche',
          requiresSystemDialog: true,
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async {
            requests++;
            return PermissionStepStatus.deniedForever;
          },
          onDone: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.text('Apri impostazioni'), findsOneWidget);
    // "Continua" only exists after the OS answered — it is navigation, never a recorded "Non ora".
    expect(find.text('Continua'), findsOneWidget);
    expect(find.text('Non ora'), findsNothing);
  });

  testWidgets('a system-dialog ask that ends undecided keeps a retry and still no skip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.location_on,
          titolo: 'Dove sei intervenuto',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Consenti la posizione',
          requiresSystemDialog: true,
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => PermissionStepStatus.notDetermined,
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Consenti la posizione'), findsOneWidget); // retry, not a consent of ours
    expect(find.text('Non ora'), findsNothing);
  });

  testWidgets('returning from the system settings re-reads the answer', (tester) async {
    var status = PermissionStepStatus.deniedForever;
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.notifications,
          titolo: 'Avvisi sul lavoro',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Attiva le notifiche',
          requiresSystemDialog: true,
          checkStatus: () async => status,
          request: () async => status,
          onDone: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Apri impostazioni'), findsOneWidget);

    // The technician granted it in Settings while the app was backgrounded.
    status = PermissionStepStatus.granted;
    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Consentito'), findsOneWidget);
    expect(find.text('Apri impostazioni'), findsNothing);
  });

  testWidgets('a request that throws does not strand the page on a spinner', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionStepPage(
          icon: Icons.notifications,
          titolo: 'Avvisi sul lavoro',
          motivo: 'motivo',
          senzaDiEsso: 'senza',
          ctaLabel: 'Attiva le notifiche',
          requiresSystemDialog: true,
          checkStatus: () async => PermissionStepStatus.notDetermined,
          request: () async => throw Exception('channel error'),
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Non disponibile su questo dispositivo.'), findsOneWidget);
    expect(find.text('Continua'), findsOneWidget);
  });
}

/// Drives the real lifecycle channel. `binding.handleAppLifecycleStateChanged` does not reach
/// WidgetsBindingObservers in the test binding, so the page has to be told the way the platform
/// does it (same idiom as `test/core/settings_actually_enforce_test.dart`).
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}
