import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/app_stepper.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)));

const _steps = [
  StepperStep(label: 'Dati'),
  StepperStep(label: 'Staff'),
  StepperStep(label: 'Materiali'),
  StepperStep(label: 'Firme'),
];

void main() {
  group('AppStepper', () {
    testWidgets('renders every step label', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStepper(steps: _steps, currentIndex: 1),
      ));
      for (final s in _steps) {
        expect(find.text(s.label), findsOneWidget);
      }
    });

    testWidgets('completed steps before current show a check icon',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStepper(steps: _steps, currentIndex: 2),
      ));
      // Steps 0 and 1 are done → 2 check icons.
      expect(find.byIcon(LucideIcons.check), findsNWidgets(2));
    });

    testWidgets('no checks when on the first step', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStepper(steps: _steps, currentIndex: 0),
      ));
      expect(find.byIcon(LucideIcons.check), findsNothing);
    });

    testWidgets('upcoming and current steps show their 1-based number',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStepper(steps: _steps, currentIndex: 0),
      ));
      // Current (1) + upcoming (2,3,4) are numbered; none are done.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('progressing to the last step checks all prior steps',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStepper(steps: _steps, currentIndex: 3),
      ));
      expect(find.byIcon(LucideIcons.check), findsNWidgets(3));
      expect(find.text('4'), findsOneWidget);
    });
  });
}
