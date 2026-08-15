import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_stepper.dart';

/// Progress through a form, said once.
///
/// The stepper used to be numbered discs joined by connector lines, with all four step names
/// printed underneath at 10px. Two rows of chrome to communicate "2 of 4", none of the labels
/// readable, and the labels took `context.colors.ink` while only ever rendering on CHARCOAL — so
/// in light mode they were near-black on near-black.
Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: const Color(0xFF272727),
    body: Padding(padding: const EdgeInsets.all(8), child: child),
  ),
);

const _steps = [
  StepperStep(label: 'Dati'),
  StepperStep(label: 'Staff'),
  StepperStep(label: 'Materiali'),
  StepperStep(label: 'Firme'),
];

void main() {
  group('AppStepper', () {
    testWidgets('names the current step and only the current step', (tester) async {
      // Four 10px captions were four things to read to find out which one you were on.
      await tester.pumpWidget(_wrap(const AppStepper(steps: _steps, currentIndex: 1)));

      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Dati'), findsNothing);
      expect(find.text('Materiali'), findsNothing);
    });

    testWidgets('says how far through it is', (tester) async {
      await tester.pumpWidget(_wrap(const AppStepper(steps: _steps, currentIndex: 2)));

      expect(find.text('3 di 4'), findsOneWidget);
    });

    testWidgets('a visited step can be jumped back to', (tester) async {
      // Correcting the cliente from the summary used to mean pressing Indietro three times.
      var jumped = -1;
      await tester.pumpWidget(
        _wrap(
          AppStepper(steps: _steps, currentIndex: 3, onStepSelected: (i) => jumped = i),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Dati, passo 1'));
      await tester.pumpAndSettle();

      expect(jumped, 0);
    });

    testWidgets('a step not yet reached is not a shortcut', (tester) async {
      // Skipping ahead past required fields is not navigation, it is a way to reach the signature
      // pad with an empty rapportino behind it.
      var jumped = -1;
      await tester.pumpWidget(
        _wrap(
          AppStepper(steps: _steps, currentIndex: 0, onStepSelected: (i) => jumped = i),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Firme, passo 4'));
      await tester.pumpAndSettle();

      expect(jumped, -1);
    });

    testWidgets('paints on-dark colours explicitly rather than through the theme', (tester) async {
      // This bar only ever renders on CHARCOAL. A theme-flipping token here is the bug that has
      // now appeared six times in this codebase, so there is no token to get wrong.
      await tester.pumpWidget(_wrap(const AppStepper(steps: _steps, currentIndex: 1)));

      final label = tester.widget<Text>(find.text('Staff'));
      expect(label.style?.color, const Color(0xFFFFFFFF));
    });
  });
}
