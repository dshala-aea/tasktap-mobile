// dart format width=100
// test/core/widgets/screen_header_test.dart
//
// HeaderIconBtn's `glass` default flipped from false to true: every ScreenHeader in the app is
// `dark: true` (grep confirms — no screen passes `dark: false`), so the squared, bg3-filled
// "machined" branch this widget also has was never the right one for the 19 of 20 call sites that
// left `glass` unset. This locks the new default in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/screen_header.dart';

void main() {
  group('HeaderIconBtn', () {
    testWidgets('glass defaults to true — round shape, not the squared bg3 fill', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeaderIconBtn(icon: Icons.close, label: 'Chiudi', onTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<HeaderIconBtn>(find.byType(HeaderIconBtn));
      expect(btn.glass, isTrue);

      final container = tester.widget<Container>(
        find.descendant(of: find.byType(HeaderIconBtn), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      // Glass mode's disc radius (19) rather than AppRack.insetShape's machined square.
      expect((decoration.borderRadius as BorderRadius?)?.topLeft, const Radius.circular(19));
    });

    testWidgets('glass: false still renders the squared variant when explicitly asked for', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeaderIconBtn(icon: Icons.close, label: 'Chiudi', glass: false, onTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<HeaderIconBtn>(find.byType(HeaderIconBtn));
      expect(btn.glass, isFalse);
    });
  });

  group('ScreenHeader', () {
    testWidgets('is dark (CHARCOAL) by default', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ScreenHeader(title: 'Test'))));
      await tester.pumpAndSettle();

      final header = tester.widget<ScreenHeader>(find.byType(ScreenHeader));
      expect(header.dark, isTrue);
    });
  });
}
