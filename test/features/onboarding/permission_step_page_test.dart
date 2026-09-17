import 'package:flutter/material.dart';
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
}
