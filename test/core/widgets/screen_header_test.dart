// dart format width=100
// test/core/widgets/screen_header_test.dart
//
// Both `HeaderIconBtn.glass` and `ScreenHeader.dark` default to false: the fixed-CHARCOAL plate
// they used to assume was under every header/nav surface was never part of the Vetro design the
// app actually agreed on (light frosted glass throughout) — it was a leftover of the pre-Vetro
// "Cassetta" shell metaphor. This locks the light defaults in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/screen_header.dart';

void main() {
  group('HeaderIconBtn', () {
    testWidgets('glass defaults to false — the squared bg3 fill, not the glass disc', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeaderIconBtn(icon: Icons.close, label: 'Chiudi', onTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<HeaderIconBtn>(find.byType(HeaderIconBtn));
      expect(btn.glass, isFalse);

      final container = tester.widget<Container>(
        find.descendant(of: find.byType(HeaderIconBtn), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      // AppRack.insetShape's machined square (radius 8) rather than glass mode's disc radius.
      expect((decoration.borderRadius as BorderRadius?)?.topLeft, const Radius.circular(8));
    });

    testWidgets('glass: true renders the glass variant when explicitly asked for', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeaderIconBtn(icon: Icons.close, label: 'Chiudi', glass: true, onTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<HeaderIconBtn>(find.byType(HeaderIconBtn));
      expect(btn.glass, isTrue);
    });
  });

  group('ScreenHeader', () {
    testWidgets('is light (flipping glass bar) by default', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ScreenHeader(title: 'Test'))));
      await tester.pumpAndSettle();

      final header = tester.widget<ScreenHeader>(find.byType(ScreenHeader));
      expect(header.dark, isFalse);
    });
  });
}
