import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_checkbox.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppCheckbox', () {
    testWidgets('the box stays square: 48 dp of target, not a 24 x 48 sliver', (tester) async {
      await tester.pumpWidget(
        _wrap(AppCheckbox(value: false, label: 'Controllo scarico condensa', onChanged: (_) {})),
      );

      // The rhcu regression: `ConstrainedBox(minHeight: 48)` stretched the 24 dp square into a
      // tall rectangle, which read on screen as a broken image rather than a checkbox.
      final box = tester.getSize(
        find.descendant(of: find.byType(AppCheckbox), matching: find.byType(Container)),
      );
      expect(box.width, 24);
      expect(box.height, 24);
    });

    testWidgets('the label sits to the right of the box, on the same line', (tester) async {
      await tester.pumpWidget(
        _wrap(AppCheckbox(value: false, label: 'Controllo scarico condensa', onChanged: (_) {})),
      );

      final boxRect = tester.getRect(
        find.descendant(of: find.byType(AppCheckbox), matching: find.byType(Container)),
      );
      final labelRect = tester.getRect(find.text('Controllo scarico condensa'));
      expect(labelRect.left, greaterThan(boxRect.right));
      expect(labelRect.top, lessThan(boxRect.bottom), reason: 'one row, not a caption underneath');
    });

    testWidgets('the row keeps a 48 dp tap target', (tester) async {
      await tester.pumpWidget(_wrap(AppCheckbox(value: false, label: 'Voce', onChanged: (_) {})));

      expect(tester.getSize(find.byType(AppCheckbox)).height, greaterThanOrEqualTo(48));
    });

    testWidgets('tapping the label ticks the box too', (tester) async {
      bool? received;
      await tester.pumpWidget(
        _wrap(AppCheckbox(value: false, label: 'Voce', onChanged: (v) => received = v)),
      );

      await tester.tap(find.text('Voce'));
      expect(received, isTrue);
    });

    testWidgets('the required marker is drawn after the label', (tester) async {
      await tester.pumpWidget(
        _wrap(AppCheckbox(value: false, label: 'Voce', isRequired: true, onChanged: (_) {})),
      );

      expect(find.text('*'), findsOneWidget);
      expect(
        tester.getRect(find.text('*')).left,
        greaterThan(tester.getRect(find.text('Voce')).right),
      );
    });

    testWidgets('a box with no label renders as the square alone', (tester) async {
      await tester.pumpWidget(_wrap(AppCheckbox(value: true, onChanged: (_) {})));

      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(AppCheckbox)).width, 24);
    });
  });
}
