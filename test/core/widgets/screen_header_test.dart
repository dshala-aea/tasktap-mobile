// dart format width=100
// test/core/widgets/screen_header_test.dart
//
// ScreenHeader always renders as the flipping flat Documento bar — the fixed-CHARCOAL `dark`
// plate it used to optionally render (a leftover of the pre-Vetro "Cassetta" shell metaphor, kept
// only for timbra_screen.dart's own permanently-dark ground) was removed once Timbra stopped
// using a ScreenHeader at all (2026-08-30, "Hybrid Card Hero").
//
// `HeaderIconBtn.glass` defaults to true — every header action in the app (back chevron, bell,
// profile, a sheet's close button) renders as the flat disc; it is not tied to the header being
// dark, since the header itself now flips light/dark rather than staying permanently dark.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/widgets/screen_header.dart';

void main() {
  group('HeaderIconBtn', () {
    testWidgets('glass defaults to true — the frosted disc, not the squared bg3 fill', (
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
      expect(btn.glass, isTrue);
    });

    testWidgets('glass: false renders the squared bg3 variant when explicitly asked for', (
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

      final container = tester.widget<Container>(
        find.descendant(of: find.byType(HeaderIconBtn), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      // AppRack.insetShape's machined square rather than glass mode's disc radius.
      expect(
        (decoration.borderRadius as BorderRadius?)?.topLeft,
        Radius.circular(AppRack.insetRadius),
      );
    });
  });

  group('ScreenHeader', () {
    testWidgets('renders its title as the flipping flat bar, no BackdropFilter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ScreenHeader(title: 'Test')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ScreenHeader), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);

      // Compared against AppPalette.light's own value, not a raw constant: the bar reads
      // context.colors.surface (themed, flips in dark mode), which merely happens to equal SHEET
      // under the light palette this unthemed MaterialApp falls back to.
      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(ScreenHeader),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(box.color, equals(AppPalette.light.surface));
    });
  });
}
